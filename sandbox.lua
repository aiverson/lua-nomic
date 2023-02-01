-------------------------------------------------------------------------------
-- file: sandbox.lua
--
-- author: Alex Iverson
--
-- brief: Create a sandbox for player code
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- function: cloneTab
--
-- brief: Clone a table
-------------------------------------------------------------------------------
local function cloneTab(tab)
  local clone = {}
  for k, v in pairs(tab) do
    clone[k] = v
  end
end

-------------------------------------------------------------------------------
-- function: createEnv
--
-- brief: Generate the sandboxed environment
--
-- returns: New globals environment which disallows some functionality
-------------------------------------------------------------------------------
local function createEnv()
  local globals = {
    string = cloneTab(string), --TODO: sandbox string functions for memory usage
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    pcall = pcall,
    error = error,
    tonumber = tonumber,
    tostring = tostring,
    rawequal = rawequal,
    rawget = rawget,
    rawlen = rawlen,
    rawset = rawset,
    math = cloneTab(math),
    assert = assert,
    pairs = pairs,
    ipairs = ipairs,
    select = select,
    type = type,
    xpcall = xpcall,
    table = cloneTab(table) --TODO: add cost for table.sort
  }
  globals._G = globals
  return globals
end

return {
  createEnv = createEnv
}
