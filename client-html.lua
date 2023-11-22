---@module 'typedef.jsdom'

---@type Document
local doc
---@type string
local root_id
doc, root_id = ...

---@type Document
local document = doc

---@type fun()
local notify

---@class UINode
---@field children UINode[]
---@field attrs table<string, string>
---@field handlers table<string, function>
---@field tag string?
---@field text string
local UINode = {}

---@class UIDesc
---@field [integer] UINode|string
---@field onClick fun()?
local UIDesc = {}

local UINode_mt = {
    __proxy_opaque = true
}

---create a new uinode
---@param tag string
---@param desc UIDesc
---@return UINode
local function new_node(tag, desc)
    ---@type UINode[]
    local children = {}
    for i, v in ipairs(desc) do
        if type(v) == "string" then
            children[i] = {tag = nil, text = v, children = {}, attrs = {}, handlers = {}}
        else
            children[i] = v
        end
    end
    local handlers = {}
    if desc.onClick then
        local onclick = desc.onClick
        ---@cast onclick -nil
        handlers.click = function() onclick(); notify() end
    end
    local attrs = {}
    return setmetatable({tag = tag, children = children, handlers = handlers, attrs = attrs}, UINode_mt)
end

---@type table<UINode, DomNode>
local dom_nodes = {}
---@type UINode
local last_tree

---update a dom node in accordance to a tree
---@param tree UINode
---@param last_tree UINode?
---@param last_elem DomNode?
---@return DomNode
local function build_against(tree, last_tree, last_elem)
    if not last_tree or not last_elem then
        if tree.tag then
            local elem = document:createElement(tree.tag)
            for i, child in ipairs(tree.children) do
                elem:append(build_against(child))
            end
            for k, v in pairs(tree.attrs) do
                elem:setAttribute(k, v)
            end
            for k, v in pairs(tree.handlers) do
                elem:addEventListener(k, v)
            end
            return elem
        else
            return document:createTextNode(tree.text)
        end
    end
    ---@cast last_tree -nil
    ---@cast last_elem -nil
    if tree.tag == last_tree.tag then
        if tree.tag then
            local elem = last_elem
            local size = math.max(#tree.children, #last_tree.children)
            for i = 1, size do
                if not last_tree.children[i] then
                    elem:append(build_against(tree.children[i]))
                elseif not tree.children[i] then
                    elem.lastElementChild:remove()
                else
                    for k, v in pairs(last_tree.attrs) do
                        if not tree.attrs[k] then
                            elem:removeAttribute(k)
                        end
                    end
                    for k, v in pairs(tree.attrs) do
                        elem:setAttribute(k, v)
                    end
                    for k, v in pairs(last_tree.handlers) do
                        if not tree.handlers[k] == v then
                            elem:removeEventListener(k, v)
                        end
                    end
                    for k, v in pairs(tree.handlers) do
                        if not last_tree.handlers[k] == v then
                            elem:addEventListener(k, v)
                        end
                    end
                end
            end
            return elem
        else
            local elem = last_elem
            ---@cast elem DomTextNode
            if tree.text ~= last_tree.text then
                elem.data = tree.text
            end
            return elem
        end
    else
        return build_against(tree)
    end
end

---@class Binding
---@field node DomNode
---@field app fun(): UINode
---@field last UINode

---@type table<Binding, boolean>
local claimed_roots = {}

function notify()
    for binding in pairs(claimed_roots) do
        local node = build_against(binding.app(), binding.last, binding.node)
        if node == binding.node then
            --do nothing
        else
            binding.node:replaceWith(node)
            binding.node = node
        end
    end
end

---claim an element as the root node of an app
---@param node DomNode
---@param app fun():UINode
local function claim_root(node, app)
    claimed_roots[{node = node, app = app, last = nil}] = true
end


return {
    build_against = build_against,
    new_node = new_node,
    notify = notify,
    claim_root = claim_root
}