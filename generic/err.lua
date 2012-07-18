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


module("err", package.seeall)

--- append a string to an error object
-- @param format string: format string
-- @param ... list of strings required for the format string
-- @return table: the error object
function append(e, format, ...)
	e.count = e.count + 1
	table.insert(e.msg, string.format(format, ...))
	return e
end

--- insert an error object into another one
-- @param e table: the error object
-- @param re table: the error object to insert
-- @return table: the error object
function cat(e, re)
	-- auto-convert strings to error objects before inserting
	if type(re) == "string" then
		re = new_error("%s", re)
	end
	table.insert(e.msg, re)
	e.count = e.count + 1
	return e
end

function print(e, depth)
	if not depth then
		depth = 1
	else
		depth = depth + 1
	end
	local prefix = string.format("Error [%d]: ", depth)
	for _,m in ipairs(e.msg) do
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
function setcount(e, n)
	e.count = n
end

--- get the error counter
-- @param e the error object
-- @return number: the error counter
function getcount(e, n)
	return e.count
end

--- create an error object
-- @param format string: format string
-- @param ... list of arguments required for the format string
-- @return table: the error object
function new_error(format, ...)
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

function toerror(x)
	if type(x) == "table" then
		return x
	else
		return new_error(x)
	end
end

_G.new_error = new_error
