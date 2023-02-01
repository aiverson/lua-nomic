-- This file handles the creation of worker threads to run client code.
-- It includes the communication apparatus as well as the pool management

--TODO: fix GC of asyncs passed by asyncs between threads. Currently they are all anchored indefinitely so the GC never runs. However, this still needs to be fixed.

--TODO: improve communication protocol so that multiple simultaneous call-returns can be in-flight
--TODO: improve communication protocol so that event streams can be introduced
--TODO: add commands to modify resource limits

-- List of threads available for reuse. Used as a LIFO.
local available = {}
local awaiting = {}

local nAllocated = 0
local maxThreads = 100

local debugMode = true
local debugPrint = debugMode and print or function(...) end

-- The main code of the client threads
local function threadFunc(pipename, workerid, nonce)
    local debugMode = true

    local uv = require 'uv'
    local codec = require './spawner-codec'
    local pipe = uv.new_pipe(false)
    pipe:connect(pipename)

    local msgHandlers = {}

    local function dispatch(msgtype, ...)
        local handler = msgHandlers[msgtype]
        if not handler then error(("invalid message type %q"):format(msgtype)) end
        handler(...)
    end

    local recieveHandler = function(err, data, ...)
        debugPrint(err, data, ...)
        if err then return end
        dispatch(table.unpack(data))
    end
    pipe:read_start(codec.decode(recieveHandler))
    local send = codec.encode(function(data) pipe:write(data) end)


    -- Parameters for resource limitations
    local insLimit = 1000000 --16384  -- Maximum number of VM instructions allowed to the client code
    local memLimit = 10000 --128    -- Memory limit in Kilobytes
    local checkFreq = 256   -- How frequently the limits are checked
    local inscount = 0      -- Number of instructions already used

    local printidx = 0
    print = function(...)
        args = {...}
        printidx = printidx + 1
        for i = 1, select('#', ...) do args[i] = tostring(args[i]) end
        io.write("["..uv.now()..":"..printidx..":worker "..workerid.."]\t"..table.concat(args, "\t").."\n")
    end
    
    debugPrint = debugMode and print or function(...) end

    --prevent resource kills in protected functions corresponding to internal infrastructure
    local protected = setmetatable({}, {__mode = "k"})
    local function protect(func)
        protected[func] = true
        return func
    end

    protect(print)
    protect(debugPrint)
    protect(recieveHandler)
    protect(dispatch)
    
    -- The debug hook function that counts the resource usage to prevent overconsumption by client code.
    local function hook(event, line)
        if event == "count" then
            inscount = inscount + checkFreq
            if inscount > insLimit or collectgarbage("count") > memLimit then
                if not protected[debug.getinfo(1).func] and not protected[coroutine.running()] then
                    debugPrint("killed code for resource limits", debug.traceback())
                    error(killErr)
                end
            end
        end
    end

    local callIdx = 1

    local pendingReturns = {}
    local commands = {}

    local killErr = {} --Empty table, unique unreplicatable identity to ensure that it is different from anything client code can generate. MUST NEVER BE PASSED INTO CLIENT CODE IN ANY WAY.
    --Every piece of code that accepts a callback from client code must pcall it and check for killErr and call cleanupKill if it is present

    local killed = false
    local running = true

    -- Handle returns from proxied calls. Accept the return value, dispatch the next pending call if one exists, and send the return values back to the callback.
    local function returnHandler(id, ...)
        debugPrint("recieved return ", id, ...)
        if type(id) == "number" then
            if pendingReturns[id] then
                debugPrint("dispatching pending return for "..id)
                local handler
                handler, pendingReturns[id] = pendingReturns[id], nil
                handler(id, ...)
            else
                --debugPrint "recieved return with bad id"
            end
        else
            -- There shouldn't be anything needed here
            error "recieved return with nonnumeric id"
        end
    end

    protect(returnHandler)
    msgHandlers["return"] = returnHandler

    -- Handle recieved commands by looking them up in the commands table and executing the requested operation
    local function commandHandler(name, ...)
        send({"ack", name})
        debugPrint("recieved command ", name, ...)
        if not commands[name] then
            return --error("Recieved invalid command "..tostring(name))
        end
        commands[name](...)
    end
    
    msgHandlers.command = commandHandler

    protect(commandHandler)

    local finishedCheck = uv.new_check()

    local saved_hook

    -- Clean up the client code after a forced termination. Remove the debugging hook that tracks resource usage, send info back to the host, and reset callback info.
    local function cleanupKill() 
        debug.sethook(table.unpack(saved_hook))
        jit.on()
        killed = true
        pendingReturns = {}
        pendingSends = {}
        finishedCheck:stop()
        if running then
            send({"die"})
            debugPrint("killed spawned code", debug.traceback())
        end
        running = false
        collectgarbage("collect")
    end
    protect(cleanupKill)

    -- Clean up the client code after a clean termination. Remove the debugging hook that tracks resource usage, send info back to the host, and reset callback info.
    local function cleanupFinish() 
        debug.sethook(table.unpack(saved_hook))
        jit.on()
        pendingReturns = {}
        pendingSends = {}
        if running then
            send({"finish"})
            debugPrint("spawned code finished", debug.traceback())
        end
        running = false
        collectgarbage("collect")
    end
    protect(cleanupFinish)

    -- wait until all callbacks registered by the wrapped code have finished.
    local function waitForCallbacks() 
        local coro = coroutine.running()
        local function validate()
            if not next(pendingReturns) then
                assert(coroutine.resume(coro))
            end
        end
        finishedCheck:start(validate)
        coroutine.yield()
        finishedCheck:stop()
    end
    protect(waitForCallbacks)

    -- proxy a call across the threads to invoke a function on the master and sets the callback on the result to resume the current coroutine with the resulting values
    local function remoteCall(name, ...) 
        debugPrint("calling remote from ", coroutine.running(), name, ...)
        send{"call", callIdx, name, ...}
        local coro = coroutine.running()
        local function callback(id, ...)
            debugPrint("callback got", ...)
            local ok, err = coroutine.resume(coro, ...)
            if not ok then
                print("code died with error ", err)
                cleanupKill()
            end
        end
        protect(callback)
        pendingReturns[callIdx] = callback
        callIdx = callIdx + 1
        local vals = {coroutine.yield()}
        debugPrint("caller resumed", (coroutine.running()), table.unpack(vals))
        assert(table.unpack(vals))
        return table.unpack(vals, 2)
    end

    local function copyTable(tbl, names, blacklist) -- make a copy of a table for use in building a new environment
        local res = {}
        if not names or blacklist then
            for k, v in pairs(tbl) do
                res[k] = v
            end
            if names then
                for _, k in ipairs(names) do
                    res[k] = nil
                end
            end
        else
            for i = 1, #names do
                res[names[i]] = tbl[names[i]]
            end
        end
        return res
    end
    
    local function makeEnv(sandboxed, proxies) --Build the global environment that sandboxed code will be executed inside
        local globalFuncs
        --TODO: sandbox setmetatable. setting an __gc metamethod can escape resource limits and lock up the thread indefinitely. It can't get access to anything outside of the container though.
        if sandboxed then
            globalFuncs = {"assert", "error", "getmetatable", "ipairs", "next", "pairs", "rawequal", "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "_VERSION"}
        else
            globalFuncs = {"assert", "error", "getmetatable", "ipairs", "next", "pairs", "print", "rawequal", "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "_VERSION"} -- TODO: make the unsandboxed environment
        end
        local env = copyTable(_G, globalFuncs)
        env.coroutine = copyTable(coroutine, {"create", "yield", "status"}) -- Wrap and resume provided later
        env.string = copyTable(string)
        env.table = copyTable(table)
        env.math = copyTable(math, {"randomseed"}, true)
        env.bit = copyTable(bit)
        env._G = env
        
        
        local function pcall_handler(ok, err, ...) -- Automatically propagate kill codes through error handling to prevent using any protected mode to avoid a kill signal.
            if not ok and rawequal(err, killErr) then
                error(err)
            end
            return ok, err, ...
        end
        
        env.pcall = function(func, ...)
            return pcall_handler(pcall(func, ...))
        end
        
        env.xpcall = function(func, msgh, ...)
            local function wrapped_handler(err)
                if rawequal(err, killErr) then
                    return err
                else
                    return msgh(err)
                end
            end
            return pcall_handler(xpcall(func, wrapped_handler, ...))
        end
        
        env.load = function(ld, source, mode, subenv) -- Only allow loading text mode code to prevent inserting malformed bytecode
            if not source then source = "=(load)" end
            if not subenv then subenv = env end
            mode = "t"
            return load(ld, source, mode, subenv)
        end

        -- TODO: Patch the coroutines so that generator style usage works with proxied calls inside the generator
        env.coroutine.resume = function(coro, ...)
            return pcall_handler(coroutine.resume(coro, ...))
        end

        env.coroutine.wrap = function(func)
            local coro = coroutine.create(func)
            return function(...)
                return pcall_handler(coroutine.resume(coro, ...))
            end
        end
        
        for i, name in ipairs(proxies) do -- Unpack proxied calls into the environment
            env[name] = function(...)
                return remoteCall(name, ...)
            end
        end
        return env
    end

    local function splitProxies(proxies)
        local g = require 'lpeg'
        local locale = g.locale()
        local name = g.C(locale.alnum ^ 1)* -locale.alnum
        local pattern = g.Ct(name * (g.P"," * name)^0 + -1)
        local list = pattern:match(proxies)
        return list
    end
    
    local function run(proxies, code, ...)
        debugPrint("entering run function proxies: ", proxies)
        killed = false
        running = true
        inscount = 0
        local cleanclosed = false
        
        local wrapfunc, err = load(code, "=(eval)", "bt", makeEnv(true, splitProxies(proxies)))
        --print("run function: code loaded", func, err)
        if not wrapfunc then return print(err) end
        local func = function(...) local ok, res = pcall(wrapfunc, ...) if not ok then cleanupKill() else cleanupFinish() end end

        local inner = function(...)
            local ok, res = coroutine.resume(coroutine.create(func), ...)
            if not ok then print(res, debug.stacktrace()) return cleanupKill(res) end
            waitForCallbacks()
            if not killed then cleanupFinish() end
            cleanclosed = true
        end
        protect(inner)

        saved_hook = {debug.gethook()}
        debugPrint "began running spawned code"
        jit.off()
        debug.sethook(hook, "", 256)

        local coro = protect(coroutine.create(inner))

        local ok, res = coroutine.resume(coro, ...)
        --[[if running then
            if not ok then
                cleanupKill(res)
            else
                cleanupFinish(res)
            end
        end]]
        --print("exiting run function")
    end

    commands.run = run
    commands.kill = cleanupKill

    send{"status", "initialize", workerid, nonce}

    uv.run()

end

local uv = require 'uv'
local path = require 'path'
local fs = require 'fs'
local codec = require './spawner-codec' --TODO: Switch from JSON to a minimalistic binary protocol.
local thread = require 'thread' --TODO: consider removing dependency after switching the codec to use a non-json protocol

local wrapper_mt = {
    __index = {
        corecalls = {
            [0] = function(self, rets, cmds)  -- Configure returns and commands
                self.rets, self.cmds = rets, cmds
                if self.notifyReady then
                    self:notifyReady()
                    self.notifyReady = nil
                end
            end,
            [1] = function(self) -- die
                coroutine.wrap(function()
                    self.running = false
                    debugPrint("["..uv.now()..":host "..self.workerid.."]\tworker died", self.finishNotify)
                    if self.finishNotify then
                        local notify
                        notify, self.finishNotify = self.finishNotify, nil
                        notify(self, false)
                    end
                    available[#available+1] = self
                end)()
            end,
            [2] = function(self) -- finished
                coroutine.wrap(function()
                    self.running = false
                    debugPrint("["..uv.now()..":host "..self.workerid.."]\tworker finished", self.finishNotify)
                    if self.finishNotify then
                        local notify
                        notify, self.finishNotify = self.finishNotify, nil
                        notify(self, true)
                    end
                    available[#available+1] = self
                end)()
            end,
        },
        -- run some code on the thread
        run = function(self, cb, proxies, func, ...)
            local names = {}
            for k, v in pairs(proxies) do
                names[#names+1] = k
            end
            self.usercalls = proxies
            local list = table.concat(names, ",")
            local code
            if type(func) == "string" then
                code = func
            elseif type(func) == "function" then
                code = string.dump(func, false)
            else
                error "invalid argument func, must be a function or a string containing valid code"
            end
            self.running = true
            local coro = coroutine.running()
            self.finishNotify = cb
            self:sendCommand("run", list, code, ...)
            return self
        end,
        -- force kill the thread's code
        kill = function(self)
            self:sendCommand("kill")
        end,
        handlers = {
            -- handle a call proxied from the thread
            call = function(self, idx, name, ...)
                debugPrint("["..uv.now()..":host "..self.workerid.."]\tcalling", idx, name, ...)
                if idx == nil or name == nil then
                    print("invalid call ", debug.traceback())
                    return --error("invalid call")
                end
                if self.corecalls[name] then
                    self.corecalls[name](self, ...)
                elseif self.usercalls[name] then
                    coroutine.wrap(function(self, idx, name, ...)
                        local vals = {pcall(self.usercalls[name], self, ...)}
                        debugPrint("["..uv.now()..":host "..self.workerid.."]\treturning", idx, name, table.unpack(vals))
                        self.send{"return", idx, table.unpack(vals)}
                    end)(self, idx, name, ...)
                end
            end,
            -- Handle a command acknowledgement from the thread
            ack = function(self, ...)
                --print("command acknowledged")
                local cb = table.remove(self.pendingAcks, 1)
                if cb then return cb(...) end
            end,
            die = function(self)
                coroutine.wrap(function()
                    self.running = false
                    available[#available+1] = self
                    debugPrint("["..uv.now()..":host "..self.workerid.."]\tworker died leaving n available workers", #available, self.finishNotify)
                    if self.finishNotify then
                        local notify
                        notify, self.finishNotify = self.finishNotify, nil
                        coroutine.wrap(notify)(self, false)
                    end
                end)()
            end,
            finish = function(self)
                coroutine.wrap(function()
                    self.running = false
                    available[#available+1] = self
                    debugPrint("["..uv.now()..":host "..self.workerid.."]\tworker finished leaving n available workers", #available, self.finishNotify)
                    if self.finishNotify then
                        local notify
                        notify, self.finishNotify = self.finishNotify, nil
                        coroutine.wrap(notify)(self, true)
                    end
                end)()
            end,
        },
        -- Send a command to the thread
        sendCommand = function(self, name, ...)
            --print ("sending command", name, ...)
            --self.commandWaiting = coroutine.running()
            if not name then error "attempted to send nil command" end
            self.send{"command", name, ...}
            table.insert(self.pendingAcks, function() end)
            --local a, b, c, d, e, f, g, h, i, j = coroutine.yield() -- suppress tail call optimization for debugging
            --return a, b, c, d, e, f, g, h, i, j
        end,
        dispatch = function(self, data)
            debugPrint("master handling", table.unpack(data))
            if self.handlers[data[1]] then
                self.handlers[data[1]](self, table.unpack(data, 2))
            end
        end

    }
}

local pipedir = path.join(uv.cwd(), 'tmp', tostring(uv.getpid()))
fs.mkdirSync(pipedir, "700")
local pipepath = path.join(pipedir, "workers")
local pipe = uv.new_pipe(false)
pipe:bind(pipepath)

local pendingConnects = {} -- [id] = {nonce, callback}


pipe:listen(128, function()
    local client = uv.new_pipe(false)
    pipe:accept(client)
    local handler
    local function dispatch(err, data)
        --p("codec raw", err, data)
        if err then return end
        if handler then return handler(data) end
        local category, eventid, workerid, nonce = table.unpack(data)
        if category == "status" and eventid == "initialize" then
            if pendingConnects[workerid] and pendingConnects[workerid][1] == nonce then
                handler = pendingConnects[workerid][2]
                handler{"status", "initialize", codec.encode(function(data) client:write(data) end)}
                pendingConnects[workerid] = nil
            end
        end
    end
    client:read_start(codec.decode(dispatch))
end)


-- Select an available thread or create a new thread if no thread is available
local function getThread()
    if #available > 0 then
        local selected = available[#available]
        available[#available] = nil
        return selected
    elseif nAllocated < maxThreads then
        local coro = coroutine.running()
        local thr = setmetatable({
            workerid = nAllocated,
            notifyReady = function(data) assert(coroutine.resume(coro, data)) end,
            pendingCommands = {},
            pendingAcks = {},
        }, wrapper_mt)
        local function handler(data)
            
        end
        local bytes = {}
        for i = 1, 128 do
            bytes[i] = math.random(0, 255)
        end
        local nonce = string.char(table.unpack(bytes))
        pendingConnects[nAllocated] = {nonce, function(data)
            if data[1] == "status" and data[2] == "initialize" then
                thr.send = data[3]
                if coro then
                    coroutine.resume(coro, thr)
                    coro = nil
                end
            else
                thr:dispatch(data)
            end
        end}
        thread.start(threadFunc, pipepath, nAllocated, nonce)
        nAllocated = nAllocated + 1
        print("new thread allocated, now at", nAllocated)
        return (coroutine.yield()) --prevent tail call optimizations so call stack is preserved for debugging
    else
        error "Too many active threads"
    end
end

local function run(cb, proxies, func, ...)
    return getThread():run(cb, proxies, func, ...)
end

return {run = run}