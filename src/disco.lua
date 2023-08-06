local mdns = requires('st.mdns')
local function discoverDevices( deviceName, service)
  local serviceType = "vtouch._tcp"
  local domain 	  = "local"
  local discoveredDevices = {}
  local i = 0
  local discoveryResponses = mdns.discover(serviceType, domain) or {} 
  log.info('*** mDNS discovered ' .. #discoveryResponses.found .. " devices")
  for idx, answer in ipairs(discoveryResponses.found) do
    if string.find(answer.service_info.name, deviceName) then
        log.info('*** Discovered a ' .. deviceName .. ' device: ', idx, answer.service_info.name, answer.host_info.address, answer.host_info.port)
        i = i+1
        discoveredDevices[i] = {
      name 		= answer.service_info.name,
      ipAddress 	= answer.host_info.address,
      port 		= answer.host_info.port
        }
    end
  end
  return i, discoveredDevices
end