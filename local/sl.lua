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

-- ----------------------------------------------------------------------------
-- There is plenty of optimization potential here, however the string lists
-- are usually very small: 0 - 100 entries. Don't waste time.
-- ----------------------------------------------------------------------------

--- Class "sl" for keeping string lists.
-- Trying to use string list with anything but strings throws an exception.
sl.sl = class("sl")

--- Initialize string list [sl:new()]. Merge and unique can't be set both.
-- @param merge Whether entries are to be merged, defaults to false (boolean).
-- @param unique Whether inserting duplicate entries raises errors,
--               defaults to false (boolean).
function sl.sl:initialize(merge, unique)
    assert(merge == nil or type(merge) == "boolean")
    assert(unique == nil or type(unique) == "boolean")
    assert(not (merge and unique))

    self._merge = merge or false
    self._unique = unique or false
    self._list = {}
end

--- Insert an entry into the string list.
-- @param entry The entry.
-- @return True on success, false when the entry is not unique.
function sl.sl:insert(entry)
    assert(type(entry) == "string")

    if self._merge then
        if self:lookup(entry) then
            return true
        end
    elseif self._unique then
        if self:lookup(entry) then
            return false
        end
    end
    table.insert(self._list, entry)
    return true
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

--- Iterate through the string list in insertion order.
-- @return Iterator function.
function sl.sl:iter_inserted()

    local i = 0

    return function()
        i = i + 1
        return self._list[i]
    end
end

--- Iterate through the string list in alphabetical order.
-- @return Iterator function.
function sl.sl:iter_sorted()
    local t = {}
    local i = 0

    for _,v in ipairs(self._list) do
        table.insert(t, v)
    end
    table.sort(t)

    return function()
        i = i + 1
        return t[i]
    end
end

--- Create in independent string list copy.
-- @return New string list object.
function sl.sl:copy()
    local c = sl.sl:new(self._merge, self._unique)
    for e in self:iter_inserted() do
        assert(c:insert(e))
    end
    assert(self:size() == c:size())
    return c
end

--- Concatenate the string list in alphabetical order.
-- @param sep Separator, defaults to empty string.
-- @return Concatenated string.
function sl.sl:concat_sorted(sep)
    assert(sep == nil or type(sep) == "string")
    local first = true
    local cat = ""
    sep = sep or ""

    for e in self:iter_sorted() do
        if first then
            cat = e
            first = false
        else
            cat = cat..sep..e
        end
    end

    return cat
end

--- Return string list entries as an array, in insertion order.
-- @return Array in insertion order.
function sl.sl:totable_inserted()
    local t = {}
    for _,v in ipairs(self._list) do
        table.insert(t, v)
    end
    return t
end

--- Return string list entries as an array, in insertion order.
-- @return Array in insertion order.
function sl.sl:totable_sorted()
    return table.sort(self:totable_inserted())
end

--[[
local function selftest()
    local s1 = sl.sl:new()

    assert(s1:size() == 0)
    assert(s1.class.name == "sl")

    s1:insert("ccc")
    s1:insert("bbb")
    s1:insert("aaa")
    s1:insert("aaa")

    assert(s1:size() == 4)

    local c = 1
    for entry in s1:iter_inserted() do
        assert(c <= s1:size() and c > 0)
        if c == 1 then assert(entry == "ccc") end
        if c == 2 then assert(entry == "bbb") end
        if c == 3 then assert(entry == "aaa") end
        if c == 4 then assert(entry == "aaa") end
        c = c+1
    end

    assert(s1:lookup("foo") == false)
    assert(s1:lookup("bbb") == true)

    s1:insert("xxx")
    assert(s1:size() == 5)
    c = 1
    for entry in s1:iter_sorted() do
        assert(c <= s1:size() and c > 0)
        if c == 1 then assert(entry == "aaa") end
        if c == 2 then assert(entry == "aaa") end
        if c == 3 then assert(entry == "bbb") end
        if c == 4 then assert(entry == "ccc") end
        if c == 5 then assert(entry == "xxx") end
        c = c+1
    end

    assert(s1:remove("doesnotexist") == false)
    assert(s1:remove("aaa") == true)
    assert(s1:size() == 3)
    c = 1
    for entry in s1:iter_sorted() do
        assert(c <= s1:size() and c > 0)
        --e2lib.logf(1, "entry=%s", entry)
        if c == 1 then assert(entry == "bbb") end
        if c == 2 then assert(entry == "ccc") end
        if c == 3 then assert(entry == "xxx") end
        c = c+1
    end

    assert(s1:concat_sorted() == "bbbcccxxx")
    assert(s1:concat_sorted("y") == "bbbycccyxxx")

    local s2 = sl.sl:new(false, true)

    c = false
    for _,v in ipairs({"bbb", "aaa", "xxx", "foo", "bla", "bar", "xxx"}) do
        if not s2:insert(v) then
            c = true
            assert(v == "xxx")
        end
    end
    assert(c == true)

    local s3 = sl.sl:new(true, false)

    for _,v in ipairs({"bbb", "aaa", "xxx", "foo", "bar", "bar", "xxx", "y"}) do
        assert(s3:insert(v) == true)
    end
    assert(s3:size() == 6)

    local s4 = sl.sl:new()
    s4:insert("")
    s4:insert("")
    s4:insert("")

    assert(s4:concat_sorted() == "")
    assert(s4:concat_sorted("x") == "xx")
end

selftest()
--]]

return strict.lock(sl)

-- vim:sw=4:sts=4:et: