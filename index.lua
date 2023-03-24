local html = require './html'
local bundle = require 'luvi'.bundle
local fs = require 'coro-fs'

local pagescript = fs.readFile('testscript.lua')

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
        html.script {
          type = "text/lua",
          pagescript
        },
      },
      html.body {
        id = "body"
      }
    },
    {}
  )
  res.code = 200;
end
