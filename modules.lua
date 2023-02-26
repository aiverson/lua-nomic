

local coro_assocs = setmetatable({}, {__mode = 'k'})
local func_assocs = setmetatable({}, {__mode = 'k'})
local table_assocs = setmetatable({}, {__mode = 'k'})

local error_kill_flag = {}

local function cloneTab(tab)
  local clone = {}
  for k, v in pairs(tab) do
    clone[k] = v
  end
end

local function sandboxed_getmetatable(obj)
  if type(obj) == 'string' then
    return nil
  else
    return getmetatable(obj)
  end
end

local function sandboxed_coroutine_create(fn)
  local coro = coroutine.create(fn)
  coro_assocs[coro] = coro_assocs[coroutine.running()]
  return coro
end


local function env_create()
  local env = {
    tonumber = tonumber

  }
  return env
end

local function module_create(code, source, ...)
  local env = env_create()
  local fn, err = env.load(code, source or '=(module_create)')
