local json = require 'json' --temporarily use JSON api in lieu of a binary serialization protocol
local object = require 'core'.object

local codec = object:extend()

local magic_field_name = "__magic_field_for_codec_caps"

local releasable_mt = {
    __gc = function(self)
        self.codec:release(self.id, self.count)
    end
}

local ref_mt = {}

local function wrap_func(codec, id)
    local wrapper = setmetatable({codec = codec, id = id, count = 1}, releasable_mt)
    local function do_call(...)
        local _ = wrapper --pin to function so gc works
        return codec:call(id, ...)
    end
    return do_call, wrapper
end

local function wrap_remote(codec, id)
    --create these as closures so that the access to the codec and ids can't be extracted without the debug api.
    --the debug API should be sandboxed so that it can't be used to extract these either.
    local countstore = {count = 1}
    local ref_mt = {
        __gc = function(self)
            codec:release(id, countstore.count)
        end,
        __index = function(self, key)
            return codec:index(id, key)
        end,
        __call = function(self, ...)
            return codec:call(id, ...)
        end
        -- no other ops are currently supported
    }
    return setmetatable({}, ref_mt), countstore

end


function codec:initialize(setup)
    self.imports = {}
    self.exports = {}
    self.questions = {}
    self.answers = {}

    self.find_shared = {}

    if not setup then setup = {} end
    assert(type(setup) == "table", "codec config must be a table")
    if setup.exports then
        assert(type(setup.exports) == "table", "initial exports must be a sequence table containing functions and ocaps")
        for i, v in ipairs(setup.exports) do
            if type(v) == "function" then
                exports[i] = {val = v, count = 1}
            elseif type(v) == "table" and getmetatable(v) == ocap_mt then
                exports[i] = {val = v, count = 1}
            else
                error(("value at position %d of initial exports must be a function or an ocap but was instead a %s"):format(i, type(v)))
            end

        end
    end

    self.initial_imports = {}
    if setup.imports then
        assert(type(setup.imports) == "number", "initial imports imports must be a count of how many initial imports are expected")
        for i = 1, setup.imports do
            local id = {ref = "import", idx = i}
            local obj, ref = wrap_remote(self, id)
            self.find_shared[obj] = id
            self.initial_imports[i] = obj
            self.imports[i] = {val = obj, ref = ref}
        end
    end

    assert((type(setup.writer) == "function", "must have a write function to write buffers to")
    self.writer = setup.writer


end

local writeslot_mt = {
    __index = {
        set = function(self, str)
            if self.used then
                error "this slot was already used; a slot should be used exactly once"
            end
            self.buffer[self.pos] = str
            self.used = true
            self.buffer.outstanding_slots = self.buffer.outstanding_slots - 1
        end,
        elide = function(self)
            if self.used then
                error "this slot was already used; a slot should be used exactly once"
            end
            self.buffer[self.pos] = ""
            self.used = true
            self.buffer.outstanding_slots = self.buffer.outstanding_slots - 1
        end
    }
}

local function new_writeslot(buffer, pos)
    return setmetatable({buffer = buffer, pos = pos, used = false}, writeslot_mt)
end

local writebuffer_mt = {
    __index = {
        append = function(self, str)
            self.n = self.n + 1
            self[self.n] = str
        end,
        reserve = function(self)
            self.n = self.n + 1
            self.outstanding_slots = self.outstanding_slots + 1
            return new_writeslot(self, self.n)
        end,
        tostring = function(self)
            if self.outstanding_slots != 0 then
                error "not all reserved slots have been resolved."
            end
            return table.concat(self, "")
        end
    }
}

local function new_writebuffer()
    return setmetatable({n = 0, outstanding_slots = 0}, writebuffer_mt)
end

local flagcodes = {
    nil = 0,
    false = 1,
    true = 2,
    smallint = 4,
    int = 5,
    number = 6,
    shortstring = 7,
    longstring = 8,
    shorttable = 9,
    longtable = 10,
    tableterm = 11, --TODO: use a nil instead
    export = 12,
    import = 13,
    answer = 14,
}


local function serialize_message(codec, val, buff)
    if self.find_shared[val] then
        local id = self.find_shared[val]
        if id.ref == "import" then
            buff:append(string.pack("<!1 I1 I4", flagcodes.imported, id.idx))
        elseif id.ref == "question" then
            buff:append(string.pack("<!1 I1 I4", flagcodes.answer, id.idx))
        elseif id.ref == "export" then
            buff:append(string.pack("<!1 I1 I4", flagcodes.exported, id.idx))
            codec.exports[id.idx].count = codec.exports[id.idx].count + 1
        else
            error("tried to serialize something recognized as a known shared reference but somehow neither an import or an answer to a question or an existing export")
        end

    elseif type(val) == "table" then
        local mt = getmetatable(val)
        if mt then
            if mt == ref_mt then
                buff:append(string.pack("<!1 I1 I4", flagcodes.exported, codec:export(val)))
            else
                error "tried to send something with a metatable that wasn't a ref. This isn't allowed. Construct a cap wrapping it."
            end
        else
            local count = #val
            if count < 256 then
                buff:append(string.pack("<!1 I1 I1", flagcodes.shorttable, count))
            else
                buff:append(string.pack("<!1 I1 I4", flagcodes.longtable, count))
                -- if anyone ever tries to send a four billion element sequence in one message, I will hunt them down. Use a backpressured stream if you must, or better yet, don't.
            end
            for i = 1, count do
                serialize_message(codec, val[i], buff)
            end
            for k, v in pairs(val) do
                if type(k) ~= "number" or k < 1 or k > count or k % 1 ~= 0 then
                    serialize_message(codec, k, buff)
                    serialize_message(codec, v, buff)
                end
            end
            buff:append(string.pack("<!1 I1", flagcodes.tableterm))

        end
    elseif type(val) == "string" then
        if #val < 256 then
            buff:append(string.pack("<!1 s1", val))
        else
            buff:append(string.pack("<!1 s4", val))
            -- same story for four gigabyte buffer. backpressured stream or don't
        end
    elseif type(val) == "number" then
        if val % 1 == 0 and val < 2 ^ 31 and val >= -(2^31) then
            if val < 128 and val >= -128 then
                buff:append(string.pack("<!1 I1 i1", flagcodes.smallint, val))
            else
                buff:append(string.pack("<!1 I1 i4", flagcodes.int, val))
            end
        else
            buff:append(string.pack("<!1 I1 d", flagcodes.number, val))
        end


    elseif type(val) == "thread" then
        error "tried to send a coroutine. This isn't allowed. Wrap it in a function or reference."
    elseif type(val) == "function" then
        buff:append(string.pack("<!1 I1 I4", flagcodes.exported, codec:export(val)))
    elseif type(val) == "bool" then
        buff:append(string.pack("<!1 I1", val and flagcodes.true or flagcodes.false))
    elseif val == nil then
        buff:append(string.pack("<!1 I1", flagcodes.nil))
    elseif type(val) == "userdata" then
        error "tried to send userdata. This isn't allowed. Wrap it in an opaque reference or an ocap providing the api"
    else
        error "tried to send something that wasn't one of the known lua types. This definitely isn't allowed."
    end
end

local function deserialize_message(codec, buff, pos)
    local code, pos = string.unpack("<!1 I1", buff, pos)
    if code == flagcodes.nil then
        return nil, pos
    elseif code == flagcodes.true then
        return true, pos
    elseif code == flagcodes.false then
        return false, pos
    elseif code == flagcodes.smallint then
        return string.unpack("<!1 i1", buff, pos)
    elseif code == flagcodes.int then
        return string.unpack("<!1 i4", buff, pos)
    elseif code == flagcodes.number then
        return string.unpack("<!1 d", buff, pos)
    elseif code == flagcodes.shortstring then
        return string.unpack("<!1 s1", buff, pos)
    elseif code == flagcodes.longstring then
        return string.unpack("<!1 s4", buff, pos)
    elseif code == flagcodes.shorttable then
        local seqlen, pos = string.unpack("<!1 I1", buff, pos)
        local tab = {}
        for i = 1, seqlen do
            tab[i] = deserialize_message(codec, buff, pos)
        end
        local key, val
        key, pos = deserialize_message(codec, buff, pos)
        while key ~= nil do
            val, pos = deserialize_message(codec, buff, pos)
            tab[key] = val
            key, pos = deserialize_message(codec, buff, pos)
        end
        return tab, pos
    elseif code == flagcodes.longtable then
        local seqlen, pos = string.unpack("<!1 I4", buff, pos)
        local tab = {}
        for i = 1, seqlen do
            tab[i] = deserialize_message(codec, buff, pos)
        end
        local key, val
        key, pos = deserialize_message(codec, buff, pos)
        while key ~= nil do
            val, pos = deserialize_message(codec, buff, pos)
            tab[key] = val
            key, pos = deserialize_message(codec, buff, pos)
        end
        return tab, pos
    elseif code == flagcodes.tableterm then
        return nil, pos
    elseif code == flagcodes.export then
        local idx, pos = string.unpack("<!1 I4", buff, pos)
        return codec:import(idx), pos
    elseif code == flagcodes.import then
        local idx, pos = string.unpack("<!1 I4", buff, pos)
        return codec.exports[idx].val
    elseif code == flagcodes.answer then



end

function codec:send(self, val)

end


function codec:decode(self, callback)
    --TODO: Handle partially written buffers
    local buffer = ""
    local function handler(err, data)
        if err then
            callback(err, data)
        else
            buffer = buffer .. data
            local val, len, msg = nil, 0, nil
            repeat
                buffer = buffer:sub(len)
                --print(buffer)
                val, len, msg = json.decode(buffer)
                if not val and len < #buffer then
                    callback(msg)
                    buffer = nil
                end
                if val then
                    callback(err, val)
                end
            until len >= #buffer
            buffer = ""
        end
    end
    return handler
end

function codec:encode(callback)
    local function handler(data)
        callback(json.encode(data))
    end
    return handler
end

return M
