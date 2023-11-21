---@meta typedef.jsdom

---@class DomNode
---@field lastElementChild DomNode
local DomNode = {}

---@class Document
local Document = {}

---get a dom element by its id
---@param id string
---@return DomNode node
function Document:getElementById(id) end

---create a new element with the specified tag
---@param tag string
---@return DomNode node
function Document:createElement(tag) end

---Create a new text node
---@param text string
---@return DomNode
function Document:createTextNode(text) end

---add a child node after the current children
---@param child DomNode
function DomNode:append(child) end

---remove a dom node from its parent
function DomNode:remove() end

---add an event listener to a node
---@param event string
---@param handler function
function DomNode:addEventListener(event, handler) end
---remove a previously added event listener
---@param event string
---@param handler function
function DomNode:removeEventListener(event, handler) end

---set an attribute on a node
---@param name string
---@param value string
function DomNode:setAttribute(name, value) end
---remove an attribute from a node
---@param name string
function DomNode:removeAttribute(name) end

---replace a node in its parents with a sequence of nodes
---@param ... DomNode
function DomNode:replaceWith(...) end

---@class DomTextNode: DomNode
---@field data string

return {DomNode = DomNode, Document = Document}