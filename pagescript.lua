
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

print "client html"
---@module "client-html"
local client_html = module_create(sources.client_html, "client_html.lua")(document, "mainapp")
print "client elements"
---@module "client-elements"
local elem = module_create(sources.client_elements, "client_elements.lua")(client_html)
print "counter"
---@module "clientmodules.counter"
local counter = module_create(sources.clientmodules.counter, "clientmodules/counter.lua"){elem = elem}
print "testapp"
---@module "clientmodules.testapp"
local testapp = module_create(sources.clientmodules.testapp, "clientmodules/testapp.lua"){elem = elem, counter = counter}
print "done loading"
client_html.claim_root(document:getElementById("mainapp"), testapp)
print "root claimed"

print(pcall(client_html.notify))