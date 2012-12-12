--- Locking module.
--
-- This module maintains lock directories within a lock context.
-- Remaining lock directories can be removed by calling the cleanup
-- method.
--
-- @module generic.lock

--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2012      Tobias Ulmer <tu@emlix.com>, emlix GmbH
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
-- @return boolean
function lock.lock(l, dir)
    local e = err.new("locking failed")

    local rc, re = e2lib.mkdir(dir)
    if not rc then
        return false, e:cat(re)
    end

    table.insert(l.locks, dir)
    return true
end

--- remove a lock directory
-- @param l table: lock object
-- @param dir string: lock directory
-- @return boolean
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
        end
    end

    return true
end

-- remove all remaining lock directories
-- @param l table: lock object
function lock.cleanup(l)
    while #l.locks > 0 do
        lock.unlock(l, l.locks[1])
    end
end

--[[
local test=false
if test then
    -- some dummy functions to test without context...
    function err.new(x)
        return true
    end
    e2lib = {}
    e2lib.mkdir = function(x)
        print("mkdir " .. x)
        return true
    end
    e2lib.rmdir = function(x)
        print("rmdir " .. x)
        return true
    end

    l = new()

    l:lock("/tmp/foo1")
    l:lock("/tmp/foo2")
    l:lock("/tmp/foo3")
    l:unlock("/tmp/foo2")
    l:cleanup()
end
]]

return strict.lock(lock)

-- vim:sw=4:sts=4:et:
