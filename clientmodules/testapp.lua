
local deps = ...

---@module "client-elements"
local elem = deps.elem
---@module "clientmodules.counter"
local counter = deps.counter

local all_counters = {
	counter(0),
	counter(7),
}
local n_counters = 2

return function()
    local desc = {
        elem.button {
            onClick = function() all_counters[n_counters + 1] = counter(0) n_counters = n_counters + 1 end,
            "+"
        },
        elem.p {
            "Counters: "
        },
    }
    for i = 1, n_counters do
	    local j = i * 2 + 1
	    desc[j] = string.char(64 + i) .. ":"
	    desc[j+1] = all_counters[i]()
    end
    return elem.div(desc)

end
