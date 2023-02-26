local core = require 'core'
local Object, Emitter = core.Object, core.Emitter

local PriorityQueue = Object:extend()
local PriorityElement = Object:extend()

function PriorityQueue:initialize()
    self.n = 0
end

function PriorityQueue:pop()
    local elem = self[1]
    local idx = #self
    if idx == 1 then
        self[1] = nil
        return elem[1], elem[2]
    elseif idx == 0 then
        return
    end
    local last = idx - 1
    self[1], self[idx], self[idx][3] = self[idx], nil, 1
    idx = 1
    while true do
        if idx * 2 > last then
            return elem[1], elem[2]
        end
        local nextidx
        if self[idx][1] > self[idx*2][1] then
            nextidx = idx*2
        end
        if idx*2+1 < last and self[idx*2+1][1] < self[idx][1] and self[idx*2+1][1] < self[idx*2][1] then
            nextidx = idx*2+1
        end
        if nextidx then
            self[nextidx], self[idx], self[nextidx][3], self[idx][3] = self[idx], self[nextidx], idx, nextidx
        else
            return elem[1], elem[2]
        end
    end
end

function PriorityQueue:peek()
    local elem = self[1]
    if not elem then return nil end
    return elem[1], elem[2]
end

function PriorityQueue:put(priority, value)
    local elem = PriorityElement:new(priority, value, self)
    local idx = #self + 1
    self[idx] = elem
    local newidx = math.floor(idx/2)
    while newidx > 0 do
        if self[newidx][1] > self[idx][1] then
            self[newidx], self[idx], self[newidx][3], self[idx][3] = self[idx], self[newidx], idx, newidx
        else
            return elem
        end
    end
    return elem
end

function PriorityElement:initialize(priority, value, queue)
    self[1], self[2] = priority, value
    self.queue = queue
end

function PriorityElement:remove()
    local idx = self[3]
    local newidx = math.floor(idx/2)
    while newidx > 0 do
        self.queue[newidx], self.queue[idx], self.queue[newidx][3], self.queue[idx][3] = self.queue[idx], self.queue[newidx], idx, newidx
    end
    self.queue:pop()
end

local Conn = Object:extend()

function Conn:initialize(link)
  self.messages = PriorityQueue:new()
  self.link = link
  self.imports = {}
  self.exports = {}
  self.free_export = 1
  self.questions = {}
  self.free_question = 1
  self.answers = {}
end

function Conn:question(data)
  local q = {kind = 'question', data = data, needs_answer = true, submitted = false, id = self.free_question}
  q.entry = self.messages:put(0, q)
  if self.questions[self.free_question] then
    self.free_question = self.questions[self.free_question]
  else
    self.free_question = self.free_question + 1
  end
  return new_promise(q)
end

function Conn:release(id)
  local q =
