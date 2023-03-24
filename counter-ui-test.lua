

local quill = require 'quill'
local slot = require 'slot'

local count = slot.set(0)

quill.template(function(self, count)
    return quill.span{
      quill.button {
        onclick = function() count:set(count:get() - 1) end;
        "<";
      };
      slot.map(tostring, count);
      quill.button {
        onclick = function() count:set(count:get() + 1) end;
        ">";
      };
    }
end)
