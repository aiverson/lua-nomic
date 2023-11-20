
local schema = require 'schema'

local text, union, enum, variant = schema.text, schema.union, schema.enum, schema.variant
local u16, u64, list = schema.u16, schema.u64, schema.list

local S = schema.create("schema", "the schema for saving and transmitting schemas")

local stype = S:addstruct("type", "the type that a field may have")
local struct = S:addstruct("struct", "a structure containing named fields")
local field = S:addstruct("field", "something in a structure where data can be stored")
local senum = S:addstruct("enum", "a set of meaningful names which get stored as a single number")

local typeid = S:newtype("typeid", u64)
local schemaid = S:newtype("schemaid", u64)
local fieldid = S:newtype("fieldid", u64)

field:define {
  text "name" (0) "the name of the field as it should be used to generate the keys of the table";
  stype "type" (1) "The type the field is stored as";
  text "docstring" (3) "expanded documentation describing the usage and meaning of the field";
  union "kind" (2) "what kind of field it is, whether it is always present, whether it is part of an enum"
  {
    variant "field" (4) "This field is just an ordinary field that is always accessible" {};
    variant "union" (5) "The field is part of a union, only accessible when the descriminator has a particular value"
    {
      -- support your local union
      u16 "descriminator" (6) "which component of the struct holds the discriminator for this union field";
      u16 "descriminant" (7) "the value the descriminator field must take for this field to be valid.";
    };
  };
  fieldid "id" (8) "The unique key for a field automatically derived from the initial name and the struct to verify forward compatibility. The collision domain for this key is within the parent struct.";
}

struct:define {
  text "name" (0) "a friendly name for the struct, if applicable";
  list(field) "fields" (1) "the fields of the struct, in evolution order";
  typeid "id" (2) "The unique key for a struct automatically derived from the parent context. The collision domain for this is either within a single parent schema, across all schemas being provided by a lookup service, or across all schemas used in a single connection.";
}

local enum_elem = S:struct "enum_elem" "An element of an enum"
{
  text "name" (0) "The name of the enum element as used in code";
  text "docstring" (1) "extended description of the enum element";
  fieldid "id" (2) "The unique id of an element in an enum, used to verify forward compatibility across renames. The collision domain for this is within the single enum";
}

senum:define {
  text "name" (0) "a friendly name for the enum, if applicable";
  list(enum_elem) "values" (1) "the list of names corresponding to values of the enum";
  typeid "id" (2) "The unique key for an enum automatically derived from parent context. The collision domain is the same as a struct id.";
}

local primitive = S:enum "primitive" "An enumeration of the primitive non-pointer types"
{
  "bool";
  "u8";
  "i8";
  "u16";
  "i16";
  "u32";
  "i32";
  "u64";
  "i64";
  "f16";
  "f32";
  "f64";
  "unit";
  "bottom";
}

local sargument = S:struct "argument" "The name and type of an argument or return"
{
  stype "type" (0);
  text "name" (1) "A friendly name for the argument, just for documentation";
  text "docstring" (2) "Expanded documentation about what the argument means";
  fieldid "id" (3) "A unique id automatically derived from context to check forward compatibility. The collision domain is only within a single method.";
}

local smethod = S:struct "method" "The definition of a method of an interface"
{
  text "name" (0) "A friendly name for the method";
  list(sargument) "parameters" (1) "What arguments are given to the method when it is called";
  list(sargument) "results" (2) "What arguments are returned by the method when it is called";
  fieldid "id" (3) "A unique id automatically derived from context to check forward compatibility. The collision domain is only within the interface.";
}

local interface = S:struct "interface" "A definition of an interface"
{
  text "name" (0) "A friendly name for the interface";
  list(smethod) "methods" (1) "all the methods of the interface, in evolution order";
  typeid "id" (2) "A unique id automatically derived from the schema in which this interface lives. The collision domain is the same as for structs";
}

local generic = S:struct "generic" "A parameterized type"
{
  union "kind" (0) "what kind of type this generic expands to"
  {
    variant "struct" (1) "this generic evaluates to a struct"
    {
      struct "type" (2) "the struct which it evaluates to";
    };
    variant "interface" (3) "this generic evaluates to an interface"
    {
      interface "type" (4) "the interface which it evaluates to";
    };
    variant "list" (5) "the generic is a built in list" {};
    variant "maybe" (6) "the generic is a built in maybe construct" {};
  }
}

local newtype = S:struct "newtype" "a distinct wrapper stored exactly like some other type"
{
  text "name" (0) "The name of the distinct wrapper";
  stype "base" (1) "The type being wrapped";
  typeid "id" (2) "A unique id automatically derived from context. The collision domain is the same as for struct.";
}

stype:define {
  union "kind" (0) "what kind of type reference this is"
  {
    variant "primitive" (1) "This stype is a primitive built in to the protocol"
    {
      primitive "type" (2) "Which primitive is this type";
    };
    variant "struct" (3) "This type is a direct usage of a defined struct type"
    {
      struct "type" (4) "The struct this type is";
    };
    variant "enum" (5) "This type is a direct usage of an enum"
    {
      senum "type" (6) "Which enum this type is";
    };
    variant "generic" (7) "This type is an instantiation of a generic"
    {
      generic "basetype" (8) "The generic which is being invoked";
      list(stype) "args" (9) "The arguments to invoke the generic with";
    };
    variant "parameter" (10) "This type is a usage of a parameter from an enclosing generic"
    {
      u8 "depth" (11) "Like debruijn notation, parameters are referred to by a count up the enclosing lambdas";
      u8 "index" (12) "Unlike debruijn notation, we allow multiple parameters to a call";
    };
    variant "newtype" (13) "This type is a newtype wrapper around some other type"
    {
      newtype "type" (14) "The newtype which is being used";
    };
    variant "interface" (15) "This type is an interface type"
    {
      interface "type" (16) "which interface this type is";
    };
  };
}

local schema_export = S:struct "export" "Something exported from a schema"
{
  union "kind" (0) "What kind of thing is being exported"
  {
    variant "struct" (1) "The export is a struct"
    {
      struct "type" (2) "The exported struct";
    };
    variant "enum" (3) "The export is an enum"
    {
      enum "type" (4) "The exported enum";
    };
    variant "generic" (5) "The export is a generic type"
    {
      generic "type" (6) "The exported generic";
    };
    variant "newtype" (7) "The export is a newtype"
    {
      newtype "type" (8) "The exported newtype";
    };
    variant "interface" (9) "The export is an interface"
    {
      interface "type" (10) "The exported interface";
    };
  };
}

local schema_schema = S:struct "schema" "The entire schema which is being described"
{
  text "name" (0) "The friendly name for the schema";
  text "docstring" (1) "expanded documentation describing the purpose and content of the schema";
  schemaid "id" (2) "The unique identifier which identifies this schema for forward compatibility";
  list(schema_export) "exports" (3) "All types which are exported from the schema.";
}

local demangled_type_id = S:addstruct("demangled_type_id", "The compound ID to identify an applied generic outside the context of a schema")

demangled_type_id:define {
  u64 "baseid" (0) "The id of the base type or generic";
  list(demangled_type_id) "args" (1) "The arguments to resolve the type fully";
}

local schema_provider = S:interface "schema_provider" "An interface for attempting to locate a schema from an id"
{
  method "load_schema" (0) "Look up a schema by the id of the schema as a whole"
  {
    schemaid "id" "The id of the schema to load";
  } :to
  {
    schema_schema "schema" "The schema located by the id";
  };
  method "find_source" (1) "Given the id of something exported by a schema somewhere, attempt to figure out what exported it"
  {
    typeid "id" "The id of the export to look for";
  } :to
  {
    maybe(schemaid) "id" "The id of the schema containing the export";
  };
  method "demangle_type_id" (2) "Generic interfaces are hashed together with their parameters to fit in the 64 bit interface id. The hash means that if you just have the interface id of a generic interface, you can't necessarily find out what the original id or parameters were without asking something else for them."
  {
    typeid "id" "The mangled generic interface id to ask for the source representation of";
  } :to
  {
    demangled_type_id
  };
}

S:interface "interface_specializer" "It doesn't usually make sense to make interfaces that support any possible type, so it's not built into the protocol by default. However, it can sometimes be useful, so"
{
  method "specialize" (0) "request a version of this capability that responds to the mangled form of the provided demangled type identifier. This requires that both vats have common knowledge of what typeids mean"
  {
    demangled_type_id "id" "the interface id and paramters"
  } :to {schema.anycap};
}

S:interface "introspector" "An interface for inspecting the current capability to figure out what it can do. You probably shouldn't rely on this in production."
{
  method "has_interface" (0) "probe to see if a single interface is supported. You don't need to do this before calling a method from the interface, it will just fail if the interface is unsupported. If for some reason you want to test if an interface exists but don't want to use it, this exists."
  {
    typeid "id";
  } :to {bool};
  method "has_any_interface" (1) "probe to see if any interface from a list is supported"
  {
    list(typeid) "ids";
  } :to {list(bool)};
  method "get_interfaces" (2) "try to enumerate the interfaces implemented by a capability."
  {} :to {list(typeid)};
}

return S
