--- Hash
-- @module generic.hash

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

local hash = {}
local err = require("err")
local strict = require("strict")
require("sha1")

--- create a hash context
-- @return a hash context object, or nil on error
-- @return nil, an error string on error
function hash.hash_start()
    local hc = {}

    for k,v in pairs(hash) do
        hc[k] = v
    end

    hc.ctx = sha1.sha1_init()
    hc.data = ""
    hc.datalen = 0

    return hc
end

--- add hash data
-- @param hc the hash context
-- @param data string: data
function hash.hash_append(hc, data)
    assert(type(hc) == "table" and type(hc.ctx) == "userdata")
    assert(type(data) == "string")

    hc.data = hc.data .. data
    hc.datalen = hc.datalen + string.len(data)

    -- Consume data and update hash whenever 64KB are available
    if hc.datalen >= 64*1024 then
        hc.ctx:update(hc.data)
        hc.data = ""
        hc.datalen = 0
    end
end

--- hash a line
-- @param hc the hash context
-- @param data string: data to hash, a newline is appended
function hash.hash_line(hc, data)
    hash.hash_append(hc, data .. "\n")
end

--- hash a file
-- @param hc the hash context
-- @param path string: the full path to the file
-- @return true on success, nil on error
-- @return nil, error object on failure
function hash.hash_file(hc, path)
    assert(type(hc) == "table" and type(hc.ctx) == "userdata")
    assert(type(path) == "string")

    local fd = io.open(path, "r")
    if not fd then
        return nil, err.new("could not open file '%s'", path)
    end

    local buf = ""
    while true do
        buf = fd:read(64*1024)
        if buf == nil then
            break
        end

        hash.hash_append(hc, buf)
    end

    fd:close()

    return true
end

--- add hash data
-- @param hc the hash context
-- @return the hash value, or nil on error
-- @return an error string on error
function hash.hash_finish(hc)
    assert(type(hc) == "table" and type(hc.ctx) == "userdata")

    hc.ctx:update(hc.data)

    local cs = string.lower(hc.ctx:final())
    assert(string.len(cs) == 40)

    -- Destroy the hash context to catch errors
    for k,_ in pairs(hc) do
        hc[k] = nil
    end

    return cs
end

return strict.lock(hash)

-- vim:sw=4:sts=4:et:
