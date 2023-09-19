--    Copyright 2021 SmartThings
--
--    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--    except in compliance with the License. You may obtain a copy of the License at:
--
--            http://www.apache.org/licenses/LICENSE-2.0
--
--    Unless required by applicable law or agreed to in writing, software distributed under the
--    License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--    either express or implied. See the License for the specific language governing permissions
--    and limitations under the License.
--

local log = require "log"
local json = require "dkjson"
local socket = require "cosock.socket"
local Config = require"lustre".Config
local ws = require"lustre".WebSocket
local CloseCode = require"lustre.frame.close".CloseCode
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local vtouch_utils = require "utils"

local capObjId = capabilities["earthbench45333.object"]
local capEye = capabilities["earthbench45333.eye"]
local capFinger = capabilities["earthbench45333.finger"]
local capObjNormalized = capabilities["earthbench45333.objnormalizedxy"]
local capTrigger = capabilities["earthbench45333.trigger"]
local capDirection = capabilities["earthbench45333.direction"]
local RECONNECT_PERIOD = 30 -- 30 Sec

--- @field device table the device the listener is listening for events
--- @field websocket table|nil the websocket connection to the device
--- @module VTouch.Listener
local Listener = {}
Listener.__index = Listener
Listener.WS_PORT = 20000
Listener._status = false
Listener.funcTable = {
    ["objId"] = Listener.objId_update,
    ["eye"] = Listener.eye_update,
    ["finger"] = Listener.finger_update,
    ["objNormalized"] = Listener.objNormalized_update,
    ["trigger"] = Listener.trigger_update,
    ["direction"] = Listener.direction_update
}

function Listener:name_update(new_name)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) name_update: %s", ip,
                                                 self.device.label, new_name))
    self.device:try_update_metadata({vendor_provided_label = new_name})
end

function Listener:objId_update(value)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) objId_update: %s", ip,
                                                 self.device.label, value))
    if value ~= nil then
        self.device:emit_event(capObjId.object(tostring(obj_id)))
    end
end

function Listener:eye_update(eye)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) eye_update: %s", ip,
                                                 self.device.label, eye))
    self.device:emit_event(capEye.eye({eye.x, eye.y, eye.z} ))
end

function Listener:finger_update(finger)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) finger_update: %s", ip,
                                                 self.device.label, finger))
    self.device:emit_event(capFinger.finger({finger.x, finger.y, finger.z}))
end

function Listener:objNormalized_update(objNormalized)
    local ip = self.device:get_field("ip")
    local normalizedXY = {}
    for key, value in pairs(objNormalized) do
        normalizedXY[key] = value
    end
    log.info(string.format("[%s](%s) objNormalized_update: %s %s", ip,
                                                 self.device.label, normalizedXY.x, normalizedXY.y))
    self.device:emit_event(capObjNormalized.XY( { normalizedXY.x, normalizedXY.y } ))
end

function Listener:trigger_update(trigger)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) trigger_update: %s", ip,
                                                 self.device.label, trigger))
    self.device:emit_event(capTrigger.trigger(trigger))
end

function Listener:direction_update(direction)
    local ip = self.device:get_field("ip")
    log.info(string.format("[%s](%s) direction_update: %s", ip,
                                                 self.device.label, direction))
    self.device:emit_event(capDirection.direction(direction))
end

function Listener:handle_json_event(jsonData)
    local dataTable = json.decode(jsonData)
    for key, value in pairs(dataTable) do
        if key == "objId" then
            self.objId_update(value)
        elseif key == "eye" then
            self.eye_update(value)
        elseif key == "finger" then
            self.finger_update(value)
        elseif key == "objNormalized" then
            self.objNormalized_update(value)
        elseif key == "trigger" then
            self.trigger_update(value)
        elseif key == "direction" then
            self.direction_update(value)
        end
        log.info(string.format("key: %s, value: %s", key, value))
    end
end

function Listener:try_reconnect()
    local retries = 0
    local ip = self.device:get_field("ip")
    if not ip then
        log.warn(string.format("[%s](%s) Cannot reconnect because no device ip",
                                                     ip, self.device.label))
        return
    end
    log.info(string.format("[%s](%s) Attempting to reconnect websocket for vtouch at %s",
                                                 ip, self.device.label, ip))
    while true do
        if self:start() then
            self.driver:inject_capability_command(
                self.device,
                {
                    capability = capabilities.refresh.ID,
                    command = capabilities.refresh.commands.refresh.NAME,
                    args = {}
                }
            )
            return
        end
        retries = retries + 1
        log.info(string.format("Reconnect attempt %s in %s seconds", retries, RECONNECT_PERIOD))
        socket.sleep(RECONNECT_PERIOD)
    end
end

--- @return success boolean
function Listener:start()
    local url = "/"
    local sock, err = socket.tcp()
    local ip = self.device:get_field("ip")
    local serial_number = ip
    if not ip then
        log.error_with({hub_logs=true}, "Failed to start listener, no ip address for device")
        return false
    end
    log.info_with({hub_logs=true}, string.format("[%s](%s) Starting websocket listening client on %s:%s",
                                                 ip, self.device.label, ip, url))
    if err then
        log.error_with({hub_logs=true}, string.format("[%s](%s) failed to get tcp socket: %s", serial_number, self.device.label, err))
        return false
    end
    sock:settimeout(3)
    local config = Config.default():protocol(""):keep_alive(30)
    local websocket = ws.client(sock, "/", config)
    websocket:register_message_cb(function(msg)
        self:handle_json_event(msg.data)
        -- log.debug(string.format("(%s:%s) Websocket message: %s", device.device_network_id, ip, utils.stringify_table(event, nil, true)))
    end):register_error_cb(function(err)
        -- TODO some muxing on the error conditions
        log.error_with({hub_logs=true}, string.format("[%s](%s) Websocket error: %s", serial_number,
                                                        self.device.label, err))
        if err and (err:match("closed") or err:match("no response to keep alive ping commands")) then
            self.device:offline()
            self._status = false
            self:try_reconnect()
        end
    end)
    websocket:register_close_cb(function(reason)
        log.info_with({hub_logs=true}, string.format("[%s](%s) Websocket closed: %s", serial_number,
                                                     self.device.label, reason))
        self.websocket = nil -- TODO make sure it is set to nil correctly
        if not self._stopped then self:try_reconnect() end
    end)
    local _
    _, err = websocket:connect(ip, Listener.WS_PORT)
    if err then
        log.error_with({hub_logs=true}, string.format("[%s](%s) failed to connect websocket: %s", serial_number, self.device.label, err))
        return false
    end
    log.info_with({hub_logs=true}, string.format("[%s](%s) Connected websocket successfully", serial_number,
                                                 self.device.label))
    self.status = true
    self._stopped = false
    self.websocket = websocket
    self.device:online()
    return true
end

function Listener.create_device_event_listener(driver, device)
    return setmetatable({device = device, driver = driver, _stopped = true}, Listener)
end

function Listener:stop()
    self._stopped = true
    if not self.websocket then
        log.warn(string.format("[%s](%s) no websocket exists to close", ip,
                                                     self.device.label))
        return
    end
    local suc, err = self.websocket:close(CloseCode.normal())
    if not suc then
        log.error(string.format("[%s](%s) failed to close websocket: %s", ip,
                                                        self.device.label, err))
    end
end

function Listener:is_stopped()
    return self._stopped
end

return Listener
