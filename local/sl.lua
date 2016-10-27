--- Universal string list. Handy for storing result-, licence-, source names.
-- @module local.sl

-- Copyright (C) 2014 emlix GmbH, see file AUTHORS
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

local sl = {}
local class = require("class")
local err = require("err")
local e2lib = require("e2lib")
local strict = require("strict")

--- String list class that keeps entries in sorted order
-- while ignoring duplicate entries.
-- Trying to use string list with anything but strings throws an exception.
sl.sl = class("sl")

--- Initialize string list [sl:new()]
-- @return new string list object
function sl.sl:initialize()
    self._list = {}
    self._need_sort = false
end

function sl.sl:_sort_if_needed()
    if self._need_sort then
        table.sort(self._list)
        self._need_sort = false
    end
end

--- Insert an entry into the string list.
-- @param entry The entry.
function sl.sl:insert(entry)
    assert(type(entry) == "string")

    if self:lookup(entry) then
        return
    end
    table.insert(self._list, entry)
    self._need_sort = true
end

--- Insert entries of a vector into string list.
--@param entrytbl Vector of entries.
function sl.sl:insert_table(entrytbl)
    assert(type(entrytbl) == "table")

    for _,e in ipairs(entrytbl) do
        self:insert(e)
    end
end

-- Insert entries from another string list.
-- @param entrysl string list input
function sl.sl:insert_sl(entrysl)
    assert(entrysl:isInstanceOf(sl.sl))

    for _,e in ipairs(entrysl._list) do
        self:insert(e)
    end
end

--- Remove *all* matching entries from the string list.
-- @param entry The entry.
-- @return True when one or more entries were removed, false otherwise.
function sl.sl:remove(entry)
    assert(type(entry) == "string")
    local changed, i

    changed = false
    i = 1
    while self._list[i] do
        if self._list[i] == entry then
            table.remove(self._list, i)
            changed = true
            self._need_sort = true
        else
            i = i+1
        end
    end

    return changed
end

--- Check whether entry is in string list.
-- @param entry The search entry.
-- @return True if entry is in the string list, false otherwise.
function sl.sl:lookup(entry)
    assert(type(entry) == "string")

    for k, v in ipairs(self._list) do
        if v == entry then
            return true
        end
    end

    return false
end

--- Return the number of entries in the string list.
-- @return Number of entries, 0 if empty.
function sl.sl:size()
    return #self._list
end

--- Iterate through the string list in alphabetical order.
-- @return Iterator function.
function sl.sl:iter()
    local t = {}
    local i = 0

    self:_sort_if_needed()

    return function()
        i = i + 1
        return self._list[i]
    end
end

--- Create in independent string list copy.
-- @return New string list object.
function sl.sl:copy()
    local c = sl.sl:new()

    for _,e in pairs(self._list) do
        c:insert(e)
    end
    assert(self:size() == c:size())
    return c
end

--- Concatenate the string list in alphabetical order.
-- @param sep Separator, defaults to empty string.
-- @return Concatenated string.
function sl.sl:concat(sep)
    assert(sep == nil or type(sep) == "string")
    local first = true
    local cat = ""
    sep = sep or ""

    for e in self:iter() do
        if first then
            cat = e
            first = false
        else
            cat = cat..sep..e
        end
    end

    return cat
end

--- Return string list entries as an array.
-- @return Sorted array.
function sl.sl:totable()
    local t = {}
    self:_sort_if_needed()
    for _,v in ipairs(self._list) do
        table.insert(t, v)
    end
    return t
end

--- Return string list in unpacked form. Useful when dealing with
-- vectors, variadic functions, etc.
-- @return All entries as individual return values, in sorted order.
function sl.sl:unpack()
    return unpack(self:totable())
end

return strict.lock(sl)

-- vim:sw=4:sts=4:et:
