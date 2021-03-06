--- e2-new-source command.
-- Upload a new source to an existing server.
-- @module local.e2-new-source

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

local cache = require("cache")
local digest = require("digest")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local err = require("err")
local generic_git = require("generic_git")
local policy = require("policy")
local transport = require("transport")
local url = require("url")

--- Download a file.
-- @param f string: url or path to file.
-- @return temporary filename or false.
-- @return an error object on failure.
local function download(f)
    local rc, re
    local path = e2lib.dirname(f)
    local fn = e2lib.basename(f)

    local tfile, re = e2lib.mktempfile()
    if not tfile then
        return false, re
    end

    local tpath = e2lib.dirname(tfile)
    local tfn = e2lib.basename(tfile)

    rc, re = transport.fetch_file(path, fn, tpath, tfn)
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
        local cwd = e2lib.cwd()
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
    source.rlocation_sha1 = source.rlocation .. ".sha1"
    -- source.rlocation_sha256 = source.rlocation .. ".sha256"
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
    tmpfile.file, re = e2lib.mktempfile()
    if not tmpfile.file then
        return false, e:cat(re)
    end
    tmpfile.base = e2lib.basename(tmpfile.file)
    tmpfile.dir = e2lib.dirname(tmpfile.file)

    -- check that file and digest(s) are neither in cache nor on server
    local tocheck = {
        source.rlocation_sha1,
        -- source.rlocation_sha256,
        source.rlocation
    }
    for _, fileloc in ipairs(tocheck) do
        local cf = nil
        local msg = "if necessary, move file out of the way manually"
        rc, re, cf = cache.file_in_cache(c, server, fileloc, nil)
        if rc then
            return false, e:append(
                "file or digest already in cache (%s): %s", msg, cf)
        end

        rc, re = cache.fetch_file(c, server, fileloc, tmpfile.dir, tmpfile.base,
            { cache=false })
        if rc then
            return false, e:append(
                "file or digest already on server (%s): %s:%s",
                msg, server, fileloc)
        end
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

    -- print checksum
    if source.dtentry.digest == digest.SHA1 then
        assert(#source.dtentry.checksum == 40)
        e2lib.logf(1, "sha1 = \"%s\"", source.dtentry.checksum)
    end

    if not cache.writeback_enabled(c, server) then
        e2lib.warnf("WOTHER", "enabling writeback for server: %s",
            server)
        rc, re = cache.set_writeback(c, server, true)
        if not rc then
            return false, e:cat(re)
        end
    end

    -- upload checksum to cache (maybe) and server (always)
    local rc, re = cache.push_file(c, source.localfn_digest, server,
        source.rlocation_sha1)
    if not rc then
        return false, e:cat(re)
    end

    -- upload source file, see above.
    local rc, re = cache.push_file(c, source.localfn, server,
        source.rlocation)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

local function e2_new_source(arg)
    local e2project
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    e2option.flag("git", "create a git repository")
    e2option.flag("files", "create a new file on a files server")
    e2option.option("server", "specify server")
    e2option.flag("no-checksum", "do not verify checksum file")
    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    -- setup default build mode
    rc, re = policy.handle_commandline_options(opts, true)
    if not rc then
        error(re)
    end

    e2project = e2tool.e2project()
    e2project:init_project("new-source")

    rc, re = e2project:load_project()
    if not rc then
        error(re)
    end

    if opts.git then
        if #arguments ~= 1 then
            error(err.new("<name> argument required"))
        end
        -- remote
        local rserver = cache.server_names().projects
        if opts["server"] then
            rserver = opts["server"]
        end
        local name = arguments[1]
        local rlocation = string.format("%s/git/%s.git",
            e2project:project_location(), name)
        -- local
        local lserver = cache.server_names().dot
        local llocation = string.format("in/%s/.git", name)
        local rc, re = generic_git.new_repository(cache.cache(), lserver, llocation,
            rserver, rlocation)
        if not rc then
            error(re)
        end
        e2lib.log(1, "Read e2-new-source(1) for the next step")
    elseif opts.files then
        if #arguments < 2 or #arguments > 3 then
            e2option.usage(1)
        end

        local location = arguments[1]
        local sl, re = e2lib.parse_server_location(location,
            cache.server_names().upstream)
        if not sl then
            error(re)
        end
        local server = sl.server
        local location = sl.location
        local source_file = arguments[2]
        local checksum_file = arguments[3]
        local verify = not opts["no-checksum"]
        if verify and not checksum_file then
            error(err.new("checksum file argument missing"))
        end

        local rc, re = new_files_source(cache.cache(), server, location, source_file,
        checksum_file, verify)
        if not rc then
            error(re)
        end
    else
        error(err.new("Please specify either --files are --git"))
    end
end

local pc, re = e2lib.trycall(e2_new_source, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
