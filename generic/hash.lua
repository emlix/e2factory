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

--- create a hash context
-- @return a hash context object, or nil on error
-- @return nil, an error string on error
local function hash_start()
	local hc = {}
	for k,v in pairs(hash) do
		hc[k] = v
	end
	hc.data = ""
	return hc
end

--- add hash data
-- @param hc the hash context
-- @param data string: data
local function hash_append(hc, data)
	-- append the data
	hc.data = hc.data .. data
end

local function hash_line(hc, data)
	hash_append(hc, data .. "\n")
end

--- add hash data
-- @param hc the hash context
-- @return the hash value, or nil on error
-- @return an error string on error
local function hash_finish(hc)
	-- write hash data to a temporary file
	hc.tmpdir = e2lib.mktempdir()
	hc.tmpfile = string.format("%s/hashdata", hc.tmpdir)
	hc.f = io.open(hc.tmpfile, "w")
	hc.f:write(hc.data)
	hc.f:close()

	-- hash data and read the hash value
	local cmd = string.format("sha1sum %s", hc.tmpfile)
	hc.p = io.popen(cmd, "r")
	local s = hc.p:read()
	if not s then
		return nil, "calculating hash value failed"
	end
	hc.p:close()

	-- parse the output from sha1sum
	hc.sha1 = s:match("(%S+)")
	if not hc.sha1 then
		return nil, "calculating hash value failed"
	end
	e2lib.rmtempdir(hc.tmpdir)
	return hc.sha1
end

hash = {}
hash.hash_start = hash_start
hash.hash = hash_append
hash.hash_line = hash_line
hash.hash_finish = hash_finish
