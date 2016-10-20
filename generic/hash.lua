--- Hash module with built-in caching.
-- @module generic.hash

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
local lsha1 = require("lsha1")
local strict = require("strict")
local trace = require("trace")

--- The hashcache lookup dictionary.
local hcachedict = false
--- Path to the persistent storage file.
local hcachestorage = false

--- Internal hash cache entry dictionary.
-- @table hce
-- @field dev See stat.
-- @field ino See stat.
-- @field size See stat.
-- @field mtime See stat.
-- @field mtime_nsec See stat.
-- @field ctime See stat.
-- @field ctime_nsec See stat.
-- @field hash SHA-1 checksum
-- @field hit Count cache hits.

--- Load or create the persistent hashcache file.
-- @param filename Path to hashcache file. If filename does not exists, it
--                 will be created when calling hcache_store().
-- @return True on success, false on error. Errors only have an effect on
--         performance, and should ususally be ignored.
-- @return Error object on failure.
-- @see hcache_store
function hash.hcache_load(filename)
    local rc, re, hctab, chunk, msg

    if hcachedict then
        return false, err.new("hashcache already initialised")
    end

    hcachestorage = filename

    hctab = {}
    chunk, msg = loadfile(filename)
    if not chunk then
        return false, err.new("loading hashcache %q failed: %s", filename, msg)
    end

    -- set empty environment for this chunk
    setfenv(chunk, {})
    hctab = chunk()
    if type(hctab) ~= "table" then
        return false, err.new("ignoring malformed hashcache %q", filename)
    end

    for path,hce in pairs(hctab) do
        if type(path) == "string" and #path > 0
            and type(hce.hash) == "string" and #hce.hash == 40
            and type(hce.mtime) == "number"
            and type(hce.mtime_nsec) == "number"
            and type(hce.ctime) == "number"
            and type(hce.ctime_nsec) == "number"
            and type(hce.size) == "number"
            and type(hce.dev) == "number"
            and type(hce.ino) == "number"
            and type(hce.hit) == "number" then

            if not hcachedict then
                hcachedict = {}
            end

            hcachedict[path] = {
                hash = hce.hash,
                mtime = hce.mtime,
                mtime_nsec = hce.mtime_nsec,
                ctime = hce.ctime,
                ctime_nsec = hce.ctime_nsec,
                size = hce.size,
                dev = hce.dev,
                ino = hce.ino,
                hit = hce.hit,
            }
        else
            hcachedict = false
            return false,
                err.new("malformed hashcache entry, ignoring %q", filename)
        end
    end

    return true
end

--- Save the hashcache to persistent storage, for later use. The hashcache file
-- location set by calling hcache_load().
-- @return True on success, false on error. Errors should usually be ignored.
-- @return Error object on failure.
-- @see hcache_load
function hash.hcache_store()
    local rc, re, hcachevec, e, out

    if not hcachedict or not hcachestorage then
        return true
    end

    hcachevec = {}
    for path,hce in pairs(hcachedict) do
        table.insert(hcachevec, {path=path, hce=hce})
    end

    local function comp(t1, t2)
        if t1.hce.hit > t2.hce.hit then
            return true
        end
        return false
    end

    table.sort(hcachevec, comp)

    out = { "return {\n" }
    for i,v in ipairs(hcachevec) do
        table.insert(out,
            string.format(
            "[%q] = { hash=%q, mtime=%d, mtime_nsec=%d, ctime=%d, " ..
            "ctime_nsec=%d, size=%d, dev=%d, ino=%d, hit=%d },\n",
            v.path, v.hce.hash, v.hce.mtime, v.hce.mtime_nsec, v.hce.ctime,
            v.hce.ctime_nsec, v.hce.size, v.hce.dev, v.hce.ino, v.hce.hit))

            if v.hce.hit == 0 and i > 10000 then
                break
            end
    end
    table.insert(out, "}\n")

    rc, re = eio.file_write(hcachestorage, table.concat(out))
    if not rc then
        e = err.new("writing hashcache file")
        return false, e:cat(re)
    end

    return true
end

--- Create a hash context. Throws error object on failure.
-- @return Hash context object.
function hash.hash_start()
    local errstring, hc
    hc = { _data = "" }

    hc._ctx, errstring = lsha1.init()
    if not hc._ctx then
        error(err.new("initializing SHA1 context failed: %s", errstring))
    end

    return strict.lock(hc)
end

--- Add data to hash context. Throws error object on failure.
-- @param hc the hash context
-- @param data string: data
function hash.hash_append(hc, data)
    assert(type(hc) == "table")
    assert(type(data) == "string")
    assert(hc._data and hc._ctx)
    local rc, errstring

    hc._data = hc._data .. data

    -- Consume data and update hash whenever 64KB are available
    if #hc._data >= 64*1024 then
        rc, errstring = lsha1.update(hc._ctx, hc._data)
        if not rc then
            error(err.new("%s", errstring))
        end
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

--- Hash a file.
-- @param hc the hash context
-- @param path string: the full path to the file
-- @return True on success, false on error.
-- @return Error object on failure.
function hash.hash_file(hc, path)

    local function _hash_file(hc, f)
        local rc, re, buf

        while true do
            buf, re = eio.fread(f, 64*1024)
            if not buf then
                return false, re
            elseif buf == "" then
                break
            end

            hash.hash_append(hc, buf)
        end

        return true
    end

    local f, rc, re, ok

    f, re = eio.fopen(path, "r")
    if not f then
        return false, re
    end

    trace.disable()
    ok, rc, re = e2lib.trycall(_hash_file, hc, f)
    trace.enable()

    if not ok then
        -- rc contains error object/message
        re = rc
        rc = false
    end

    if not rc then
        eio.fclose(f)
        return false, re
    end

    rc, re = eio.fclose(f)
    if not rc then
        return false, re
    end
    return true
end

--- Lookup the checksum for a file in the hashcache.
-- @param path Absolute path to the file.
-- @return Checksum or false if path is not in the cache or an error occured.
local function hcache_lookup(path)
    local sb, hce

    if not hcachedict then
        return false
    end

    -- Try not to return checksums for files which are inaccessible.
    if not e2lib.exists(path, false) then
        return false
    end

    sb = e2lib.stat(path)
    if not sb then
        return false
    end

    hce = hcachedict[path]
    if not hce
        or hce.mtime ~= sb.mtime
        or hce.mtime_nsec ~= sb.mtime_nsec
        or hce.ctime ~= sb.ctime
        or hce.ctime_nsec ~= sb.ctime_nsec
        or hce.size ~= sb.size
        or hce.dev ~= sb.dev
        or hce.ino ~= sb.ino then

        return false
    end

    hce.hit = hce.hit + 1
    return hce.hash
end

--- Add file and checksum to the hashcache.
-- @param path Path to the file.
-- @param hash SHA1 checksum string, length 40.
-- @return True on success, false on error.
local function hcache_add(path, hash)
    assert(type(path) == "string" and #path > 0)
    assert(type(hash) == "string" and #hash == 40)

    local sb

    if not hcachedict then
        hcachedict = {}
    end

    sb = e2lib.stat(path)
    if not sb then
        return false
    end

    hcachedict[path] = {
        hash = hash,
        mtime = sb.mtime,
        mtime_nsec = sb.mtime_nsec,
        ctime = sb.ctime,
        ctime_nsec = sb.ctime_nsec,
        size = sb.size,
        dev = sb.dev,
        ino = sb.ino,
        hit = 0,
    }

    return true
end

--- Hash a file at once. Unlike hash_file(), this function makes use of a
-- persistent cache.
-- @param path Full path to the file.
-- @return Checksum string, or false on error.
-- @return Error object on failure.
-- @see hcache_load
function hash.hash_file_once(path)
    local rc, re, hc, cs

    cs = hcache_lookup(path)
    if cs then
        return cs
    end

    hc = hash.hash_start()

    rc, re = hash.hash_file(hc, path)
    if not rc then
        hash.hash_finish(hc)
        return false, re
    end

    cs, re = hash.hash_finish(hc)
    if not cs then
        return false, re
    end

    hcache_add(path, cs)
    return cs
end

--- Get checksum and release hash context. Throws error object on failure.
-- @param hc the hash context
-- @return SHA1 Checksum.
function hash.hash_finish(hc)
    local rc, errstring, cs

    rc, errstring = lsha1.update(hc._ctx, hc._data)
    if not rc then
        error(err.new("%s", errstring))
    end

    cs, errstring = lsha1.final(hc._ctx)
    if not cs then
        error(err.new("%s", errstring))
    end

    -- Destroy the hash context to catch errors
    for k,_ in pairs(hc) do
        hc[k] = nil
    end

    return cs
end

return strict.lock(hash)

-- vim:sw=4:sts=4:et:
