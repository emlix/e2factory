--- Environment Manipulation
-- @module local.environment

-- Copyright (C) 2007-2016 emlix GmbH, see file AUTHORS
--
-- This file is part of e2factory, the emlix embedded build system.
-- For more information see http://www.e2factory.org
--
-- e2factory is a registered trademark of emlix GmbH.
--
-- e2factory is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details.

local environment = {}
local e2lib = require("e2lib")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local strict = require("strict")

--- create new environment
-- @return environment
function environment.new()
    local env = {}
    local meta = { __index = environment }
    setmetatable(env, meta)
    env.dict = {}
    env.sorted = {}
    return env
end

--- set variable
-- @param env environment
-- @param var key
-- @param val value
-- @return env as passed in the first parameter
function environment.set(env, var, val)
    assertIsTable(env)
    assertIsTable(env.sorted)
    assertIsStringN(var)
    assertIsString(val)
    env.dict[var] = val
    table.insert(env.sorted, var)
    table.sort(env.sorted)
    return env
end

--- return a hash representing the environment
-- @param env environment
function environment.id(env)
    assertIsTable(env)
    assertIsTable(env.sorted)
    local hc = hash.hash_start()
    for var, val in env:iter() do
        hash.hash_append(hc, var..val)
    end
    return hash.hash_finish(hc)
end

--- merge environment from merge into env.
-- @param env environment
-- @param merge environment
-- @param override bool: shall vars from merge override vars from env?
-- @return environment as merged from env and merge
function environment.merge(env, merge, override)
    assertIsTable(env)
    assertIsTable(env.sorted)
    assertIsTable(merge)
    assertIsTable(merge.sorted)
    assertIsBoolean(override)
    for i, var in ipairs(merge.sorted) do
        if not env.dict[var] then
            table.insert(env.sorted, var)
        end
        if not env.dict[var] or override then
            env.dict[var] = merge.dict[var]
        end
    end
    return env
end

--- iterate over the environment, in alphabetical order
-- @param env environment
function environment.iter(env)
    assertIsTable(env)
    assertIsTable(env.sorted)
    local index = nil
    local function _iter(t)
        local var
        index, var = next(t, index)
        return var, env.dict[var]
    end
    return _iter, env.sorted
end

--- return a (copy of the) dictionary
-- @param env environment
-- @return a copy of the dictionary representing the environment
function environment.get_dict(env)
    assertIsTable(env)
    assertIsTable(env.sorted)
    local dict = {}
    for k,v in env:iter() do
        dict[k] = v
    end
    return dict
end

--- Write environment as key=value\n... string to file. File is created or
-- overwritten.
-- @param env Environment.
-- @param file File name.
-- @return True on success, false on error.
-- @return Error object on failure.
function environment.tofile(env, file)
    assertIsTable(env)
    assertIsTable(env.sorted)
    assertIsString(file)
    local rc, re, e, out

    out = {}
    for var, val in env:iter() do
        -- no e2lib.shquote(), some projects depend on shell variable expansion
        table.insert(out, string.format("%s=\"%s\"\n", var, val))
    end

    rc, re = eio.file_write(file, table.concat(out))
    if not rc then
        e = err.new("writing environment script")
        return false, e:cat(re)
    end

    return true
end

return strict.lock(environment)

-- vim:sw=4:sts=4:et:
