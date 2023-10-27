local net_utils = require "st.net_utils"
local driver = require "st.driver"
local log = require "log"
local utils = require "utils"

local mdns = require "st.mdns"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"


local SERVICE_TYPE = "_vtouch._tcp"
local DOMAIN = "local"
local Disco = {
    known_network_id = {},
    ServiceType = SERVICE_TYPE,
    Domain = DOMAIN,
    new_network_id = {}
}

function Disco:do_mdns()
    local mdns_responses, err = mdns.discover(Disco.ServiceType, Disco.Domain)
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
        if(not utils.has_value_in_table(Disco.known_network_id, ip)) then
            Disco.new_network_id[ip] = true
        end
    end
end

function Disco.discover(driver, _, should_continue)
    log.trace("Discovering vtouch devices")
    for _, device in ipairs(driver:get_devices()) do
        local dni = device:get_field("ip")
        if dni then
            Disco.known_network_id[dni] = true
        end
    end
    Disco:do_mdns()
    Disco.create_device()
end

function Disco.create_device()
    for ip, val in pairs(Disco.new_network_id) do
        if(val) then
            log.info(string.format("Discovered vtouch device at %s", ip))
            local create_device_msg = assert(
                driver:try_create_device({
                    type = "LAN",
                    device_network_id = ip ,
                    label = "Spatial Touch",
                    profile = "vtouch",
                    manufacturer = "VTouch",
                    model = "Spatial Touch",
                    vendor_provided_label = "VTouch",
                }),
                "failed to create device"
            )
            Disco.new_network_id[ip] = false
        end
    end
    Disco.new_network_id = {}
end

return Disco