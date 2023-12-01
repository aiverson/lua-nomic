---@module 'typedef.jsdom'

---@type Document
local doc
---@type CSSStyleSheet
local style_sheet
---@type string
local root_id
doc, style_sheet, root_id = ...

---@type Document
local document = doc

---@type fun()
local notify

---@class UINode
---@field children UINode[]
---@field attrs table<string, string>
---@field handlers table<string, function>
---@field styles UIStyle[]
---@field tag string?
---@field text string
---@field namespace string?
local UINode = {}

local UINode_mt = {
    __proxy_opaque = true
}

---@class UIDesc
---@field [integer] UINode|UIAttribute|UIHandler|UIStyle|string
local UIDesc = {}

---@class UIAttribute
---@field name string
---@field value string
local UIAttribute = {}
local UIAttribute_mt = {
    __proxy_opaque = true
}

---@class UIHandler
---@field name string
---@field value function
local UIHandler = {}
local UIHandler_mt = {
    __proxy_opaque = true
}

---@class UIStyle
local UIStyle = {}

local new_composite_style
local UICompositeStyle_mt
local add_styles = function (left, right)
    local children = {}
    if getmetatable(left) == UICompositeStyle_mt then
        for i, v in ipairs(left.children) do
            table.insert(children, v)
        end
    else
        table.insert(children, left)
    end
    if getmetatable(right) == UICompositeStyle_mt then
        for i, v in ipairs(right.children) do
            table.insert(children, v)
        end
    else
        table.insert(children, right)
    end
    return new_composite_style(children)
end

---@class UICompositeStyle: UIStyle
---@field children UIStyle[]
local UICompositeStyle = {}
UICompositeStyle_mt = {
    __add = add_styles,
    __proxy_private = true
}

---@class UISimpleStyle: UIStyle
---@field name string
---@field value string
local UISimpleStyle = {}
local UISimpleStyle_mt = {
    __add = add_styles,
    __proxy_private = true
}

---create a new uinode
---@param tag string
---@param desc UIDesc
---@param namespace string?
---@return UINode
local function new_node(tag, desc, namespace)
    local styles = {}
    local attrs = {}
    local handlers = {}
    ---@type UINode[]
    local children = {}
    for i, v in ipairs(desc) do
        if type(v) == "string" then
            table.insert(children, {tag = nil, text = v, children = {}, attrs = {}, handlers = {}})
        elseif type(v) == "table" then
            local mt = getmetatable(v)
            if mt == UIAttribute_mt then
                attrs[v.name] = v.value
            elseif mt == UIHandler_mt then
                handlers[v.name] = function() v.value(); notify() end
            elseif mt == UINode_mt then
                table.insert(children, v)
            elseif mt == UISimpleStyle_mt or mt == UICompositeStyle_mt then
                table.insert(styles, v)
            else
                error("invalid UIDesc")
            end
        else
            error("invalid UIDesc")
        end
    end
    return setmetatable({tag = tag, children = children, handlers = handlers, attrs = attrs, styles = styles, namespace = namespace}, UINode_mt)
end

---create a new uiattribute
---@param name string
---@param value string|boolean|integer
---@return UIAttribute
local function new_attribute(name, value)
    return setmetatable({name = name, value = value}, UIAttribute_mt)
end

---create a new uihandler
---@param name string
---@param value function
---@return UIHandler
local function new_handler(name, value)
    return setmetatable({name = name, value = value}, UIHandler_mt)
end

---create a new uicompositestyle
---@param children UIStyle[]
---@return UICompositeStyle
function new_composite_style(children)
    return setmetatable({children = children}, UICompositeStyle_mt)
end

---create a new uisimplestyle
---@param name string
---@param value string
---@return UISimpleStyle
local function new_simple_style(name, value)
    return setmetatable({name = name, value = value}, UISimpleStyle_mt)
end

---@type table<UINode, DomNode>
local dom_nodes = {}
---@type UINode
local last_tree

---@class StyleClassRegistry
---@field counter integer counter for class names generated
---@field style_map table<string, string> map from style string to class name
local StyleClassRegistry = {}

---@param styles UIStyle[]
---@return table<string, boolean>
function StyleClassRegistry:get_or_create(styles)
    local classes = {}
    for i, style in ipairs(styles) do
        local mt = getmetatable(style)
        if mt == UICompositeStyle_mt then
            ---@cast style UICompositeStyle
            local sub_classes = self:get_or_create(style.children)
            for i, sub_class in ipairs(sub_classes) do
                classes[sub_class] = true
            end
        elseif mt == UISimpleStyle_mt then
            ---@cast style UISimpleStyle
            local style_string = style.name .. ":" .. style.value .. ";"

            if not self.style_map[style_string] then
                local class_name = "s" .. self.counter
                self.counter = self.counter + 1

                style_sheet:insertRule("." .. class_name .. "{" .. style_string .. "}")

                self.style_map[style_string] = class_name
            end
            classes[self.style_map[style_string]] = true
        else
            error("invalid style")
        end
    end
    return classes
end
local StyleClassRegistry_mt = {
    __index = StyleClassRegistry
}

---update a dom node in accordance to a tree
---@param style_class_registry StyleClassRegistry
---@param tree UINode
---@param last_tree UINode?
---@param last_elem DomNode?
---@return DomNode
local function build_against(style_class_registry, tree, last_tree, last_elem)
    if not last_tree or not last_elem then
        if tree.tag then
            local elem
            if tree.namespace then
                elem = document:createElementNS(tree.namespace, tree.tag)
            else
                elem = document:createElement(tree.tag)
            end
            for i, child in ipairs(tree.children) do
                elem:append(build_against(style_class_registry, child))
            end
            for k, v in pairs(tree.attrs) do
                elem:setAttribute(k, v)
            end
            for k, v in pairs(tree.handlers) do
                elem:addEventListener(k, v)
            end
            local classes = style_class_registry:get_or_create(tree.styles)
            for class, _ in pairs(classes) do
                elem.classList:add(class)
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
                    elem:append(build_against(style_class_registry, tree.children[i]))
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
                    local last_classes = style_class_registry:get_or_create(last_tree.styles)
                    local classes = style_class_registry:get_or_create(tree.styles)
                    for class, _ in pairs(last_classes) do
                        if not classes[class] then
                            elem.classList:remove(class)
                        end
                    end
                    for class, _ in pairs(classes) do
                        if not last_classes[class] then
                            elem.classList:add(class)
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
        return build_against(style_class_registry, tree)
    end
end

---@class Binding
---@field node DomNode
---@field app fun(): UINode
---@field last UINode
---@field style_class_registry StyleClassRegistry

---@type table<Binding, boolean>
local claimed_roots = {}

function notify()
    for binding in pairs(claimed_roots) do
        local node = build_against(binding.style_class_registry, binding.app(), binding.last, binding.node)
        if node == binding.node then
            --do nothing
        else
            binding.node:replaceWith(node)
            binding.node = node
        end
    end
end

local style_class_registry = {
    counter = 0,
    style_map = {}
}
setmetatable(style_class_registry, StyleClassRegistry_mt)

---claim an element as the root node of an app
---@param node DomNode
---@param app fun():UINode
local function claim_root(node, app)
    claimed_roots[{node = node, app = app, last = nil, style_class_registry = style_class_registry}] = true
end


return {
    build_against = build_against,
    new_node = new_node,
    new_attribute = new_attribute,
    new_handler = new_handler,
    new_composite_style = new_composite_style,
    new_simple_style = new_simple_style,
    notify = notify,
    claim_root = claim_root
}
