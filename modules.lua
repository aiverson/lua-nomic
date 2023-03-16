

local proxy_origins = setmetatable({}, {__mode = 'k'}})
local proxy_owners = setmetatable({}, {__mode = 'k'})
local proxy_refs = setmetatable({}, {__mode = 'k'})

local error_kill_flag = {}

local proxy_get

local module_proxy_of_mt = {__mode = 'v'}

local root_module = {proxy_of = setmetatable({}, module_proxy_of_mt)}

local function translate(obj, module_src, module_dst) -- translate values across a module boundary to maintain sandboxing
  if proxy_origins[obj] == module_dst then -- the object is a proxy for an object which lives in the destination module
    return proxy_refs[obj] -- the original object living in the destination module should be used
  elseif proxy_refs[obj] then -- the object is a proxy which doesn't live in the destination module
    return proxy_get(proxy_refs[obj], module_src, module_dst) -- get a proxy specific to the destination module to prevent pollution if some module decided to use raw methods to mutate their local proxy
  end
  local t = type(obj)
  if t == 'string' or t == 'number' or t == 'boolean' or t == 'nil' then
    return obj -- immutable primitives and string may be passed directly
  elseif t == "table" then
    local mt = getmetatable(t)
    return proxy_get(obj, module_src, module_dst)
  elseif t == "function" then
    return proxy_get(obj, module_src, module_dst)
  else
    error "NYI unsupported translation between modules, this needs to be expanded"
  end
end

local function translate_args_inner(module_src, module_dst, count, arg, ...)
  if count > 1 then
    return translate(arg, module_src, module_dst), translate_args_inner(module_src, module_dst, count - 1, ...)
  else
    return translate(arg, module_src, module_dst)
  end
end
local function translate_args(module_src, module_dst, ...) -- convenience function for translating a list of args all at once
  local count = select('#', ...)
  if count == 0 then return end
  return translate_args_inner(module_src, module_dst, count, ...)
end

local function cloneTab(tab)
  if tab == nil then return nil end
  local clone = {}
  for k, v in pairs(tab) do
    clone[k] = v
  end
end

local function sandboxed_getmetatable(obj)
  if type(obj) == 'string' then --strings have a shared metatable, so this forbids the global mutable state
    return "string"
  else
    return getmetatable(obj)
  end
end

local proxy_mt = { -- metatable for proxies
  __metatable = "proxy",
  __index = function(self, k) return translate(proxy_refs[self][k], proxy_origins[self], proxy_owners[self]) end,
  __newindex = function(self, k, v) proxy_refs[self][k] = translate(v, proxy_owners[self], proxy_origins[self]) end,
  __call = function(self, ...)
    return
      translate(
        proxy_refs[self](
          translate_args(proxy_owners[self], proxy_origins[self], ...)
                        ),
        proxy_origins[self], proxy_owners[self]
      )
  end,
  __tostring = function(self) return tostring(proxy_refs[self]) end,
  __uncall = function(self)
    return uncall(proxy_origins[self])
  end,
}

function proxy_get(object, module_src, module_dst) -- proxy an object from the source module to the dest, reusing a proxy if possible
  if module_dst.proxy_of[object] then return module_dst.proxy_of[object] end
  local proxy = setmetatable({}, proxy_mt)
  proxy_origins[proxy] = module_src
  proxy_owner[proxy] = module_dst
  proxy_ref[proxy] = object
  module_dst.proxy_of[object] = proxy
  return proxy
end


local function pcall_handler(ok, err, ...) -- Automatically propagate kill codes through error handling to prevent using any protected mode to avoid a kill signal.
    if not ok and rawequal(err, error_kill_flag) then
        error(err)
    end
    return ok, err, ...
end

local sandboxed_pcall = function(func, ...)
    return pcall_handler(pcall(func, ...))
end

local sandboxed_xpcall = function(func, msgh, ...)
    local function wrapped_handler(err)
        if rawequal(err, error_kill_flag) then
            return err
        else
            return msgh(err)
        end
    end
    return pcall_handler(xpcall(func, wrapped_handler, ...))
end

local function env_create(module)
  local env = {
    assert = assert,
    -- collectgarbage is forbidden to prevent messing with memory tracking
    -- dofile is forbidden because there is no default filesystem access
    error = error -- this will probably need to be sandboxed in the future to allow errors with nonstring values
    -- _G added later
    getmetatable = sandboxed_getmetatable,
    ipairs = ipairs,
    load = function(ld, source, mode, subenv)
      if not source then source = "=(load)" end
      if not subenv then subenv = env end
      mode = "t"
      return load(ld, source, mode, subenv)
    end,
    -- loadfile is forbidden because there is no default filesystem access
    next = next,
    pairs = pairs,
    pcall = sandboxed_pcall,
    -- print needs to be implemented with some kind of logging system to make the module output available rather than just dumping to stdout
    rawequal = rawequal,
    rawget = rawget,
    rawlen = rawlen,
    rawset = rawset,
    select = select,
    setmetatable = setmetatable,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    _VERSION = _VERSION,
    xpcall = sandboxed_xpcall,

    coroutine = {
      create = coroutine.create,
      isyieldable = coroutine.isyieldable,
      resume = function(co, ...)
        return translate_args(root_module, module, coroutine.resume(co, translate_args(module, root_module, ...)))
      end,
      running = coroutine.running,
      status = coroutine.status,
      wrap = function(f)
        local function wrapped_f(...)
          return translate_args(module, root_module, f(translate_args(root_module, module, ...)))
        end
        local co = coroutine.create(wrapped_f)
        return function(...)
          return translate_args(root_module, module, coroutine.resume(translate_args(module, root_module, ...)))
        end
      end,
      yield = function(...)
        return translate_args(root_module, module, coroutine.yield(translate_args(module, root_module, ...)))
      end,
    },

    -- require must be set up to permit loading whitelisted packages from source and retrieving injected dependencies on other modules
    -- package configuration table is forbidden because it of filesystem and mutable global state

    string = cloneTab(string), -- string library is safe
    utf8 = cloneTab(utf8), -- if utf8 lib is available, it is fine
    table = cloneTab(table),
    bit = cloneTab(bit),
    math = cloneTab(math),
    -- io is forbidden
    -- os is forbidden
    -- debug is forbidden pending a sandboxed version

  }
  return env
end


local function module_create(code, source, ...)
  local module = {proxy_of = setmetatable({}, module_proxy_of_mt)}
  local env = env_create(module)
  local fn, err = env.load(code, source or '=(module_create)')
  return translate_args(module, root_module, fn, err)
end
