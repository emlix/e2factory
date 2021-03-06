--- Locking module.
--
-- This module maintains lock directories within a lock context.
-- Remaining lock directories can be removed by calling the cleanup
-- method.
--
-- @module generic.lock

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

local lock = {}
local err = require("err")
local e2lib = require("e2lib")
local strict = require("strict")

--- create a new lock context
-- @return table: the lock context
function lock.new()
    local l = {
        locks = {},
    }

    for k,v in pairs(lock) do
        l[k] = v
    end

    return l
end

--- create a lock directory
-- @param l table: lock object
-- @param dir string: lock directory
-- @return True on success, false on error.
-- @return Err object on failure.
function lock.lock(l, dir)
    local rc, re = e2lib.mkdir(dir)
    if not rc and err.eccmp(re, 'EEXIST') then
        local e = err.new('chroot already in use!')
        e:append('if this is an error, try rmdir %q', dir)
        return false, e
    elseif not rc then
        local e = err.new("locking failed")
        return false, e:cat(re)
    end

    table.insert(l.locks, dir)
    return true
end

--- remove a lock directory
-- @param l table: lock object
-- @param dir string: lock directory
-- @return True on success, false on error.
-- @return Err object on failure.
function lock.unlock(l, dir)
    local e = err.new("unlocking failed")
    local rc, re

    for i,x in ipairs(l.locks) do
        if dir == x then
            table.remove(l.locks, i)
            rc, re = e2lib.rmdir(dir)
            if not rc then
                return false, e:cat(re)
            end

            break
        end
    end

    return true
end

-- remove all remaining lock directories
-- @param l table: lock object
function lock.cleanup(l)
    local rc, re

    while #l.locks > 0 do
        rc, re = lock.unlock(l, l.locks[1])
        if not rc then
            e2lib.logf(4, "unlocking lock failed: %s", re:tostring())
        end
    end
    e2lib.logf(4, "all locks released")
end

return strict.lock(lock)

-- vim:sw=4:sts=4:et:
