--- Checksum caching module.
-- @module local.cscache

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

local cscache

local class = require("class")
local digest -- initialized later
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")


--- Checksum cache class.
-- @type cs_cache_class
local cs_cache_class = class("cs_cache_class")

function cs_cache_class:initialize()
    self._csdict = nil
    self._projectroot = nil
    self._csfile = ".e2/hashcache"
end

--- Return checksum of specified type for filename, or false.
-- @param filename Absolute path to file.
-- @param digest_type Digest type
-- @see local.digest
-- @return Checksum or false if not match.
function cs_cache_class:lookup(filename, digest_type)
    assertIsStringN(filename)
    assert(digest_type == digest.SHA1 or digest_type == digest.SHA256)

    local hce, cs, sb

    if not self._csdict then
        self:load_cache()
        assert(self._csdict)
    end

    if not self._csdict[filename] then
        return false
    end


    hce = self._csdict[filename]
    assert(hce)

    if digest_type == digest.SHA1 and hce.sha1 then
        cs = hce.sha1
    elseif digest_type == digest.SHA256 and hce.sha256 then
        cs = hce.sha256
    end

    if not cs then
        return false
    end

    -- Try not to return checksums for files which are inaccessible.
    if not e2lib.exists(filename, false) then
        self._csdict[filename] = nil
        return false
    end

    sb = e2lib.stat(filename)
    if not sb then
        self._csdict[filename] = nil
        return false
    end

    if hce.mtime ~= sb.mtime
        or hce.mtime_nsec ~= sb.mtime_nsec
        or hce.ctime ~= sb.ctime
        or hce.ctime_nsec ~= sb.ctime_nsec
        or hce.size ~= sb.size
        or hce.dev ~= sb.dev
        or hce.ino ~= sb.ino then

        self._csdict[filename] = nil
        return false
    end

    hce.use = os.time()

    return cs
end

--- Insert checksum for filename.
-- @param filename Absolute path to file.
-- @param checksum Checksum string.
-- @param digest_type Digest type.
-- @see local.digest
function cs_cache_class:insert(filename, checksum, digest_type)
    assertIsStringN(filename)
    assert(filename:sub(1,1) == "/")
    assertIsStringN(checksum)
    assert(digest_type == digest.SHA1 or digest_type == digest.SHA256)

    local sb, hce, sha1, sha256

    if not checksum or type(checksum) ~= "string" then
        return
    end

    if not self._csdict then
        self:load_cache()
        assert(self._csdict)
    end

    if digest_type == digest.SHA1 then
        assert(#checksum == digest.SHA1_LEN)
        sha1 = checksum
        sha256 = self:lookup(filename, digest.SHA256)
    elseif digest_type == digest.SHA256 then
        assert(#checksum == digest.SHA256_LEN)
        sha1 = self:lookup(filename, digest.SHA1)
        sha256 = checksum
    end

    if not e2lib.exists(filename, false) then
        return
    end

    sb = e2lib.stat(filename)
    if not sb then
        return
    end

    assert(sha1 or sha256)

    self._csdict[filename] = {
        sha1 = sha1 or nil,
        sha256 = sha256 or nil,
        mtime = sb.mtime,
        mtime_nsec = sb.mtime_nsec,
        ctime = sb.ctime,
        ctime_nsec = sb.ctime_nsec,
        size = sb.size,
        dev = sb.dev,
        ino = sb.ino,
        use = 0,
    }
end

--- Load cache from hashcache file if availble.
-- Done automatically on the first lookup or insert.
-- Also installs a cleanup callback to store_cache().
-- Does not populate the cache in release mode.
function cs_cache_class:load_cache()
    local chunk, msg, hctab

    self._csdict = {}

    if e2option.opts["build-mode"] == "release" then
        return
    end

    if not self._projectroot then
        local info

        info = e2tool.info()
        if not info then
            return
        else
            self._projectroot = info.root
        end
    end

    e2lib.register_cleanup("cs_cache_class:store_cache",
        cs_cache_class.store_cache, self)

    chunk, msg = loadfile(e2lib.join(self._projectroot, self._csfile))
    if not chunk then
        e2lib.logf(3, "could not load cs_cache: %s", msg)
        return
    end

    -- set empty environment for this chunk
    setfenv(chunk, {})
    hctab = chunk()
    if type(hctab) ~= "table" then
        e2lib.logf(3, "ignoring malformed cs_cache")
        return
    end

    for path,hce in pairs(hctab) do
        if type(path) == "string" and #path > 0
            and type(hce.mtime) == "number"
            and type(hce.mtime_nsec) == "number"
            and type(hce.ctime) == "number"
            and type(hce.ctime_nsec) == "number"
            and type(hce.size) == "number"
            and type(hce.dev) == "number"
            and type(hce.ino) == "number"
            and type(hce.use) == "number"
            then

            if type(hce.sha1) ~= "string" or #hce.sha1 ~= digest.SHA1_LEN then
                hce.sha1 = nil
            end

            if type(hce.sha256) ~= "string" or #hce.sha256 ~= digest.SHA256_LEN then
                hce.sha256 = nil
            end


            if hce.sha1 or hce.sha256 then
                self._csdict[path] = {
                    sha1 = hce.sha1,
                    sha256 = hce.sha256,
                    mtime = hce.mtime,
                    mtime_nsec = hce.mtime_nsec,
                    ctime = hce.ctime,
                    ctime_nsec = hce.ctime_nsec,
                    size = hce.size,
                    dev = hce.dev,
                    ino = hce.ino,
                    use = hce.use,
                }
            end
        end
    end
end

--- Store the checksum cache to disk.
-- Called by cleanup handler.
function cs_cache_class:store_cache()
    local hcachevec, out

    if not self._csdict or not self._projectroot then
        return
    end

    hcachevec = {}
    for path,hce in pairs(self._csdict) do
        if not path:find("/e2tmp.", 1, true) then -- weed out temp files
            table.insert(hcachevec, {path=path, hce=hce})
        end
    end

    local function comp(t1, t2)
        if t1.hce.use > t2.hce.use then
            return true
        end
        return false
    end

    table.sort(hcachevec, comp)

    out = { "return {\n" }
    for i,v in ipairs(hcachevec) do
        table.insert(out,
            string.format(
            "[%q] = { sha1=%q, sha256=%q, mtime=%d, mtime_nsec=%d, ctime=%d, " ..
            "ctime_nsec=%d, size=%d, dev=%d, ino=%d, use=%d },\n",
            v.path, v.hce.sha1 or "", v.hce.sha256 or "", v.hce.mtime,
            v.hce.mtime_nsec, v.hce.ctime, v.hce.ctime_nsec, v.hce.size,
            v.hce.dev, v.hce.ino, v.hce.use))

            if i > 1000 then
                break
            end
    end
    table.insert(out, "}\n")

    eio.file_write(e2lib.join(self._projectroot, self._csfile), table.concat(out))
end

if not cscache then
    cscache = cs_cache_class:new()
    digest = require("digest")
end

return cscache
