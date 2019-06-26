--- Error Object
-- @module generic.err

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

local err =  {}
local e2lib = require("e2lib")
local strict = require("strict")

local function assert_err(e)
    if type(e) ~= "table" then -- prevent calling debug.traceback() everytime
        assert(type(e) == "table", "No error table supplied: "..debug.traceback())
    end
    assert(type(e.count) == "number", "Error count is not a number")
    assert(type(e.msg) == "table", "Error message table of wrong type")
    if e.code ~= false then
        assertIsStringN(e.code)
    end
    return true
end

--- append a string to an error object
-- @param format string: format string
-- @param ... list of strings required for the format string
-- @return table: the error object
function err.append(e, format, ...)
    assert_err(e)
    assert(type(format) == "string")
    e.count = e.count + 1
    table.insert(e.msg, string.format(format, ...))
    return e
end

--- Insert an error object into another one.
-- @param e table: the error object
-- @param re The error object to insert OR a format string used to creating a
-- new error object.
-- @param ... list of strings required for the format string
-- @return table: the error object
function err.cat(e, re, ...)
    assert_err(e)
    assert(type(re) == "string" or assert_err(re))
    -- auto-convert strings to error objects before inserting
    if type(re) == "string" then
        if #{...} > 0 then
            re = err.new(re, ...)
        else
            re = err.new("%s", re)
        end
    end
    table.insert(e.msg, re)
    e.count = e.count + 1
    return e
end

--- Turn error objects into an error message string
-- @param e table: the error object
-- @param depth number: used internally to count and display nr. of sub errors
-- @return Error message string.
function err.tostring(e, depth)
    assert_err(e)
    assert(type(depth) == "number" or depth == nil)
    if not depth then
        depth = 1
    else
        depth = depth + 1
    end

    local msg = ""
    local prefix = string.format("Error [%d]: ", depth)
    for k,m in ipairs(e.msg) do
        if type(m) == "string" then
            msg = msg..string.format("%s%s\n", prefix, m)
            prefix = string.format("      [%d]: ", depth)
        else
            -- it's a sub error
            msg = msg..m:tostring(depth)
        end
    end

    return msg
end

--- print error messages at log level 1
-- @param e table: the error object
-- @param depth number: used internally to count and display nr. of sub errors
function err.print(e, depth)
    e2lib.log(1, e:tostring())
end

--- set the error counter
-- @param e the error object
-- @param n number: new error counter setting
-- @return nil
function err.setcount(e, n)
    assert_err(e)
    assert(type(n) == "number")
    e.count = n
end

--- get the error counter
-- @param e the error object
-- @return number: the error counter
function err.getcount(e)
    assert_err(e)
    return e.count
end

--- Private store of error codes
local _errcodes = {}

--- Register an errcode and optional data associated with it.
-- @param errcode UPPERCASE string shorthand for the error. Eg. EPERM.
-- @param data Optional miscellaneous data. Defaults to true. May not be false.
-- @raise Assertion on incorrect use.
function err.ecreg(errcode, data)
    assertIsStringN(errcode)
    assert(string.upper(errcode) == errcode)
    assert(not _errcodes[errcode])
    assert(data ~= false)

    if data == nil then
        data = true
    end

    _errcodes[errcode] = data
end

--- Set errcode on an err. The errcode must be registered first.
-- @param e Error object
-- @param errcode Errorcode string.
-- @return The err object.
-- @raise Assertion on incorrect use.
-- @see err.ecreg
function err.ecset(e, errcode)
    assert_err(e)
    assertIsStringN(errcode)
    assert(_errcodes[errcode])
    e.code = errcode
    return e
end

--- Compare errcode of an Error object with another errcode.
-- @param e Error object
-- @param errcode Errcode to com
-- @return Returns true if the errcodes are equal,
--         false if they differ (or unset).
-- @raise Assertion on incorrect use.
function err.eccmp(e, errcode)
    assert_err(e)
    assertIsStringN(errcode)
    assert(_errcodes[errcode])

    local ec = err.eccode(e)

    if ec and ec == errcode then
        return true
    end

    return false
end

--- Return the errcode, or false when there is none.
-- @param e Error object
-- @raise Assertion on incorrect use.
function err.eccode(e)
    assert_err(e)

    if not e.code then
        return false
    end

    return e.code
end

--- Get data associated with the errcode of this error, false otherwise.
-- @param e Error object.
-- @return Data associated with errcode. False when there's no errcode.
-- @raise Assertion on incorrect use.
function err.ecdata(e)
    assert_err(e)

    if not e.code then
        return false
    end

    return _errcodes[e.code]
end

local err_mt = {
    __index = err,
    __tostring = err.tostring
}

--- create an error object
-- @param format string: format string
-- @param ... list of arguments required for the format string
-- @return table: the error object
function err.new(format, ...)
    assert(type(format) == "string" or format == nil)
    local e = {}
    e.count = 0
    e.msg = {}
    e.code = false
    setmetatable(e, err_mt)
    if format then
        e:append(format, ...)
    end
    return e
end

return strict.lock(err)

-- vim:sw=4:sts=4:et:
