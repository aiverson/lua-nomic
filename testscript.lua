
local js = require 'js'

local document = js.global.document

local body = document:getElementById('body')

local para = document:createElement("p")
para:appendChild(document:createTextNode("this text set from lua"))
body:appendChild(para)
