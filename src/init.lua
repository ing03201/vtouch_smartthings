local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local json require "dkjson"
local ws = require('websocket.client').sync({ timeout = 30 })

local cap_object = capabilities["talentautumn23825.vtouch.object"]
local cap_x = capabilities["talentautumn23825.vtouch.x"]
local cap_y = capabilities["talentautumn23825.vtouch.y"]
local cap_z = capabilities["talentautumn23825.vtouch.z"]
local cap_trigger = capabilities["talentautumn23825.vtouch.trigger"]
local cap_direction = capabilities["talentautumn23825.vtouch.direction"]

local url = ""
function ws_connect()
    local r, code, _, sock = ws:connect('ws://IP:PORT')
    log.debug('WS_CONNECT', r, code)

    if r then
        driver:register_channel_handler(sock, function ()
        ws_listen()
        end)
    end
end

function do_refresh()

end
function ws_listen()
    local payload, opcode, c, d, err = ws:receive()
    if opcode == 9.0 then  -- PING 
        log.debug('SEND PONG:', ws:send(payload, 10)) -- Send PONG
    end
    if err then
        ws_connect()   -- Reconnect on error
    end
    local data, pos, err = json.decode(payload)
    if err then
        log.debug('JSON DECODE ERROR:', err)
    end 
    if data then
        log.debud('JSON DATA:', data)
        -- Update device attributes based on received data
        device:emit_event(capabilities.switch.switch.on(data.switch))
        device:emit_event(capabilities.switchLevel.level(data.level))
    end
end


local driver_template = {
    supported_capabilities = {
        capabilities.switch,
        capabilities.switchLevel
    },
    lifecycle_handlers = {
        init = function(driver, device)
            -- Initialize device
            ip = device.preferences.deviceaddr
        end
    }
}

local driver = Driver("vtouch", driver_template)
driver:run()