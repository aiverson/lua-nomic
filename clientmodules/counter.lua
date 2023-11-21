

local deps = ...

---@module "client-elements"
local elem = deps.elem

---@param start integer
return function(start)
    local counter = start
    return function()
        return elem.div {
            elem.button {
                onClick = function() counter = counter + 1 end,
                "+"
            },
            tostring(counter),
            elem.button {
                onClick = function ()
                    counter = counter - 1
                end,
                "-"
            }
        }
    end

end