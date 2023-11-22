local weblit = require "./deps/weblit"
local uv = require "uv"

local app = weblit.app

local waitingSockets = {}

app.bind(
    {
        host = "127.0.0.1",
        port = 8080
    }
).use(weblit.logger).use(weblit.autoHeaders).use(weblit.etagCache)

app.websocket(
    {
        path = "/v2/socket" -- Prefix for matching
        --protocol = "virgo/2.0", -- Restrict to a websocket sub-protocol
    },
    function(req, read, write)
        -- Log the request headers
        print(req)

        print("closing websocket")

        waitingSockets[write] = nil
        -- End the stream
        write()
    end
)

app.route({method = "GET", path = "/index.html"}, require './index')

app.use(weblit.static "bundle:static/").use(weblit.static "static/")

app.start()

require "uv".run()
