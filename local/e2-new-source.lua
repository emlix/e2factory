--- e2-new-source command.
-- Upload a new source to an existing server.
-- @module local.e2-new-source

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

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local generic_git = require("generic_git")
local err = require("err")
local e2option = require("e2option")
local transport = require("transport")
local cache = require("cache")
local digest = require("digest")
local url = require("url")

--- Download a file.
-- @param f string: url or path to file.
-- @return temporary filename or false.
-- @return an error object on failure.
local function download(f)
    local path = e2lib.dirname(f)
    local fn = e2lib.basename(f)

    local tfile = e2lib.mktempfile()
    local tpath = e2lib.dirname(tfile)
    local tfn = e2lib.basename(tfile)

    local rc, re = transport.fetch_file(path, fn, tpath, tfn)
    if not rc then
        return rc, re
    end

    return tfile
end

--- Attempt converting relative or absolute file path to url.
-- @param path A relative or absolute path, or url (string).
-- @return A fixed absolute path starting with file://, or the unmodified input.
local function path_to_url(path)
    -- nil is a valid argument, be very careful
    if type(path) == "string" and path:len() > 0 then
        if path:sub(1) == "/" then
            return "file://" .. path
        end

        local u = url.parse(path)
        local cwd = e2util.cwd()
        if not u and cwd then
            return "file://" .. e2lib.join(cwd, path)
        end
    end
    return path
end

--- Upload and checksum a new file source.
-- @param c table: cache
-- @param server string: e2 server
-- @param location string: location on server
-- @param source_file string: source file url
-- @param checksum_file string: checksum file url
-- @param verify True for checksum verification, otherwise false (boolean).
-- @return bool
-- @return nil, an error string on error
local function new_files_source(c, server, location, source_file, checksum_file,
    verify)
    local e = err.new("preparing new source for upload failed")
    local rc, re

    source_file = path_to_url(source_file)
    checksum_file = path_to_url(checksum_file)

    -- Collect the variables used in the following code into groups.
    local source = {}
    source.url = source_file
    source.basename = e2lib.basename(source.url)
    source.rlocation = e2lib.join(location, source.basename)
    source.rlocation_digest = source.rlocation .. ".sha1"
    source.localfn = nil
    source.localfn_digest = nil
    source.dt = nil
    source.dtentry = nil

    local checksum = {
        url = checksum_file,
        localfn = nil,
        dt = nil,
        dtentry = nil,
    }

    if not verify then
        e2lib.warn("WOTHER", "Checksum verification disabled")
    end

    -- check for file with identical name on the server
    local tmpfile = {}
    tmpfile.file = e2lib.mktempfile()
    tmpfile.base = e2lib.basename(tmpfile.file)
    tmpfile.dir = e2lib.dirname(tmpfile.file)

    rc, re = cache.fetch_file(c, server, source.rlocation,
        tmpfile.dir, tmpfile.base, {})
    if rc then
        return false, e:append("file already exists on %s:%s", server,
            source.rlocation)
    end

    -- download the source from a external server
    e2lib.logf(1, "fetching %s ...", source.url)
    local rc, re = download(source.url)
    if not rc then
        return false, e:cat(re)
    end
    source.localfn = rc

    -- compute a message digest over the downloaded source
    source.dt = digest.new()
    source.dtentry = digest.new_entry(source.dt, digest.SHA1, nil,
        source.basename, source.localfn)

    rc, re = digest.checksum(source.dt, false)
    if not rc then
        return false, e:cat(re)
    end

    -- write message digest, this one we're going to upload
    source.localfn_digest = source.localfn .. ".sha1"
    rc, re = digest.write(source.dt, source.localfn_digest)
    if not rc then
        return false, e:cat(re)
    end

    -- verify the provided checksum file
    if verify then
        e2lib.logf(1, "fetching %s ...", checksum.url)
        rc, re = download(checksum.url)
        if not rc then
            return false, e:cat(re)
        end
        checksum.localfn = rc

        checksum.dt, re = digest.parse(checksum.localfn)
        if not checksum.dt then
            return false, e:cat(re)
        end

        if digest.count(checksum.dt) ~= 1 then
            -- XXX: We could find the matching entry and shorten the digest
            return false, e:append("can not handle checksum file %s: "..
                "more than one (1) entry", checksum.url)
        end

        checksum.dtentry = checksum.dt[1]
        if checksum.dtentry.name ~= source.basename then
            return false, e:append("file name in checksum file does not match")
        end

        checksum.dtentry.name2check = source.localfn

        -- Since we verify against the same file as the source.dt above, a
        -- comparison of source.dtentry.checksum and checksum.dtentry.checksum
        -- is not necessary (and not always possible).
        rc, re = digest.verify(checksum.dt, false)
        if not rc then
            return false, e:cat(re)
        end
    end

    local flags = { writeback = true } -- !!

    -- upload checksum to cache (maybe) and server (always)
    local rc, re = cache.push_file(c, source.localfn_digest, server,
        source.rlocation_digest, flags)
    if not rc then
        return false, e:cat(re)
    end

    -- upload source file, see above.
    local rc, re = cache.push_file(c, source.localfn, server,
        source.rlocation, flags)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

local function e2_new_source(arg)
    e2lib.init()
    local info, re = e2tool.local_init(nil, "new-source")
    if not info then
        e2lib.abort(re)
    end

    e2option.flag("git", "create a git repository")
    e2option.flag("files", "create a new file on a files server")
    e2option.option("server", "specify server")
    e2option.flag("no-checksum", "do not verify checksum file")
    local opts, arguments = e2option.parse(arg)

    info, re = e2tool.collect_project_info(info)
    if not info then
        e2lib.abort(re)
    end

    if opts.git then
        if #arguments ~= 1 then
            e2lib.abort("<name> argument required")
        end
        -- remote
        local rserver = info.default_repo_server
        if opts["server"] then
            rserver = opts["server"]
        end
        local name = arguments[1]
        local rlocation = string.format("%s/git/%s.git", info.project_location, name)
        -- local
        local lserver = info.root_server_name
        local llocation = string.format("in/%s/.git", name)
        local flags = {}
        local rc, re = generic_git.new_repository(info.cache, lserver, llocation,
        rserver, rlocation, flags)
        if not rc then
            e2lib.abort(re)
        end
        e2lib.log(1, "Read e2-new-source(1) for the next step")
    elseif opts.files then
        if #arguments < 2 or #arguments > 3 then
            e2option.usage(1)
        end

        local location = arguments[1]
        local sl, e = e2lib.parse_server_location(location, info.default_files_server)
        if not sl then
            e2lib.abort(e)
        end
        local server = sl.server
        local location = sl.location
        local source_file = arguments[2]
        local checksum_file = arguments[3]
        local verify = not opts["no-checksum"]
        if verify and not checksum_file then
            e2lib.abort("checksum file argument missing")
        end

        local rc, re = new_files_source(info.cache, server, location, source_file,
        checksum_file, verify)
        if not rc then
            e2lib.abort(re)
        end
    else
        e2lib.abort(err.new("Please specify either --files are --git"))
    end

    return true
end

local rc, re = e2_new_source(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
