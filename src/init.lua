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
--  ===============================================================================================
--  Up to date API references are available here:
--  https://developer.bose.com/guides/bose-soundtouch-api/bose-soundtouch-api-reference
--
--  Improvements to be made:
--
--  * Add mediaInputSource capability to support changing the speakers source
--  * Add support for controlling bose speaker zones by utilizing the mediaGroup capability
--  * Add support for detecting and updating the devices label when we receive the name changed update
--  * Use luncheon for commands and discovery
--  * Coalesce the parsing of xml payload from commands and websocket updates into a single place
--
--  ===============================================================================================
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local utils = require "st.utils"
local bose_utils = require "utils"
local command = require "command"
local socket = require "cosock.socket"
local cosock = require "cosock"

local Listener = require "listener"
local discovery = require "disco"
local handlers = require "handlers"

local function discovery_handler(driver, _, should_continue)
  log.info("Starting discovery")
  local known_devices = {}
  local found_devices = {}

  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    local id = bose_utils.get_serial_number(device)
    known_devices[id] = true
  end

  while should_continue() do
    discovery.find(nil, function(device) -- This is called after finding a device
      local id = device.id
      local ip = device.ip
      if not known_devices[id] and not found_devices[id] then
        local dev_info, err = command.info(ip)
        if not dev_info then
          log.error(string.format("Failed to get info for device: %s", err))
        end
        local profile = "vtouch"
        local name = "SpatialTouch"

        -- add device
        local create_device_msg = {
          type = "LAN",
          device_network_id = id,
          label = name,
          profile = profile,
          manufacturer = "VTouch",
          model = "SpatialTouch",
          vendor_provided_label = "SpatialTouch",
        }
        log.info_with({hub_logs = true},
          string.format("Create device with: %s", utils.stringify_table(create_device_msg)))
        assert(driver:try_create_device(create_device_msg))
        found_devices[id] = true
      else
        log.info(string.format("Discovered already known device %s", id))
      end
    end)
  end
  log.info("Ending discovery")
end


--TODO remove function in favor of "st.utils" function once
--all hubs have 0.46 firmware
local function backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      --- We use this pattern because the version of math.random()
      --- that takes a range only works for integer values and we
      --- want floating point.
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2 ^ count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then base = math.min(base, max) end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

local function device_init(driver, device)
  -- at the time of authoring, there is a bug with LAN Edge Drivers where `init`
  -- may not be called on every device that gets added to the driver
  if device:get_field("init_started") then
    return
  end
  device:set_field("init_started", true)
  device.log.info_with({ hub_logs = true }, "initializing device")
  local serial_number = bose_utils.get_serial_number(device)
  -- Carry over DTH discovered ip during migration to enable some communication
  -- in cases where it takes a long time to rediscover the device on the LAN.
  if not device:get_field("ip") and device.data and device.data.ip then
    local nu = require "st.net_utils"
    local ip = nu.convert_ipv4_hex_to_dotted_decimal(device.data.ip)
    device:set_field("ip", ip, { persist = true })
    device.log.info(string.format("Using migrated ip address: %s", ip))
  end

  cosock.spawn(function()
    local backoff = backoff_builder(300, 1, 0.25)
    local dev_info
    while true do
      discovery.find(serial_number, function(found) dev_info = found end)
      if dev_info then break end
      local tm = backoff()
      device.log.info_with({ hub_logs = true }, string.format("Failed to initialize device, retrying after delay: %.1f", tm))
      socket.sleep(tm)
    end
    if not dev_info or not dev_info.ip then
      device.log.warn_with({hub_logs=true}, "device not found on network")
      return
    end
    device.log.info_with({ hub_logs = true }, string.format("Device init re-discovered device on the lan: %s", dev_info.ip))
    device:set_field("ip", dev_info.ip, {persist = true})

    device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
      capabilities.mediaPlayback.commands.play.NAME,
      capabilities.mediaPlayback.commands.pause.NAME,
      capabilities.mediaPlayback.commands.stop.NAME,
    }))
    do_refresh(driver, device)

    backoff = backoff_builder(300, 1, 0.25)
    while true do
      local listener = Listener.create_device_event_listener(driver, device)
      device:set_field("listener", listener)
      if listener:start() then break end
      local tm = backoff()
      device.log.info_with({ hub_logs = true },
        string.format("Failed to initialize device websocket listener, retrying after delay: %.1f", tm))
      socket.sleep(tm)
    end
  end, device.id .. " init_disco")
end

local function device_removed(driver, device)
  device.log.info("handling device removed...")
  local listener = device:get_field("listener")
  if listener then listener:stop() end
end

local function info_changed(driver, device, event, args)
  if device.label ~= args.old_st_store.label then
    local ip = device:get_field("ip")
    if not ip then
      device.log.warn("failed to get device ip to update the speakers name")
      local err = command.set_name(device.label)
      if err then device.log.error("failed to set device name") end
    end
  end
end

local bose = Driver("VTouch", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed,
    infoChanged = info_changed,
    added = device_init,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers.handle_on,
      [capabilities.switch.commands.off.NAME] = handlers.handle_off,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handlers.handle_play_preset,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_play,
      [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_pause,
      [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track,
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = handlers.handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handlers.handle_unmute,
      [capabilities.audioMute.commands.setMute.NAME] = handlers.handle_set_mute,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = handlers.handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handlers.handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME] = handlers.handle_set_volume,
    },
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = handlers.handle_audio_notification,
    },

  },
})

log.info("Starting bose driver")
bose:run()
log.warn("Exiting bose driver")
