local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

local ws = require('websocket.client').sync({ timeout = 30 })

local params = {
  mode = "client",
  protocol = "any",
  verify = "none",
  options = "all"
}

function ws_connect()
  local r, code, _, sock = ws:connect('wss://IP:PORT/PATH', 'echo', params)
  print('WS_CONNECT', r, code)

  if r then
    driver:register_channel_handler(sock, function ()
      my_ws_tick()
    end)
  end
end

function my_ws_tick()
  local payload, opcode, c, d, err = ws:receive()
  if opcode == 9.0 then  -- PING 
    print('SEND PONG:', ws:send(payload, 10)) -- Send PONG
  end
  if err then
    ws_connect()   -- Reconnect on error
  end
end

driver:call_with_delay(1, function ()
  ws_connect()
end, 'WS START TIMER')

-- Initialize Driver
driver:run()