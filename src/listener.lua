--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--

local log = require "log"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local socket = require "cosock.socket"
local Config = require"lustre".Config
local ws = require"lustre".WebSocket
local CloseCode = require"lustre.frame.close".CloseCode
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local bose_utils = require "utils"
local RECONNECT_PERIOD = 120 -- 2 min

--- @field device table the device the listener is listening for events
--- @field websocket table|nil the websocket connection to the device
--- @module bose.Listener
local Listener = {}
Listener.__index = Listener
Listener.WS_PORT = 8080
--- new preset has been selected


function Listener:handle_json_event(json)
  return handler.root -- used for debugging
end

function Listener:try_reconnect()
  local retries = 0
  local ip = self.device:get_field("ip")
  if not ip then
    log.warn(string.format("[%s](%s) Cannot reconnect because no device ip",
                           bose_utils.get_serial_number(self.device), self.device.label))
    return
  end
  log.info(string.format("[%s](%s) Attempting to reconnect websocket for speaker at %s",
                         bose_utils.get_serial_number(self.device), self.device.label, ip))
  while true do
    if self:start() then
      self.driver:inject_capability_command(self.device,
                                            { capability = capabilities.refresh.ID,
                                              command = capabilities.refresh.commands.refresh.NAME,
                                              args = {}
                                            })
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
  local serial_number = bose_utils.get_serial_number(self.device)
  if not ip then
    log.error_with({hub_logs=true}, "Failed to start listener, no ip address for device")
    return false
  end
  log.info_with({hub_logs=true}, string.format("[%s](%s) Starting websocket listening client on %s:%s",
                         bose_utils.get_serial_number(self.device), self.device.label, ip, url))
  if err then
    log.error_with({hub_logs=true}, string.format("[%s](%s) failed to get tcp socket: %s", serial_number, self.device.label, err))
    return false
  end
  sock:settimeout(3)
  local config = Config.default():protocol("gabbo"):keep_alive(30)
  -- websocket client 
  local websocket = ws.client(sock, "/", config)
  websocket:register_message_cb(function(msg)
    self:handle_xml_event(msg.data)
    -- log.debug(string.format("(%s:%s) Websocket message: %s", device.device_network_id, ip, utils.stringify_table(event, nil, true)))
  end):register_error_cb(function(err)
    -- TODO some muxing on the error conditions
    log.error_with({hub_logs=true}, string.format("[%s](%s) Websocket error: %s", serial_number,
                            self.device.label, err))
    if err and (err:match("closed") or err:match("no response to keep alive ping commands")) then
      self.device:offline()
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
    log.warn(string.format("[%s](%s) no websocket exists to close", bose_utils.get_serial_number(self.device),
                           self.device.label))
    return
  end
  local suc, err = self.websocket:close(CloseCode.normal())
  if not suc then
    log.error(string.format("[%s](%s) failed to close websocket: %s", bose_utils.get_serial_number(self.device),
                            self.device.label, err))
  end
end

function Listener:is_stopped()
  return self._stopped
end

return Listener
