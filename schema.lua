
local hashing = require "schema-hash"

local newstruct, newenum, newunion, newvariant, newinterface

local defer_field_def, defer_union_def, defer_variant_def

local is_schematype

local struct_mt = {
  __index = {
    addfield = function(self, name, stype, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end

      local field = {kind = "field", name = name, type = stype, docstring = docstring, id = id}
      self.fields[#self.fields + 1] = field
      self.field_by_name[name] = field
    end,
    addunion = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      -- this id reuse/collision is benign because one is a field and the other is an enum type, and both are in the same schema, and neither is a top level export
      local enum = newenum(name, docstring, id)
      self:addfield(name, enum, docstring, id)
      return newunion(self, #self.fields, enum)
    end,
    addunionfield = function(self, name, stype, descriminator, descriminant, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      assert(type(descriminator) == "number", "union specifier must be present")
      assert(type(descriminant) == "number", "union descriminant must be present")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end

      local field = {kind = "union", name = name, type = stype, docstring = docstring, descriminator = descriminator, descriminant = descriminant, id = id}
      self.fields[#self.fields] = field
      self.field_by_name[name] = field
    end,
  },
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

function newstruct(name, docstring, id)
  assert(type(name) == "string", "the name of the struct must be a string")
  if docstring ~= nil and type(docstring) ~= "string" then
    error "the docstring must be a string if present"
  end
  local self = {
    name = name,
    docstring = docstring,
    components = {},
    count = 0,
    id = id,
    kind = 'struct'
  }
  return setmetatable(self, struct_mt)
end

local union_mt = {
  __index = {
    addvariant = function(self, name, docstring, id)
      if not id then
        id = hashing.hash{self.id, name}
      end
      local descval = self.enum:addvariant(name, docstring, id)
      return newvariant(self, self.descpos, descval)
    end
  },
  -- __call = function(self, ...) return defer_union_def(self, ...) end
}

function newunion(parent, descpos, enum)
  local self = {
    parent = parent,
    descpos = descpos,
    enum = enum
  }
  return setmetatable(self, union_mt)
end

local variant_mt = {
  __index = {
    addfield = function(self, name, stype, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      return self.parent.parent:addunionfield(name, stype, self.descpos, self.descval, docstring, id)
    end,
    addunion = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      local enum = newenum(name, docstring, id)
      self:addfield(name, enum, docstring, id)
      return newunion(self, self.count, enum)
    end,
    addunionfield = function(self, name, stype, descpos, descval, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      return self.parent.parent:addunionfield(name, stype, descpos, descval, docstring, id)
    end,
  },
  -- __call = function(self, ...) return defer_variant_def(self, ...) end
}

function newvariant(parent, name, docstring, id)
  local self = {
    parent = parent,
    name = name,
    docstring = docstring,
    id = id,
  }
  return setmetatable(self, variant_mt)
end

local enum_mt = {
  __index = {
    addvariant = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end
      self.variants[#self.variants + 1] = {name = name, docstring = docstring, id = id}
    end
  },
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

function newenum(name, docstring, id)
  local self = {
    name = name,
    docstring = docstring,
    id = id
  }
  return setmetatable(self, enum_mt)
end

local interface_mt = {
  __index = {
    addmethod = function(self, name, docstring, args, results, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end

    end
  },
  __call = function(self, ...) return defer_field_def(self, ...) end
}

function newinterface(name, docstring, id)
  assert(type(name) == "string", "the name of the field must be a string")
  if docstring ~= nil and type(docstring) ~= "string" then
    error "the docstring must be a string if present"
  end
  assert(id, "when creating a type outside the context of a schema it must have an id specified")
  local self = {
    name = name,
    docstring = docstring,
    id = id
  }
  return setmetatable(self, interface_mt)
end

local schema_mt = {
  __index = {
    addstruct = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end
      local struct = newstruct(name, docstring, id)
      self.exports[#self.exports + 1] = struct
      self.export[name] = struct
      return struct
    end,
    addenum = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = hashing.hash{self.id, name}
      end
      local t = newenum(name, docstring, id)
      self.exports[#self.exports + 1] = t
      self.export[name] = t
      return t
    end
  }
}

local deferred_field_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      list[#list + 1] = self
    end,
    execute = function(self)
      self.context.val:addfield(self.name, self.type, self.docstring, self.id)
    end
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a field declaration after the type must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a field declaration after the type must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    else
      error "unknown component of field declaration"
    end
    return self
  end
}

function deferred_field_def(stype, name)
  return setmetatable({type = stype}, deferred_field_mt)(name)
end

local deferred_union_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      self.nextcontext = {}
      list[#list + 1] = self
      for i, v in ipairs(self.children) do
        v:insertall(list, self.nextcontext)
      end
    end,
    execute = function(self)
      self.nextcontext.val = self.context.val:addunion(self.name, self.docstring, self.id)
    end,
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a union declaration after `union` must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a union declaration after `union` must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif not self.children and type(val) == "table" then
      self.children = val
    else
      error "unknown component of union declaration"
    end
    return self
  end
}

local function union(name)
  return setmetatable({}, deferred_union_mt)(name)
end

local deferred_variant_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      self.nextcontext = {}
      list[#list + 1] = self
      for i, v in ipairs(self.children) do
        v:insertall(list, self.nextcontext)
      end
    end,
    execute = function(self)
      self.nextcontext.val = self.context.val:addvariant(self.name, self.docstring, self.id)
    end,
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a variant declaration after `variant` must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a variant declaration after `variant` must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif not self.children and type(val) == "table" then
      self.children = val
    else
      error "unknown component of variant declaration"
    end
    return self
  end
}

local function variant(name)
  return setmetatable({}, deferred_variant_mt)(name)
end

local function declare()
  return {}
end
