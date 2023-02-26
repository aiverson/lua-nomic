local g = require 'lpeg'
local l = g.locale()
local core = require 'core'
local Object, instanceof = core.Object, core.instanceof

local function split(pat, str)
    return g.Ct(g.C((1-pat)^1) * (pat^1 * g.C((1-pat)^1))^0)
end

local Builder = Object:extend()

function Builder:emit(val)
    if instanceof(val, Builder) then
        for i = 1, #val do
            self[#self+1] = val[i]
        end
    else
        self[#self+1] = tostring(val)
    end
    return self
end

local defaultRenderers = {
    string = function(s, build, options) build:emit(s) end,
    number = function(x, build, options) build:emit(x) end,
    table = function(f, build, options) error "invalid table without __render metamethod" end,
}

function Builder:render(val, options)
    local render =  getmetatable(val).__render or defaultRenderers[type]
    if render then
        render(val, self, options)
    else
        error "Unable to find a renderer for a value in the render tree"
    end
end

function Builder.meta:__tostring()
    return table.concat(self)
end

local htmlElements = split(l.space):match [[html
link meta style title
body address article aside footer header h1 h2 h3 h4 h5 h6 hgroup nav section blockquote dd dir div dl dt figcaption figure hr li main ol p pre ul
a abbr b bdi bdo br cite code data dfn em i kbd mark q rb rp rt rtc ruby s samp small span strong sub sup time tt u var wbr
area audio img map track video
applet embed iframe noembed object param picture source
canvas noscript script
del ins
caption col colgroup table tbody td tfoot th thead tr
button datalist fieldset form input label legend meter optgroup option output progress select textarea
details dialog menu menuitem summary
slot template]]


local function getName(element)
    return getmetatable(element).__elemname
end

local function htmlRender(tree, build, options)
    local tag = getName(tree)
    build:emit("<"):emit(tag)
    for k, v in pairs(tree) do
        if type(k) == "string" then
            build:emit ' '
                :emit(k)
                :emit '="'
                :render(v)
                :emit '"' 
        end
    end
    build:emit">"
    for i = 1, #tree do
        build:render(tree[i])
    end
    build:emit '</'
        :emit(tag)
        :emit('>')
end

local htmlCompile

local function makeElementMT(name)
    return {
        __elemname = name,
        __render = htmlRender,
        __compile = htmlCompile,
    }
end

local htmlConstructors = {}

for i, name in ipairs(htmlElements) do
    local mt = makeElementMT(name)
    htmlConstructors[name] = function(val)
        if type(val) == "string" then
            val = {val}
        end
        if type(val) ~= "table" then
            error "invalid argument type for HTML constructor. Argument must be a table or a string"
        end
        return setmetatable(val, mt)
    end
end

