

local deps = ...

---@module "client-html"
local html = deps.html
local elems = html.elems
local attrs = html.attrs
local handlers = html.handlers

---@param start integer
return function(start)
    local counter = start
    return {
        get_count = function()
            return counter
        end,
        render = function()
            return elems.div {
                elems.button {
                    handlers.onClick(function() counter = counter + 1 end),
                    "+"
                },
                tostring(counter),
                elems.button {
                    handlers.onClick(function ()
                        counter = counter - 1
                    end),
                    "-"
                }
            }
        end
    }
end
