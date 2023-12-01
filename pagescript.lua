
local js = require 'js'

---@module "typedef.jsdom"
---@type Document
local document = js.global.document

print("the sources")
js.global.console:log("the sources")
js.global.console:log(document:getElementById("sources"))
print(document:getElementById("sources"))
js.global.console:log(document:getElementById("sources").value)
print(document:getElementById("sources").value)

local sources = js.global.JSON:parse(document:getElementById("sources").value)

---@module "modules"
local modules_base = assert(load(sources.modules, "modules.lua"))()

local module_create = modules_base(false)

local style_sheet = js.new(js.global.CSSStyleSheet)
document.adoptedStyleSheets:push(style_sheet)

print "client dom"
---@module "client-dom"
local client_dom = module_create(sources.client_dom, "client_dom.lua")(document, style_sheet, "mainapp")
print "client html"
---@module "client-html"
local client_html = module_create(sources.client_html, "client_html.lua")(client_dom)
print "client svg"
---@module "client-svg"
local client_svg = module_create(sources.client_svg, "client_svg.lua")(client_dom)
print "counter"
---@module "clientmodules.counter"
local counter = module_create(sources.clientmodules.counter, "clientmodules/counter.lua"){html = client_html}
print "testapp"
---@module "clientmodules.testapp"
local testapp = module_create(sources.clientmodules.testapp, "clientmodules/testapp.lua"){html = client_html, svg = client_svg}
print "done loading scripts"

document:addEventListener('DOMContentLoaded', function()
client_dom.claim_root(document:getElementById("mainapp"), function() return testapp:render() end)
print "root claimed"

print(pcall(client_dom.notify))
end)
