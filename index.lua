local html = require './html'
local bundle = require 'luvi'.bundle
local fs = require 'coro-fs'
local json = require 'json'

local pagescript = fs.readFile('pagescript.lua')

local sources = {
  client_html = fs.readFile("client-html.lua"),
  client_elements = fs.readFile("client-elements.lua"),
  modules = fs.readFile("modules.lua"),
  clientmodules = {
    testapp = fs.readFile("clientmodules/testapp.lua"),
    counter = fs.readFile("clientmodules/counter.lua")
  }
}

return function(req, res, go)
  table.insert(res.headers, {"Content-Type", "text/html"})
  res.body = html.render(
    html.html {
      html.head {
        html.title "fengari test",
        html.script {
          src = "fengari-web.js",
          type = "text/javascript"
        },
        html.data {
          id = "sources",
          value = json.encode(sources) --[[@as string]]:gsub(".", function(c) return "&#"..string.byte(c)..";" end)
        },
        html.script {
          type = "text/lua",
          pagescript
        }
      },
      html.body {
        id = "body",
        html.div {
          id = "mainapp",
        }
      }
    },
    {doctype = "html5"}
  )
  res.code = 200;
end
