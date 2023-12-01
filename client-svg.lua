
---@module "client-dom"
local dom = ...

---comment
---@param tag string
---@return fun(desc: UIDesc): UINode
local function b(tag)
    return function(desc)
        return dom.new_node(tag, desc, "http://www.w3.org/2000/svg")
    end
end

---@param name string
---@return fun(value: string|boolean|integer): UIAttribute
local function attr(name)
    return function(value)
        return dom.new_attribute(name, value)
    end
end

---@param name string
---@return fun(value: function): UIHandler
local function handler(name)
    return function(value)
        return dom.new_handler(name, value)
    end
end

local elems = {
    svg = b"svg",
    a = b"a",
    path = b"path",
}

local attrs = {
    d = attr"d",
    width = attr"width",
    height = attr"height",
    viewBox = attr"viewBox",
}

local handlers = {
    ---@type fun(value: fun()): UIHandler
    onClick = handler"click",
}

return {
    elems = elems,
    attrs = attrs,
    handlers = handlers,
}
