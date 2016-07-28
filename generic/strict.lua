--- Strict table handling.
-- @module generic.strict

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

--- Lock a table against adding fields explicitly or by implicit assignment.
-- Prevent reading from undeclared fields.
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
                " to undeclared field '"..tostring(k).."'")
        end

        -- error("assignment to "..tostring(t).."["..
        --    tostring(k).."]="..tostring(v))
        rawset(t, k, v)
    end

    mt.__index = function(t, k)
        local mt = getmetatable(t)
        if type(k) == 'string' and not mt.__declared[k] and what() ~= "C" then
            error("variable "..k.." is not declared", 2)
        end

        return rawget(t, k)
    end

    setmetatable(t, mt)

    return t
end

--- Unlock a table that was protected against adding and assigning to fields.
-- @param t table to unlock.
-- @return the unlocked table.
function strict.unlock(t)
    assert(type(t) == "table")

    if not strict.islocked(t) then
        error("table is not locked")
    end

    setmetatable(t, nil)

    return t
end

--- Test whether a table is locked.
-- The implementation determines this by looking at certain keys, it's therefore
-- not 100% reliable.
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

--- Declare new fields of a table.
-- Note that declaring existing fields raise a fatal error.
-- @param t table to declare fields in
-- @param fields array of field strings to declare.
-- @return the modified table
function strict.declare(t, fields)
    assert(type(t) == "table")
    assert(type(fields) == "table")
    local mt = getmetatable(t)

    for _,f in ipairs(fields) do
        assert(type(f) == "string")

        if mt.__declared[f] then
            error("field '"..f.."' is already declared")
        end
        mt.__declared[f] = true
    end

    return t
end

--- Remove fields from a table.
-- Note that the fields must be declared, otherwise a fatal error is raised.
-- @param t table to remove fields from
-- @param fields array of field strings to remove.
-- @return the modified table
function strict.undeclare(t, fields)
    assert(type(t) == "table")
    assert(type(fields) == "table")
    local mt = getmetatable(t)

    for _,f in ipairs(fields) do
        assert(type(f) == "string")

        if not mt.__declared[f] then
            error("field '"..f.."' was not declared")
        end

        mt.__declared[f] = nil
        rawset(t, f, nil)
    end

    return t
end

return strict.lock(strict)

-- vim:sw=4:sts=4:et:
