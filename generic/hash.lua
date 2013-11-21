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
local eio = require("eio")
local err = require("err")
local strict = require("strict")
local trace = require("trace")
local lsha1 = require("lsha1")

--- Create a hash context.
-- @return Hash context object or false on error.
-- @return Error object on failure.
function hash.hash_start()
    local errstring, hc
    hc = {}

    hc._ctx, errstring = lsha1.init()
    if not hc._ctx then
        return false, err.new("initializing SHA1 context failed: %s", errstring)
    end
    hc._data = ""

    return strict.lock(hc)
end

--- Add data to hash context.
-- @param hc the hash context
-- @param data string: data
-- @return True on success, false on error.
-- @return Error object on failure.
function hash.hash_append(hc, data)
    local rc, errstring

    hc._data = hc._data .. data

    -- Consume data and update hash whenever 64KB are available
    if #hc._data >= 64*1024 then
        rc, errstring = lsha1.update(hc._ctx, hc._data)
        if not rc then
            return false, err.new("%s", re)
        end
        hc._data = ""
    end

    return true
end

--- Hash a line.
-- @param hc the hash context
-- @param data string: data to hash, a newline is appended
-- @return True on success, false on error.
-- @return Error object on failure.
-- @see hash_append
function hash.hash_line(hc, data)
    return hash.hash_append(hc, data .. "\n")
end

--- Hash a file.
-- @param hc the hash context
-- @param path string: the full path to the file
-- @return True on success, false on error.
-- @return Error object on failure.
function hash.hash_file(hc, path)
    local f, rc, re, buf

    f, re = eio.fopen(path, "r")
    if not f then
        return false, re
    end

    trace.disable()

    while true do
        buf, re = eio.fread(f, 64*1024)
        if not buf then
            trace.enable()
            eio.fclose(f)
            return false, re
        elseif buf == "" then
            break
        end

        rc, re = hash.hash_append(hc, buf)
        if not rc then
            trace.enable()
            eio.fclose(f)
            return false, re
        end
    end

    trace.enable()

    rc, re = eio.fclose(f)
    if not rc then
        return false, re
    end

    return true
end

--- Get checksum and release hash context.
-- @param hc the hash context
-- @return SHA1 Checksum, or false on error.
-- @return Error object on failure.
function hash.hash_finish(hc)
    local rc, errstring, cs

    rc, errstring = lsha1.update(hc._ctx, hc._data)
    if not rc then
        return false, err.new("%s", errstring)
    end

    cs, errstring = lsha1.final(hc._ctx)
    if not cs then
        return false, err.new("%s", errstring)
    end

    -- Destroy the hash context to catch errors
    for k,_ in pairs(hc) do
        hc[k] = nil
    end

    return cs
end

return strict.lock(hash)

-- vim:sw=4:sts=4:et:
