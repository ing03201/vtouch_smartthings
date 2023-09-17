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
    local lua_table, _, err = json.decode(json_string, 1, nil)
    if err then
        log.error(string.format("Failed to decode json: %s", err))
        return nil
    end
    return lua_table
end
return utils