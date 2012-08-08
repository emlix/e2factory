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

local err =  {}

--- append a string to an error object
-- @param format string: format string
-- @param ... list of strings required for the format string
-- @return table: the error object
function err.append(e, format, ...)
    e.count = e.count + 1
    table.insert(e.msg, string.format(format, ...))
    return e
end

--- insert an error object into another one
-- @param e table: the error object
-- @param re table: the error object to insert
-- @return table: the error object
function err.cat(e, re)
    -- auto-convert strings to error objects before inserting
    if type(re) == "string" then
        re = err.new("%s", re)
    end
    table.insert(e.msg, re)
    e.count = e.count + 1
    return e
end

--- print error messages at log level 1
-- @param e table: the error object
-- @param depth number: used internally to count and display nr. of sub errors
function err.print(e, depth)
    if not depth then
        depth = 1
    else
        depth = depth + 1
    end

    local prefix = string.format("Error [%d]: ", depth)

    for k,m in ipairs(e.msg) do
        if type(m) == "string" then
            e2lib.log(1, string.format("%s%s", prefix, m))
            prefix = string.format("      [%d]: ", depth)
        else
            -- it's a sub error
            m:print(depth)
        end
    end
end

--- set the error counter
-- @param e the error object
-- @param n number: new error counter setting
-- @return nil
function err.setcount(e, n)
    e.count = n
end

--- get the error counter
-- @param e the error object
-- @return number: the error counter
function err.getcount(e, n)
    return e.count
end

--- create an error object
-- @param format string: format string
-- @param ... list of arguments required for the format string
-- @return table: the error object
function err.new(format, ...)
    local e = {}
    e.count = 0
    e.msg = {}
    local meta = { __index = err }
    setmetatable(e, meta)
    if format then
        e:append(format, ...)
    end
    return e
end

function err.toerror(x)
    if type(x) == "table" then
        return x
    else
        return err.new(x)
    end
end

return err

-- vim:sw=4:sts=4:et:
