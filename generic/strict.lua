--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2012 Tobias Ulmer <tu@emlix.com>, emlix GmbH
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

local strict = {}

local function what()
    local d = debug.getinfo(3, "S")
    return d and d.what or "C"
end

--- Lock a table against adding members explicitly or by implicit assignment.
-- @param t table to lock
function strict.lock(t)
    assert(type(t) == "table")
    local mt = {}
    mt.__declared = {}

    if getmetatable(t) ~= nil then
        error("metatable already set")
    end

    mt.__newindex = function(t, k, v)
        local mt = getmetatable(t)
        if not mt.__declared[k] and what() ~= "C" then
            error("assignment in "..tostring(t)..
                " to undeclared variable '"..tostring(k).."'")
        end

        -- error("assignment to "..tostring(t).."["..
        --    tostring(k).."]="..tostring(v))
        rawset(t, k, v)
    end

    mt.__index = function(t, k, v)
        local mt = getmetatable(t)
        if not mt.__declared[k] and what() ~= "C" then
            error("variable "..k.." is not declared")
        end

        return rawget(t, k)
    end

    setmetatable(t, mt)

    return t
end

--- Unlock a table that was protected against adding and assigning to members.
-- Not implemented yet.
-- @param t table to unlock
function strict.unlock(t)
    assert(type(t) == "table")
    error("strict.unlock() is not implemented yet")
end

--- Test whether a table is locked.
-- @param t table to check
-- @return true if it's locked, false if not
function strict.islocked(t)
    assert(type(t) == "table")
    local mt = getmetatable(t)

    if mt and mt.__declared and mt.__newindex and mt.__index then
        return true
    end

    return false
end

--- Declare new members of a table and assign them a value.
-- Note that declaring already declared members causes an error message to be
-- raised.
-- @param t table to declare members in
-- @param values table of member (key) / value pairs.
function strict.declare(t, values)
    assert(type(t) == "table")
    assert(type(values) == "table")
    local mt = getmetatable(t)

    for k, v in pairs(values) do
        if mt.__declared[k] then
            error("variable '"..k.."' is already declared")
        end
        mt.__declared[k] = true
        rawset(t, k, v)
    end

    return t
end

--- Remove members from a table.
-- Note that the members must be declared, otherwise a fatal error is raised.
-- Also note that values in the values table are ignored, only keys are
-- considered.
-- @param t table to remove members from
-- @param values table of members to delete. Must be in key/value form.
function strict.undeclare(t, values)
    assert(type(t) == "table")
    assert(type(values) == "table")
    local mt = getmetatable(t)

    for k, v in pairs(values) do
        if not mt.__declared[k] then
            error("variable '"..k.."' was not declared in the first place")
        end

        mt.__declared[k] = nil
        rawset(t, k, nil)
    end

    return t
end

return strict.lock(strict)

-- vim:sw=4:sts=4:et:
