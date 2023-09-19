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
--    ===============================================================================================
--    Up to date API references are available here:
--    https://developer.vtouch.com/guides/vtouch-soundtouch-api/vtouch-soundtouch-api-reference
--
--    Improvements to be made:
--
--    * Add mediaInputSource capability to support changing the speakers source
--    * Add support for controlling vtouch speaker zones by utilizing the mediaGroup capability
--    * Add support for detecting and updating the devices label when we receive the name changed update
--    * Use luncheon for commands and discovery
--    * Coalesce the parsing of xml payload from commands and websocket updates into a single place
--
--    ===============================================================================================
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local vtouch_utils = require "utils"
local socket = require "cosock.socket"
local cosock = require "cosock"
local net_utils = require "st.net_utils"
local Listener = require "listener"
local mdns = require "st.mdns"


local function discovery_handler(driver, _, should_continue)
    local SERVICE_TYPE = "_vtouch._tcp"
    local DOMAIN = "local"
    log.info("Starting discovery")
    while should_continue() do
        local mdns_responses, err = mdns.discover(SERVICE_TYPE, DOMAIN)
        if err ~= nil then
            log.error_with({hub_logs=true}, "Error discovering vtouch: " .. err)
            return
        end

        for _, info in ipairs(mdns_responses.found) do 
            if not net_utils.validate_ipv4_string(info.host_info.address) then
                log.trace("Invalid IP address for vtouch device: " .. info.host_info.address)
                return
            end

            if info.service_info.service_type ~= SERVICE_TYPE then
                log.trace("Invalid service type for vtouch device: " .. info.service_info.service_type)
                return
            end

            if info.service_info.domain ~= DOMAIN then
                log.trace("Invalid domain for vtouch device: " .. info.service_info.domain)
                return
            end
            local ip = info.host_info.address
            log.info(string.format("Discovered vtouch device at %s", ip))
            local create_msg = driver:try_create_device({
                type = "LAN",
                device_network_id = ip ,
                label = "Spatial Touch",
                profile = "vtouch",
                manufacturer = "VTouch",
                model = "Spatial Touch",
                vendor_provided_label = "VTouch",
            })
            assert( driver:try_create_device(create_msg), "failed to create VTouch device" )
        end
    end
    log.info("Ending discovery")
end

local function do_refresh(driver, device, cmd)
    -- get speaker playback state
    local deviceIp = device.device_network_id
    if not deviceIp then
        device.log.warn("failed to get device ip to refresh the device state")
        return
    end
    -- restart listener if needed
    local listener = device:get_field("listener")
    if listener and (listener:is_stopped() or listener.websocket == nil)then
        device.log.info("Restarting listening websocket client for device updates")
        listener:stop()
        socket.sleep(1) --give time for Lustre to close the websocket
        if not listener:start() then
            device.log.warn_with({hub_logs = true}, "Failed to restart listening websocket client for device updates")
        end
    end
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
    device.log.debug_with({ hub_logs = true }, string.format("device data: %s", device.data.ip))
    -- Carry over DTH discovered ip during migration to enable some communication
    -- in cases where it takes a long time to rediscover the device on the LAN.
    if not device.device_network_id and device.data and device.data.ip then
        local ip = device.device_network_id
        device:set_field("ip", ip, { persist = true })
        device.log.info(string.format("Using migrated ip address: %s", ip))
    end

    cosock.spawn(function()
        local backoff = backoff_builder(300, 1, 0.25)
        local ip = device.device_network_id
        device.log.info_with({ hub_logs = true }, string.format("Device init re-discovered device on the lan: %s", ip))
        device:set_field("ip", ip, {persist = true})

        device:emit_event(capabilities.switch.switch.on())
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
        local ip = device.device_network_id
        if not ip then
            device.log.warn("failed to get device ip to update the vtouch name")
            local err = command.set_name(device.label)
            if err then device.log.error("failed to set device name") end
        end
    end
end

local vtouch = Driver("vtouch", {
    discovery = discovery_handler,
    lifecycle_handlers = {
        init = device_init,
        removed = device_removed,
        infoChanged = info_changed,
        added = device_init,
    },
    capability_handlers = {
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = do_refresh,
        }
    },
})

log.info("Starting vtouch driver")
vtouch:run()
log.warn("Exiting vtouch driver")
