--- Hash module.
-- @module local.hash

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

local hash = {}
local e2lib = require("e2lib")
local eio = require("eio")
local err = require("err")
local lsha = require("lsha")
local strict = require("strict")
local trace = require("trace")

--- Create a hash context. Throws error object on failure.
-- @return Hash context object.
function hash.hash_start()
    local hc = { _data = "" }
    hc._ctx = lsha.sha1_init()
    return strict.lock(hc)
end

--- Add data to hash context. Throws error object on failure.
-- @param hc the hash context
-- @param data string: data
function hash.hash_append(hc, data)
    assert(type(hc) == "table")
    assert(type(data) == "string")
    assert(hc._data and hc._ctx)

    hc._data = hc._data .. data

    -- Consume data and update hash whenever 64KB are available
    if #hc._data >= 65536 then
        lsha.sha1_update(hc._ctx, hc._data)
        hc._data = ""
    end
end

--- Hash data with a new-line character. Throws error object on failure.
-- @param hc the hash context
-- @param data string: data to hash, a newline is appended
-- @see hash_append
function hash.hash_line(hc, data)
    hash.hash_append(hc, data .. "\n")
end

--- Get checksum and release hash context. Throws error object on failure.
-- @param hc the hash context
-- @return SHA1 Checksum.
function hash.hash_finish(hc)
    local cs

    lsha.sha1_update(hc._ctx, hc._data)
    cs = lsha.sha1_final(hc._ctx)

    -- Destroy the hash context to catch errors
    hc._data = nil
    hc._ctx = nil

    return cs
end

return strict.lock(hash)

-- vim:sw=4:sts=4:et:
