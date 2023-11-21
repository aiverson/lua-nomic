
---@module "client-html"
local html = ...

---comment
---@param tag string
---@return fun(desc: UIDesc): UINode
local function b(tag)
    return function(desc)
        return html.new_node(tag, desc)
    end
end

local elements = {
    p = b"p",
    span = b"span",
    div = b"div",
    button = b"button",
}

return elements