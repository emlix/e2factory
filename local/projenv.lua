--- Project environment module. Deals with the project-wide global and result
-- specific configuration. It handles evaluating and verifying the file
-- 'proj/env' and its include directives.
-- @module local.projenv
local projenv = {}
package.loaded["projenv"] = projenv

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local environment = require("environment")
local err = require("err")
local result = require("result")
local strict = require("strict")

local _global_env = false
local _result_env = {}

--- Get the project wide global environment
-- @return Environment object
function projenv.get_global_env()
    if not _global_env then
        _global_env = environment.new()
    end
    return _global_env
end

--- Get the project wide *result* environment.
-- Note that an unknown resultname will return a new environment.
-- @param resultname Result name
-- @return Environment object
function projenv.get_result_env(resultname)
    assertIsStringN(resultname)

    if not _result_env[resultname] then
        _result_env[resultname] = environment.new()
    end
    return _result_env[resultname]
end

--- Get a *copy* of the project wide environment and project wide result
-- environment merged into one. Very similar to proj/env and friends.
-- Writes to this table do not propagate to other results etc.
-- @return Table filled just like proj/env
function projenv.safe_global_res_env_table()
    local gt = projenv.get_global_env():get_dict()

    for resultname, resenv in pairs(_result_env) do
        gt[resultname] = resenv:get_dict()
    end

    return gt
end

local function _load_env_config(file)
    e2lib.logf(3, "loading environment: %s", file)
    local e = err.new("loading environment: %s", file)
    local rc, re
    local merge_error = false

    local function mergeenv(data)
        -- upvalues: file, _load_env_config(), merge_error
        local rc, re

        if type(data) == "string" then
            -- filename
            rc, re = _load_env_config(data)
            if not rc then
                merge_error = re
                return
            end
        elseif type(data) == "table" then
            -- environment table
            for key, value in pairs(data) do

                if type(key) ~= "string" or
                    (type(value) ~= "string" and type(value) ~= "table") then
                    merge_error = err.new("invalid environment entry in %s: %s=%s",
                        file, tostring(key), tostring(value))
                    return
                end

                if type(value) == "string" then

                    e2lib.logf(3, "global env: %-15s = %-15s", key, value)
                    projenv.get_global_env():set(key, value)

                else
                    local resultname = key

                    for key1, value1 in pairs(value) do
                        if type(key1) ~= "string" or type(value1) ~= "string" then
                            merge_error = err.new(
                                "invalid environment entry in %s [%s]: %s=%s",
                                file, key, tostring(key1), tostring(value1))
                            return
                        end

                        e2lib.logf(3, "result env: %-15s = %-15s [%s]", key1, value1, key)

                        projenv.get_result_env(key):set(key1, value1)
                    end
                end
            end
        else
            merge_error = err.new("invalid environment type: %s", tostring(data))
        end
    end

    local info = e2tool.info()
    local path = e2lib.join(info.root, file)

    local mt = {
        __index = function(t, key)
            -- simulate a table that's updating itself as we read the config
            -- called for env[key] and e2env[key]
            return projenv.safe_global_res_env_table()[key]
        end,
        __call = function(t, data)
            -- called for env "string" and env {}
            -- use not documented for e2env
            mergeenv(data)
        end
    }

    local g = {
        e2env = setmetatable({}, mt), -- XXX: no longer necessary, alias for env
        env = setmetatable({}, mt),
        string = e2lib.safe_string_table(),
    }
    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, e:cat(re)
    end

    if merge_error then
        return false, merge_error
    end
    return true
end


--- Load the environment config. Follows includes.
-- @param file File name of config
-- @return True on success, false on failure
-- @return Err object on failure.
-- @see projenv.verify_result_envs
function projenv.load_env_config(file)
    return _load_env_config(file)
end

--- Check load_env_config() didn't create any result environments for unknown
-- results.
-- @return True on success, false on failure
-- @return Err object on failure.
function projenv.verify_result_envs()
    local e

    e = err.new("in project environment config:")

    -- check for environment for non-existent results
    for resultname in pairs(_result_env) do
        if not result.results[resultname] then
            e:append("found environment for unknown result: %s",
                resultname)
        end
    end

    if e:getcount() > 1 then
        return false, e
    end

    return true
end

return strict.lock(projenv)

