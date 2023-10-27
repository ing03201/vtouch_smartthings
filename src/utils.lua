local json = require "dkjson"
local log = require "log"
local utils = {}
utils.table_to_json = function (lua_table)
    local json_string, _, err = json.encode(lua_table, {indent=true})
    if err then
        log.error(string.format("Failed to encode json: %s", err))
        return nil
    end
    return json_string
end

utils.json_to_table = function (json_string)
    local lua_table = json.decode(json_string)
    if err then
        log.error(string.format("Failed to decode json: %s", err))
        return nil
    end
    return lua_table
end


function utils.FileRead(filePath)
    local data = nil
    local handle = io.open(filePath, "r")
 
    if handle then
        data = json:decode(handle:read("*a"))
        io.close(handle)
    end
    
    return data
end
 
-- file write
function utils.FileWrite(filePath, data, pretty)    
    local handle = io.open(filePath, "w+")
    
    if handle then
        if pretty then
            handle:write(json:encode_pretty(data))
        else
            handle:write(json:encode(data))
        end
        io.close(handle)
    end
end
function utils.has_value_in_table (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

return utils