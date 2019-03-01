--- Assert functions.
-- All assert functions are loaded into the global environment _G.
-- They can be used anywhere after the first require('assrt').
-- Function names and behavior match luaunit. A few less common functions are
-- left unimplemented for now.
-- @module generic.assert

-- Copyright (C) 2016 emlix GmbH, see file AUTHORS
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

local assrt = {}
local strict = require('strict')

-- _is_table_equals() and _str_match() are taken from luaunit under the
-- following license:
--
-- This software is distributed under the BSD License.
--
-- Copyright (c) 2005-2014, Philippe Fremy <phil at freehackers dot org>
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are
-- met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.  Redistributions
-- in binary form must reproduce the above copyright notice, this list of
-- conditions and the following disclaimer in the documentation and/or
-- other materials provided with the distribution.  THIS SOFTWARE IS
-- PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
-- EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
-- PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
-- LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
-- NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

local function _is_table_equals(actual, expected)
    if (type(actual) == 'table') and (type(expected) == 'table') then
        if (#actual ~= #expected) then
            return false
        end
        local k,v
        for k,v in ipairs(actual) do
            if not _is_table_equals(v, expected[k]) then
                return false
            end
        end
        for k,v in ipairs(expected) do
            if not _is_table_equals(v, actual[k]) then
                return false
            end
        end
        for k,v in pairs(actual) do
            if not _is_table_equals(v, expected[k]) then
                return false
            end
        end
        for k,v in pairs(expected) do
            if not _is_table_equals(v, actual[k]) then
                return false
            end
        end
        return true
    elseif type(actual) ~= type(expected) then
        return false
    elseif actual == expected then
        return true
    end
    return false
end

local function _str_match(s, pattern, start, final)
    -- return true if s matches completely the pattern from index start to index end
    -- return false in every other cases
    -- if start is nil, matches from the beginning of the string
    -- if end is nil, matches to the end of the string
    if start == nil then
        start = 1
    end

    if final == nil then
        final = string.len(s)
    end

    local foundStart, foundEnd = string.find(s, pattern, start, false)
    if not foundStart then
        -- no match
        return false
    end

    if foundStart == start and foundEnd == final then
        return true
    end

    return false
end

---
function assrt.assertAlmostEquals()
    assert(false, "assertAlmostEquals not implemented")
end

---
function assrt.assertEquals(a, b, message)
    assert(type(a) == type(b), message)
    if type(a) == "table" then
        assert(_is_table_equals(a, b) == true, message)
    else
        assert(a == b, message)
    end
    return a, b
end

---
function assrt.assertError(a)
    assert(false, "assertError not implemented")
end

---
function assrt.assertErrorMsgContains()
    assert(false, "assertErrorMsgContains not implemented")
end

---
function assrt.assertErrorMsgEquals()
    assert(false, "assertErrorMsgEquals not implemented")
end

---
function assrt.assertErrorMsgMatches()
    assert(false, "assertErrorMsgMatches not implemented")
end

---
function assrt.assertFalse(v, message)
    assert(not v, message)
    return v
end

---
function assrt.assertIs(a, b, message)
    assert(a == b, message)
    return a, b
end

---
function assrt.assertIsBoolean(v, message)
    assert(type(v) == "boolean", message)
    return v
end

---
function assrt.assertIsFunction(v, message)
    assert(type(v) == "function", message)
    return v
end

---
function assrt.assertIsNil(v, message)
    assert(type(v) == "nil", message)
    return v
end

---
function assrt.assertIsNumber(v, message)
    assert(type(v) == "number", message)
    return v
end

---
function assrt.assertIsString(v, message)
    assert(type(v) == "string", message)
    return v
end

---
function assrt.assertIsStringN(v, message)
    assert(type(v) == "string" and v ~= "", message)
    return v
end

---
function assrt.assertIsTable(v, message)
    assert(type(v) == "table", message)
    return v
end

---
function assrt.assertItemsEquals(a, b, message)
    assert(_is_table_equals(a, b) == true, message)
    return a, b
end

---
function assrt.assertNil(v, message)
    assert(v == nil, message)
    return v
end

---
function assrt.assertNotAlmostEquals()
    assert(false, "assertNotAlmostEquals not implemented")
end

---
function assrt.assertNotEquals(a, b, message)
    if type(a) == "table" and type(b) == "table" then
        assert(_is_table_equals(a, b) == false, message)
    else
        assert(a ~= b, message)
    end
    return a, b
end

---
function assrt.assertNotIs(a, b, message)
    assert(a ~= b, message)
    return a, b
end

---
function assrt.assertNotNil(v, message)
    assert(v ~= nil, message)
    return v
end

---
function assrt.assertNotStrContains(str, sub, regexp)
    assrt.assertIsString(str)
    assrt.assertIsString(sub)
    assert(string.find(str, sub, 1, not regexp --[[plain=true]]) == nil)
    return str
end

---
function assrt.assertNotStrIContains(str, sub)
    assrt.assertIsString(str)
    assrt.assertIsString(sub)
    assert(string.find(str:lower(), sub:lower(), 1, true) == nil)
    return str
end

---
function assrt.assertStrContains(str, sub, regexp)
    assrt.assertIsString(str)
    assrt.assertIsString(sub)
    assert(string.find(str, sub, 1, not regexp --[[plain=true]]) ~= nil)
    return str
end

---
function assrt.assertStrIContains(str, sub)
    assrt.assertIsString(str)
    assrt.assertIsString(sub)
    assert(string.find(str:lower(), sub:lower(), 1, true) ~= nil)
    return str
end

---
function assrt.assertStrMatches(s, pattern, start, final)
    assrt.assertIsString(s)
    assrt.assertIsString(pattern)
    assert(_str_match(s, pattern, start, final) == true)
    return s
end

---
function assrt.assertTrue(v, message)
    assert(v == true, message)
    return v
end

-- Add the above functions to the global environment _G
strict.unlock(_G)
for name,func in pairs(assrt) do
    -- make sure luaunit has precedence when running unit tests
    if not _G[name] then
        _G[name] = func
    end
end
strict.lock(_G)

return strict.lock(assrt)
