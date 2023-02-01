local json = require 'json' --temporarily use JSON api in lieu of a binary serialization protocol
local object = require 'core'.object

local codec = object:extend()

local magic_field_name = "__magic_field_for_codec_caps"

local releasable_mt = {
    __gc = function(self)
        self.codec:send {
            kind = "release",
            id = self.id
        }
    end
}

local function wrap_func(codec, id)
    local wrapper = setmetatable({codec = codec, id = id}, releasable_mt)
    local function do_call(...)
        local _ = wrapper --pin to function so gc works
        local args = {...}
        return codec:question {
            kind = "call",
            id = id,
            args = args
        }
    end
    return do_call
end

local function wrap_ocap(codec, id)
    --create these as closures so that the access to the codec and ids can't be extracted without the debug api.
    --the debug API should be sandboxed so that it can't be used to extract these either.
    local ref_mt = {
        __gc = function(self)
            codec:send {
                kind = "release",
                id = id
            }
        end,
        __index = function(self, key)
            return codec:question {
                kind = "index",
                id = id,
                key = key
            }
        end
    }
    return setmetatable({}, ref_mt)

end


function codec:initialize(setup)
    self.imports = {}
    self.exports = {}
    self.questions = {}
    self.answers = {}

    self.find_import = {}

    if not setup then setup = {} end
    assert(type(setup) == "table", "codec config must be a table")
    if setup.exports then
        assert(type(setup.exports) == "table", "initial exports must be a sequence table containing functions and ocaps")
        for i, v in ipairs(setup.exports) do
            if type(v) == "function" then
                exports[i] = v
            elseif type(v) == "table" and getmetatable(v) == ocap_mt then
                exports[i] = v
            else
                error(("value at position %d of initial exports must be a function or an ocap but was instead a %s"):format(i, type(v)))
            end

        end
    end

    self.initial_imports = {}
    if setup.imports then
        assert(type(setup.imports) == "table", "initial imports imports must be a sequence table containing strings indicating functions and ocaps")
        for i, v in ipairs(setup.imports) do
            if v == "func" then
                local id = {ref = "import", idx = i}
                local fn = wrap_func(self, id)
                self.find_import[fn] = id
                self.initial_imports[i] = fn
            elseif v == "ocap" then
                local id = {ref = "import", idx = i}
                local obj = wrap_ocap(self, id)
                self.find_import[obj] = id
                self.initial_imports[i] = obj
            else
                error(("initial imports must contain either \"func\" or \"ocap\" but contains something else at position %d"):format(i))
            end
        end
    end


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
