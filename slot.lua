
local enclosing_bind
local pending_slots = {}

local function add_pending(slot)
  pending_slots[slot] = true
end

local function register_dep(dep)
  if enclosing_bind then
    enclosing_bind[dep] = true
  end
end

local slot_mt = {
  __proxy_private = true,
  __index = {
    get = function(self)
      if enclosing_bind then
        enclosing_bind[self] = true
      end
      if next(self.subs) or not self.binding then
        return self.value
      else
        self:update()
        return self.value
      end
    end,
    set = function(self, value)
      self.value = value
      for sub, _ in pairs(self.subs) do
        add_pending(sub)
      end
    end,
    update = function(self)
      if not self.binding then
        error "asked to update a slot that isn't bound"
      end
      local parent_bind = enclosing_bind
      local old_deps = self.deps
      enclosing_bind = {}
      self.value = self.binding()
      self.deps = enclosing_bind
      if next(self.subs) then
        for dep, _ in pairs(old_deps) do
          if not self.deps[dep] then
            dep:unsubscribe(self)
          end
        end
        for dep, _ in pairs(self.deps) do
          if not old_deps[dep] then
            dep:subscribe(self)
          end
        end
        for sub, _ in pairs(self.subs) do
          add_pending(sub)
        end
      end
      enclosing_bind = parent_bind
    end,

    bind = function(self, fn)
      self.binding = fn
      self:update()
    end,
    subscribe = function(self, sub)
      self.subs[sub] = true
    end,
    unsubscribe = function(self, sub)
      self.subs[sub] = nil
    end
  }
}

return {
  add_pending = add_pending,
  register_dep = register_dep,
  bind = function(binding)
    local self = setmetatable({
        subs = {},
        deps = {},
        binding = binding
    }, slot_mt)
    self:update()
    return self
  end,
  set = function(val)
    local self = setmetatable({
        subs = {},
        deps = {},
        value = val
    }, slot_mt)
    return self
  end,
  map = function(fn, src)
    local self = setmetatable({
        subs = {},
        deps = {},
        binding = function() return fn(src:get()) end,
    }, slot_mt)
    self:update()
    return self
  end,
  turn = function()
    local p = next(pending_slots)
    if p then
      pending_slots[p] = nil
      p:update()
      return true
    else
      return false
    end
  end,
  run = function()
    local p = next(pending_slots)
    while p do
      pending_slots[p] = nil
      p:update()
      p = next(pending_slots)
    end
  end,
  is_slot = function(obj)
    return getmetatable(obj) == slot_mt
  end
}
