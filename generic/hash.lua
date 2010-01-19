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

module("hash", package.seeall)
require("sha1")

--- create a hash context
-- @return a hash context object, or nil on error
-- @return nil, an error string on error
function hash_start()
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
function hash_append(hc, data)
	-- append the data
	hc.data = hc.data .. data
end

function hash_line(hc, data)
	hash_append(hc, data .. "\n")
end

--- add hash data
-- @param hc the hash context
-- @return the hash value, or nil on error
-- @return an error string on error
function hash_finish(hc)
	local ctx = sha1.sha1_init()
	ctx:update(hc.data)
	hc.sha1 = string.lower(ctx:final())
	return hc.sha1
end
