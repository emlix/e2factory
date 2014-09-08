--- Environment Manipulation
-- @module local.environment

--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2007-2009 Gordon Hecker <gh@emlix.com>, emlix GmbH
   Copyright (C) 2007-2009 Oskar Schirmer <os@emlix.com>, emlix GmbH
   Copyright (C) 2007-2008 Felix Winkelmann, emlix GmbH

   For more information have a look at http://www.e2factory.org

   e2factory is a registered trademark by emlix GmbH.

   This file is part of e2factory, the emlix embedded build system.

   e2factory is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

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
    env.dict[var] = val
    table.insert(env.sorted, var)
    table.sort(env.sorted)
    return env
end

--- return a hash representing the environment
-- @param env environment
function environment.id(env)
    local hc = hash.hash_start()
    for var, val in env:iter() do
        hash.hash_append(hc, string.format("%s=%s", var, val))
    end
    return hash.hash_finish(hc)
end

--- merge environment from merge into env.
-- @param env environment
-- @param merge environment
-- @param override bool: shall vars from merge override vars from env?
-- @return environment as merged from env and merge
function environment.merge(env, merge, override)
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
    local dict = {}
    for k,v in env:iter() do
        dict[k] = v
    end
    return dict
end

--- Write environment as key=value\n... string to file. File is created or
-- truncated. Value is quoted with e2lib.shquote() so the file can be sourced
-- by a shell.
-- @param env Environment.
-- @param file File name.
-- @return True on success, false on error.
-- @return Error object on failure.
function environment.tofile(env, file)
    local rc, re, e, out

    out = {}
    for var, val in env:iter() do
        table.insert(out, string.format("%s=%s\n", var, e2lib.shquote(val)))
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
