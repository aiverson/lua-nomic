
local deps = ...

---@module "client-elements"
local elem = deps.elem
---@module "clientmodules.counter"
local counter = deps.counter

local a = counter(0)

local b = counter(7)

return function()
    return elem.div {
        elem.p {
            "Counters: "
        },
        "A: ", a(),
        "B: ", b(),
    }

end