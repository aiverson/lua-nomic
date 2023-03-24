
local js = require 'js'
local document = js.global.document

local slot = require 'slot'

local function splitbody(body)
  local attributes = {}
  local children = {}
  for k, v in pairs(body) do
    if type(k) == "number" then
      children[k] = v
    elseif type(k) == "string" then
      attributes[k] = v
    else
      error "invalid attribute"
    end
  end
end

local function setlist(tab)
  for i, v in ipairs(tab) do
    tab[v] = true
  end
  return tab
end

local whitelisted_tags = {"span", "div", "button", "p"}
local whitelisted_attributes = setlist{"id", "name", "class", "disabled"}
local whitelisted_events = setlist{"click"}



local attribute_binding_mt = {
  __proxy_private = true,
  __index = {
    enter = function(self)
      self.slot:subscribe(self)
      self:update()
    end,
    update = function(self)
      self.element:setAttribute(self.name, self.slot:get())
    end,
    exit = function(self)
      self.slot:unsubscribe(self)
    end,
  }
}

local function make_attr_binding(element, name, slot)
  local self = setmetatable({slot = slot, name = name, element = element}, attribute_binding_mt)
  return self
end

local attribute_const_mt = {
  __proxy_private = true,
  __index = {
    enter = function(self) end,
    update = function(self) self.element:setAttribute(self.name, self.value) end,
    exit = function(self) end
  }
}

local function make_attr_const(element, name, value)
  return setmetatable({element = element, name = name, value = value}, attribute_const_mt)
end

local function build_attr(element, name, decl)
  if slot.is_slot(decl) then
    return make_attr_binding(element, name, decl)
  elseif type(decl) == "string" or type(decl) == "number" or type(decl) = "boolean" then
    return make_attr_const(element, name, tostring(decl))
  else
    error "unsupported type in attribute"
  end
end



local text_binding_mt = {
  __proxy_private = true,
  __index = {
    enter = function(self)
      self.slot:subscribe(self)
      self:update()
    end,
    update = function(self)
      self.node.data = self.slot:get()
    end,
    exit = function(self)
      self.slot:unsubscribe(self)
    end,
  }
}

local function make_text_binding(slot)
  return setmetatable({slot = slot, node = document.createTextNode(slot:get())}, text_binding_mt)
end

local text_const_mt = {
  __proxy_private = true,
  __index = {
    enter = function(self) end,
    update = function(self) end,
    exit = function(self) end,
  }
}

local function make_text_const(text)
  return setmetatable({slot = slot, node = document.createTextNode(text)}, text_const_mt)
end

local element_mt = {
  __proxy_private = true,
  __index = {
    enter = function(self)
      for attr, bind in pairs(self.attributes) do
        bind:enter()
      end
      for i, child in ipairs(self.children) do
        child:enter()
        if child.node then
          self.node:append(child.node)
        end
      end
    end,
    update = function(self) end,
    exit = function(self)
      for attr, bind in pairs(self.attributes) do
        bind:exit()
      end
      for i, child in ipairs(self.children) do
        child:exit()
        if child.node then
          child.node:remove()
        end
      end
    end
  }
}

local build_child

local function build_element(tag, attributes, handlers, children)
  local self = {
    attributes = {},
    children = {},
    tag = tag,
    node = document.createElement(tag)
  }
  for k, v in pairs(attributes) do
    self.attributes[k] = build_attr(self.node, k, v)
  end
  for i, v in ipairs(children) do
    self.children[i] = build_child(self.node, v)
  end
  for k, v in pairs(handlers) do
    self.tag:addEventListener(k, v) --TODO: sandbox this so that the lua code doesn't get access to raw events
  end
  return setmetatable(self, element_mt)
end

local function is_element(obj)
  return getmetatable(obj) == element_mt
end

function build_child(decl)
  if is_element(decl) then
    return decl
  elseif slot.is_slot(decl) then
    return make_text_binding(decl)
  elseif type(decl) == "string" then
    return make_text_const(decl)
  else
    error "unsupported type in children"
  end
end

local function element_template(tag)
  return function(body)
    local named, children = splitbody(body)
    local attributes, handlers = {}, {}
    for name, decl in pairs(named) do
      if whitelisted_attributes[name] then
        attributes[name] = decl
      elseif name:sub(1, 2) == "on" and whitelisted_events[name:sub(3, -1)] then
        handlers[name] = decl
      else
        error "the declaration of an element contained something that wasn't either a whitelisted attribute or handler"
      end
    end
    return build_element(tag, attributes, handlers, children)
  end
end

local quill = {}

for i, v in ipairs(whitelisted_tags) do
  quill[v] = element_template(v)
end

return quill
