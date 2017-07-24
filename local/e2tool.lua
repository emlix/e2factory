--- Core e2factory data structure and functions around the build process.
-- @module local.e2tool

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

local e2tool = {}
package.loaded["e2tool"] = e2tool

local buildconfig = require("buildconfig")
local cache = require("cache")
local chroot = require("chroot")
local class = require("class")
local digest = require("digest")
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2option = require("e2option")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local generic_git = require("generic_git")
local hash = require("hash")
local licence = require("licence")
local plugin = require("plugin")
local policy = require("policy")
local project = require("project")
local projenv = require("projenv")
local result = require("result")
local sl = require("sl")
local source = require("source")
local strict = require("strict")
local tools = require("tools")
local url = require("url")

--- @type file_class
e2tool.file_class = class("file_class")

--- File_class constructor.
-- A file_class represents a single file entry in various e2 config files.
-- Server name and location are optional and don't get validated.
-- Attributes are not universal. Most error checking is thus left to other
-- layers, except for some basic assert statements.
-- @param server Server name as known to cache, optional
-- @param location Path to file relative to server, optional
function e2tool.file_class:initialize(server, location)
    self._server = nil
    self._location = nil
    self._sha1 = nil
    self._sha256 = nil
    self._licences = nil
    self._unpack = nil
    self._copy = nil
    self._patch = nil

    self:server(server)
    self:location(location)
end

--- Create a new instance.
-- Note that the licences sl is NOT copied.
-- @return object copy
-- @see sl.sl
function e2tool.file_class:instance_copy()
    local c = e2tool.file_class:new(self._server, self._location)
    c:sha1(self._sha1)
    c:sha256(self._sha256)
    c:licences(self._licences) -- stringlist, doesn't create a copy
    c:unpack(self._unpack)
    c:copy(self._copy)
    c:patch(self._patch)
    return c
end

--- Turn a file object into a table.
-- File entry like in e2source, chroot, etc.
-- @return file table
function e2tool.file_class:to_config_table()
    local t = {}

    t.server = self._server
    t.location = self._location

    if self._sha1 then
        t.sha1 = self._sha1
    end
    if self._sha256 then
        t.sha256 = self._sha256
    end
    if self._licences then
        t.licences = self._licences:totable()
    end
    if self._unpack then
        t.unpack = self._unpack
    elseif self._copy then
        t.copy = self._copy
    elseif self._patch then
        t.patch = self._patch
    end

    return t
end

--- Formatted server:location string.
-- @return server:location string
function e2tool.file_class:servloc()
    return self._server .. ":" .. self._location
end

--- Validate and set server and location attributes.
-- @param server Valid server name (validated against cache)
-- @param location Path to file on the server
-- @return True on success, false on validation failure
-- @return Error object on failure
function e2tool.file_class:validate_set_servloc(server, location)
    if server == nil then
        return false, err.new("file entry without 'server' attribute")
    end

    if type(server) ~= "string" then
        return false, err.new("invalid 'server' type: %", type(server))
    end

    if server == "" then
        return false, err.new("'server' can't be empty")
    end

    if not cache.valid_server(cache.cache(), server) then
        return false, err.new("file entry with unknown server: %s", server)
    end

    if location == nil then
        return false, err.new("file entry without 'location' attribute")
    end

    if type(location) ~= "string" then
        return false, err.new("invalid 'location' type: %", type(server))
    end

    if location == "" then
        return false, err.new("'location' can't be empty")
    end

    self:server(server)
    self:location(location)

    return true
end

--- Validate the cs values and set the file checksum if available.
-- Note this function does <b>not verify</b> any checksum.
-- It enforces only format and checksum policy.
-- @param sha1 Optional SHA1 checksum.
-- @param sha256 Optional SHA256 checksum.
-- @return True on success, false on error
-- @return Error object on failure.
function e2tool.file_class:validate_set_checksums(sha1, sha256)
    local s

    if sha1 ~= nil then
        if type(sha1) ~= "string" then
            return false, err.new("sha1 must be a string")
        end

        if #sha1 ~= digest.SHA1_LEN then
            return false, err.new("sha1 should be %d characters long",
                digest.SHA1_LEN)
        end

        local s, e = sha1:find("[a-f0-9]*")
        if s ~= 1 or e ~= digest.SHA1_LEN then
            return false, err.new("sha1 should be lowercase hexadecimal")
        end
    end

    if sha256 ~= nil then
        if type(sha256) ~= "string" then
            return false, err.new("sha256 must be a string")
        end

        if #sha256 ~= digest.SHA256_LEN then
            return false, err.new("sha256 should be %d characters long",
                digest.SHA256_LEN)
        end

        local s, e = sha256:find("[a-f0-9]*")
        if s ~= 1 or e ~= digest.SHA256_LEN then
            return false, err.new("sha256 should be in lowercase hexadecimal")
        end
    end

    if self._server ~= cache.server_names().dot then
        if not sha1 and not sha256 then
            return false,
                err.new("checksum is required for the %s file entry", self:servloc())
        end

        if project.checksums_sha1() and not sha1 then
            return false, err.new("sha1 attribute is missing for %s", self:servloc())
        end

        if project.checksums_sha256() and not sha256 then
            return false, err.new("sha256 attribute is missing for %s", self:servloc())
        end
    end

    if sha1 then
        self:sha1(sha1)
    end
    if sha256 then
        self:sha256(sha256)
    end

    return true
end

--- Compute checksum of file by retreiving it via the cache transport,
-- and hashing local.
-- @param digest_type CS of this digest type
-- @param flags cache flags
-- @return Requested checksum on success, false if an error occured.
-- @return error object on failure.
function e2tool.file_class:_compute_checksum(digest_type, flags)
    assert(digest_type == digest.SHA1 or digest_type == digest.SHA256)
    local rc, re, path, dt

    path, re = cache.fetch_file_path(cache.cache(), self._server, self._location,
        flags)
    if not path then
        return false, re
    end

    dt = digest.new()
    digest.new_entry(dt, digest_type, nil--[[checksum]], nil--[[name]], path)
    rc, re = digest.checksum(dt, false)
    if not rc then
        return false, re
    end

    if digest_type == digest.SHA1 then
        digest.assertSha1(dt[1].checksum)
    else
        digest.assertSha256(dt[1].checksum)
    end

    return dt[1].checksum
end

--- Compute checksum of file on the remote server, if transport supports it.
-- @param digest_type Digest type
-- @return  Checksum on success - false if not possible or on failure
-- @return error object on failure.
function e2tool.file_class:_compute_remote_checksum(digest_type)
    assert(digest_type == digest.SHA1 or digest_type == digest.SHA256)
    local rc, re, surl, u, checksum

    surl, re = cache.remote_url(cache.cache(), self._server, self._location)
    if not surl then
        return false, re
    end

    u, re = url.parse(surl)
    if not u then
        return false, re
    end

    if u.transport == "ssh" or u.transport == "scp" or
        u.transport == "rsync+ssh" then
        local argv, stdout, dt, cmd, s, e

        if digest_type == digest.SHA1 then
            cmd =  { "sha1sum", e2lib.join("/", u.path) }
        else
            cmd =  { "sha256sum", e2lib.join("/", u.path) }
        end
        rc, re, stdout = e2lib.ssh_remote_cmd(u, cmd)
        if not rc then
            return false, re
        end

        dt, re = digest.parsestring(stdout)
        if not dt then
            return false, re
        end

        for _,dt_entry in ipairs(dt) do
            if dt_entry.name == e2lib.join("/", u.path) then
                checksum = dt_entry.checksum
                break;
            end
        end

        if not checksum then
            return false,
                err.new("could not extract %s checksum from remote output",
                    digest.type_to_string(digest_type))
        end

        s, e = checksum:find("[a-f0-9]*")
        if digest_type == digest.SHA1 then
            if not (s == 1 and e == digest.SHA1_LEN) then
                return false,
                    err.new("don't recognize SHA1 checksum from remote output")
            end
        else
            if not (s == 1 and e == digest.SHA256_LEN) then
                return false,
                    err.new("don't recognize SHA256 checksum from remote output")
            end
        end

        return checksum
    end

    return false
end

--- Calculate the FileID for a file.
-- This includes the checksum of the file as well as all set attributes.
-- @return FileID string: hash value, or false on error.
-- @return an error object on failure
function e2tool.file_class:fileid()
    local rc, re, e, hc, cs, fid
    local cs_done = false

    e = err.new("error calculating file id for file: %s", self:servloc())

    hc = hash.hash_start()
    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._location)

    if self:sha1() or project.checksums_sha1() then
        if self:sha1() then
            hash.hash_append(hc, self:sha1())
        else
            cs, re = self:_compute_checksum(digest.SHA1)
            if not cs then
                return false, e:cat(re)
            end
            hash.hash_append(hc, cs)
        end
        cs_done = true
    end

    if self:sha256() or project.checksums_sha256() then
        if self:sha256() then
            hash.hash_append(hc, self:sha256())
        else
            cs, re = self:_compute_checksum(digest.SHA256)
            if not cs then
                return false, e:cat(re)
            end
            hash.hash_append(hc, cs)
        end
        cs_done = true
    end

    assert(cs_done, "no checksum algorithm enabled for fileid()")

    if e2option.opts["check-remote"] then
        rc, re = self:checksum_verify()
        if not rc then
            return false, e:cat(re)
        end
    end

    if self._licences then
        local lid

        for licencename in self._licences:iter() do
            local lid, re = licence.licences[licencename]:licenceid()
            if not lid then
                return false, e:cat(re)
            end
            hash.hash_append(hc, lid)
        end
    end

    if self._unpack then
        hash.hash_append(hc, self._unpack)
    elseif self._patch then
        hash.hash_append(hc, self._patch)
    elseif self._copy then
        hash.hash_append(hc, self._copy)
    end

    fid = hash.hash_finish(hc)
    e2lib.logf(4, "BUILDID: %s fileid=%s", self:servloc(), fid)
    return fid
end

--- Verify file addressed by server name and location matches configured
-- checksum (if available).
-- @return True if verify succeeds, False otherwise
-- @return Error object on failure.
function e2tool.file_class:checksum_verify()
    local rc, re, e, digest_types, cs_cache, cs_remote, cs_fetch, checksum
    local checksum_conf

    e = err.new("error verifying checksum of %s", self:servloc())

    digest_types = {}
    if self:sha1() or project.checksums_sha1() then
        table.insert(digest_types, digest.SHA1)
    end
    if self:sha256() or project.checksums_sha256() then
        table.insert(digest_types, digest.SHA256)
    end
    assert(#digest_types > 0)

    for _,digest_type in ipairs(digest_types) do

        if cache.cache_enabled(cache.cache(), self._server) then
            cs_cache, re = self:_compute_checksum(digest_type)
            if not cs_cache then
                return false, e:cat(re)
            end
        end

        -- Server-side checksum computation for ssh-like transports
        if e2option.opts["check-remote"] then
            cs_remote, re = self:_compute_remote_checksum(digest_type)
            if re then
                return false, e:cat(re)
            end
        end

        if not cs_cache or (e2option.opts["check-remote"] and not cs_remote) then
            cs_fetch, re = self:_compute_checksum(digest_type, { cache = false })
            if not cs_fetch then
                return false, e:cat(re)
            end
        end

        assert(cs_cache or cs_fetch, "checksum_verify() failed to report error")

        rc = true
        if (cs_cache and cs_fetch) and cs_cache ~= cs_fetch then
            e:append("checksum verification failed: cached file checksum differs from fetched file checksum")
            e:append("type: %s cache: %s fetched: %s",
                digest.type_to_string(digest_type), cs_cache, cs_fetch)
            rc = false
        end

        if (cs_cache and cs_remote) and cs_cache ~= cs_remote then
            e:append("checksum verification failed: cached file checksum differs from remote file checksum")
            e:append("type: %s cache: %s remote: %s",
                digest.type_to_string(digest_type), cs_cache, cs_remote)
            rc = false
        end

        if (cs_fetch and cs_remote) and cs_fetch ~= cs_remote then
            e:append("checksum verification failed: refetched file checksum differs from remote file checksum")
            e:append("type: %s refetched: %s remote: %s",
                digest.type_to_string(digest_type), cs_fetch, cs_remote)
            rc = false
        end

        checksum = cs_cache or cs_fetch

        if digest_type == digest.SHA1 then
            checksum_conf = self._sha1
        elseif digest_type == digest.SHA256 then
            checksum_conf = self._sha256
        else
            assert(false, "invalid digest_type")
        end

        if checksum_conf and checksum_conf ~= checksum then
            e:append("checksum verification failed: configured file checksum "..
                "differs from computed file checksum")
            e:append("type: %s configured: %s computed: %s",
                digest.type_to_string(digest_type), checksum_conf, checksum)
            rc = false
        end

        if not rc then
            return false, e
        end
    end

    return true
end

--- Set or return the server attribute.
-- Server name is any name known to cache.
-- @param server Optional server name to set
-- @return Server name
-- @raise Assert on bad input or unset server name
function e2tool.file_class:server(server)
    if server then
        assertIsStringN(server)
        self._server = server
    end

    return self._server
end

--- Set or return the location attribute.
-- File path relative to server.
-- @param location Optional location to set
-- @return Location
-- @raise Assert on bad input or unset location
function e2tool.file_class:location(location)
    if location then
        assertIsStringN(location)
        self._location = location
    end

    return self._location
end

--- Get or set the <b>configured</b> SHA1 sum.
-- @param sha1 Optional SHA1 sum to set
-- @return SHA1 sum or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:sha1(sha1)
    if sha1 then
        assertIsString(sha1)
        assert(#sha1 == digest.SHA1_LEN)
        self._sha1 = sha1
    end

    return self._sha1 or false
end

--- Get or set the <b>configured</b> SHA256 sum.
-- @param sha256 Optional SHA256 sum to set
-- @return SHA256 sum or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:sha256(sha256)
    if sha256 then
        assertIsString(sha256)
        assert(#sha256 == digest.SHA256_LEN)
        self._sha256 = sha256
    end

    return self._sha256 or false
end

--- Get or set per-file licence list.
-- @param lic_sl Optional licences stringlist to set
-- @return licence stringlist or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:licences(lic_sl)
    if lic_sl then
        assertIsTable(lic_sl)
        assert(lic_sl:isInstanceOf(sl.sl))
        self._licences = lic_sl
    end

    return self._licences or false
end

--- Get or set the unpack attribute.
-- unpack, copy and patch are exclusive attributes, only one can be set
-- @param unpack Optional unpack attribute to set
-- @return Unpack attribute or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:unpack(unpack)
    if unpack then
        assertIsString(unpack)
        assert(not self._copy and not self._patch)
        self._unpack = unpack
    end

    return self._unpack or false
end

--- Get or set the copy attribute.
-- unpack, copy and patch are exclusive attributes, only one can be set
-- @param copy Optional copy attribute to set
-- @return Copy attribute or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:copy(copy)
    if copy then
        assertIsString(copy)
        assert(not self._unpack and not self._patch)
        self._copy = copy
    end

    return self._copy or false
end

--- Get or set the patch attribute.
-- unpack, copy and patch are exclusive attributes, only one can be set
-- @param patch Optional patch attribute to set
-- @return Patch attribute or false (unset)
-- @raise Assert on bad input
function e2tool.file_class:patch(patch)
    if patch then
        assertIsStringN(patch)
        assert(not self._unpack and not self._copy)
        self._patch = patch
    end

    return self._patch or false
end

--- @section end

--- check for configuration syntax compatibility and log informational
-- message including list of supported syntaxes if incompatibility is
-- detected.
-- @return bool
-- @return an error object on failure
local function check_config_syntax_compat()
    local re, e, sf, l

    e = err.new("checking configuration syntax compatibilitly failed")
    sf = e2lib.join(e2tool.root(), e2lib.globals.syntax_file)

    l, re = eio.file_read_line(sf)
    if not l then
        return false, e:cat(re)
    end

    for _,m in ipairs(buildconfig.SYNTAX) do
        m = string.format("^%s$", m)
        if l:match(m) then
            return true
        end
    end

    e:cat([[
Your configuration syntax is incompatible with this tool version.
Please read the configuration Changelog, update your project configuration
and finally insert the new configuration syntax version into %s

Configuration syntax versions supported by this version of the tools are:]])

    for _,m in ipairs(buildconfig.SYNTAX) do
        e:append("%s", m)
    end
    e:append("Currently configured configuration syntax is: %q", l)
    return false, e
end

--- Compare global interface version and complain if we're not compatible.
-- @return True on success, false on error.
-- @return Error object on failure.
local function check_global_interface_version()
    local rc, re, e
    local givf, line, supported

    -- read global interface version and check if this version of the local
    -- tools supports the version used for the project

    e = err.new("global interface version check failed")

    givf = e2lib.join(e2tool.root(), e2lib.globals.global_interface_version_file)
    line, re = eio.file_read_line(givf)
    if not line then
        return false, e:cat(re)
    end

    line = line:match("^%s*(%d+)%s*$")
    supported = false
    for _,v in ipairs(buildconfig.GLOBAL_INTERFACE_VERSION) do
        if v == line then
            supported = true
        end
    end
    if not supported then
        e:cat("%s: Invalid global interface version",
            e2lib.globals.global_interface_version_file)
        e:append("supported global interface versions are: %s",
            table.concat(buildconfig.GLOBAL_INTERFACE_VERSION), " ")
        return false, e
    end

    return true
end

--- Open debug logfile.
-- @return True on success, false on error.
-- @return Error object on failure.
local function opendebuglogfile()
    local rc, re, e, logfile, debuglogfile

    rc, re = e2lib.mkdir_recursive(e2lib.join(e2tool.root(), "log"))
    if not rc then
        e = err.new("error making log directory")
        return false, e:cat(re)
    end
    logfile = e2lib.join(e2tool.root(), "log/debug.log")
    rc, re = e2lib.rotate_log(logfile)
    if not rc then
        return false, re
    end

    debuglogfile, re = eio.fopen(logfile, "w")
    if not debuglogfile then
        e = err.new("error opening debug logfile")
        return false, e:cat(re)
    end

    e2lib.globals.debuglogfile = debuglogfile

    return true
end

--- @type e2project_class
e2tool.e2project_class = class("e2project_class")

function e2tool.e2project_class:initialize()
    self._rootdir = false
    self._server_project_location = false
    self._info = false

    -- set the umask value to be used in chroot
    self._chroot_umask = 18 -- 022
    self._host_umask = false

    self._results = false
    self._sources = false
end

--- Initialize the local project, load and initialize local plugins.
-- @param tool string: tool name (without the 'e2-' prefix)
-- @raise Error on failure to initialize the project.
function e2tool.e2project_class:init_project(tool)
    assertIsStringN(tool)

    local e = err.new("initializing local project")
    local rc, re
    local info

    info = self:info({})

    e2tool.current_tool(tool)

    rc, re = e2lib.cwd()
    if not rc then
        error(e:cat(re))
    end
    info.startup_cwd = rc

    self:_init_umask()

    rc, re = e2lib.locate_project_root()
    if not rc then
        error(e:cat("not located in a project directory"))
    end
    e2tool.root(rc)
    self:rootdir(rc)

    -- load local plugins
    local ctx = {  -- plugin context
        info = info,
    }
    local plugindir = e2lib.join(self:rootdir(), ".e2/plugins")
    rc, re = plugin.load_plugins(plugindir, ctx)
    if not rc then
        error(e:cat(re))
    end
    rc, re = plugin.init_plugins()
    if not rc then
        error(e:cat(re))
    end

    strict.lock(info)
end

function e2tool.e2project_class:_init_umask()
    self._host_umask = e2lib.umask(self._chroot_umask)
    e2tool.reset_umask()
end

--- Load the project configuration.
function e2tool.e2project_class:load_project(skip_load_config)
    local e = err.new("error loading project configuration")
    local rc, re

    rc, re = check_config_syntax_compat()
    if not rc then
        e2lib.abort(re)
    end

    rc, re = check_global_interface_version()
    if not rc then
        e2lib.abort(re)
    end

    rc, re = opendebuglogfile()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2lib.init2() -- configuration must be available
    if not rc then
        return false, re
    end

    if skip_load_config == true then
        return true
    end


    e2lib.logf(4, "VERSION:       %s", buildconfig.VERSION)
    e2lib.logf(4, "VERSIONSTRING: %s", buildconfig.VERSIONSTRING)

    -- read .e2/proj-location
    local plf = e2lib.join(self:rootdir(), e2lib.globals.project_location_file)
    local line, re = eio.file_read_line(plf)
    if not line then
        return false, e:cat(re)
    end
    local _, _, l = string.find(line, "^%s*(%S+)%s*$")
    if not l then
        return false, e:cat("%s: can't parse project location", plf)
    end
    self:project_location(l)
    e2lib.logf(4, "project location is %s", self:project_location())

    -- setup cache
    local config, re = e2lib.get_global_config()
    if not config then
        return false, e:cat(re)
    end

    rc, re = cache.setup_cache(config)
    if not rc then
        return false, e:cat(re)
    end

    cache.cache(rc)

    rc, re = cache.setup_cache_local(
        cache.cache(), self:rootdir(), self:project_location())
    if not rc then
        return false, e:cat(re)
    end

    rc, re = cache.setup_cache_apply_opts(cache.cache())
    if not rc then
        return false, e:cat(re)
    end

    local f = e2lib.join(self:rootdir(), e2lib.globals.e2version_file)
    local v, re = e2lib.parse_e2versionfile(f)
    if not v then
        return false, e:cat(re)
    end

    if v.tag ~= buildconfig.VERSIONSTRING then
        return false, e:cat("local tool version does not match the " ..
            "version configured\n in `%s`\nlocal tool version is %s\n" ..
            "required version is %s", f, buildconfig.VERSIONSTRING, v.tag)
    end

    -- read environment configuration
    rc, re = projenv.load_env_config("proj/env")
    if not rc then
        return false, e:cat(re)
    end

    -- read project configuration
    rc, re = project.load_project_config()
    if not rc then
        return false, e:cat(re)
    end

    -- chroot config
    rc, re = chroot.load_chroot_config()
    if not rc then
        return false, e:cat(re)
    end

    -- licences
    rc, re = licence.load_licence_config()
    if not rc then
        return false, e:cat(re)
    end

    -- sources
    rc, re = source.load_source_configs()
    if not rc then
        return false, e:cat(re)
    end

    -- results
    rc, re = result.load_result_configs()
    if not rc then
        return false, e:cat(re)
    end

    -- project result envs must be checked after loading results
    rc, re = projenv.verify_result_envs()
    if not rc then
        return false, e:cat(re)
    end

    -- after results are loaded, verify the project configuration
    rc, re = project.verify_project_config()
    if not rc then
        return false, e:cat(re)
    end

    -- warn if deprecated config files still exist
    local deprecated_files = {
        "proj/servers",
        "proj/result-storage",
        "proj/default-results",
        "proj/name",
        "proj/release-id",
        ".e2/version",
    }
    for _,f in ipairs(deprecated_files) do
        local path = e2lib.join(e2tool.root(), f)
        if e2lib.exists(path) then
            e2lib.warnf("WDEPRECATED",
                "File exists but is no longer used: `%s'", f)
        end
    end

    rc, re = policy.init()
    if not rc then
        return false, e:cat(re)
    end

    if e2option.opts["check"] then
        rc, re = self:check_local()
        if not rc then
            return false, e:cat(re)
        end
    end

    if e2option.opts["check-remote"] then
        rc, re = self:check_remote()
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- Get or set the root directory of the e2 project.
-- @param r rootdir to set, or nil
-- @return rootdir string.
-- @raise Assert on bad input
function e2tool.e2project_class:rootdir(r)
    if r then
        assertIsStringN(r)
        self._rootdir = r
    else
        assertIsStringN(self._rootdir)
    end
    return self._rootdir
end

--- Get the local template directory.
-- @return local template directory.
function e2tool.e2project_class:local_template_path()
    return e2lib.join(self:rootdir(), ".e2/lib/e2/templates")
end

--- Get or set *server* project location
-- @param l project location to set, or nil.
-- @return project location.
-- @raise Assert on bad input or unset project location.
function e2tool.e2project_class:project_location(l)
    if l then
        assertIsStringN(l)
        self._server_project_location = l
    else
        assertIsStringN(self._server_project_location)
    end
    return self._server_project_location
end

function e2tool.e2project_class:info(i)
    if i then
        assertIsTable(i)
        self._info = i
    else
        assertIsTable(self._info)
    end
    return self._info
end

function e2tool.e2project_class:check_local()
    local e, rc, re
    local dirty, mismatch

    e = err.new("checking project (local)")

    rc, re, mismatch = generic_git.verify_head_match_tag(
        self:rootdir(), project.release_id())
    if not rc then
        if mismatch then
            e:append("project repository tag does not match " ..
                "the ReleaseId given in proj/config")
        else
            return false, e:cat(re)
        end
    end

    rc, re, dirty = generic_git.verify_clean_repository(self:rootdir())
    if not rc then
        if dirty then
            e:append("project repository is not clean")
        else
            return false, e:cat(re)
        end
    end

    if e:getcount() > 1 then
        return false, e
    end
    return true
end

function e2tool.e2project_class:check_remote()
    local e, rc, re
    e = err.new("checking project (remote)")

    rc, re = generic_git.verify_remote_tag(
        e2lib.join(self:rootdir(), ".git"), project.release_id())
    if not rc then
        e:append("verifying remote tag failed")
        return false, e:cat(re)
    end

    return true
end

--- @section end

--- Info table contains servers, caches and more...
-- @table info
-- @field startup_cwd Current working dir at startup (string).
-- @field chroot_umask Umask setting for chroot (decimal number).
-- @field host_umask Default umask of the process (decimal number).


--- set umask to value used for build processes
function e2tool.set_umask()
    e2lib.umask(e2tool.e2project()._chroot_umask) -- XXX: remove hack
end

--- set umask back to the value used on the host
function e2tool.reset_umask()
    e2lib.umask(e2tool.e2project()._host_umask) -- XXX: remove hack
end

--- Set a new info table.
-- @param t Table to use for info.
-- @return The new info table.
--[[local function set_info(t)
    assertIsTable(t)
    _info = t
    return _info
end]]

--- Return the info table.
-- @return Info table on success,
--         false if the info table has not been initialised yet.
function e2tool.info()
    return e2tool.e2project():info()
end

local _current_tool
--- Get current local tool name.
-- @param tool Optional new tool name.
-- @return Tool name
-- @raise Assert if tool not set/invalid.
function e2tool.current_tool(tool)
    if tool then
        assertIsStringN(tool)
        _current_tool = tool
    end

    assertIsStringN(_current_tool)
    return _current_tool
end

local _project_root
--- Get (set) project root.
-- @param project_root Optional. Set to specify project root.
-- @return Project root directory.
function e2tool.root(project_root)
    if project_root then
        assertIsStringN(project_root)
        _project_root = project_root
    end

    assertIsStringN(_project_root)
    return _project_root
end

local _the_e2project
--- Get the e2project singleton.
function e2tool.e2project()
    if not _the_e2project then
        _the_e2project = e2tool.e2project_class:new()
    end
    return _the_e2project
end

--- Verify that a result or source file pathname in the form
-- "group1/group2/name" contains only valid characters.
-- Note that the path to the project root does not share the same constraints,
-- it's an error to pass it to this function.
--
-- @param pathname Relative path to a source or result, including
-- sub-directories (string).
-- @return True when the path is legal, false otherwise.
-- @return Error object on failure.
function e2tool.verify_src_res_pathname_valid_chars(pathname)
    local msg = "only alphanumeric characters and '-_/' are allowed"
    if not pathname:match("^[-_0-9a-zA-Z/]+$") then
        return false, err.new(msg)
    end

    return true
end

--- Verify that a result or source name in the form "group1.group2.name"
-- contains only valid characters.
--
-- @param name Full source or result name, including groups (string).
-- @return True when the name is legal, false otherwise.
-- @return Error object on failure.
function e2tool.verify_src_res_name_valid_chars(name)
    local msg = "only alphanumeric characters and '-_.' are allowed"
    if not name:match("^[-_0-9a-zA-Z.]+$") then
        return false, err.new(msg)
    end

    return true
end

--- Convert source or result name, including groups, to a file system path.
-- @param name Name of a src or res, with optional group notation (string).
-- @return File system path equivalent of the input.
function e2tool.src_res_name_to_path(name)
    return name:gsub("%.", "/")
end

--- Convert file system path of a source or result, including sub-directories
-- to group notation separated by dots.
-- @param pathname File system path of a src or res, with optional
-- sub-directories (string).
-- @return Group dot notation equivalent of the input.
function e2tool.src_res_path_to_name(pathname)
    return pathname:gsub("/", ".")
end

--- Get project-relative directory for a result.
-- Returns the relative path to the resultdir and optionally a name and prefix
-- (e.g. prefix/res/name).
-- @param name Optional result path component (string).
-- @param prefix Optional prefix path.
-- @return Path of the result.
function e2tool.resultdir(name, prefix)
    local p = "res"
    if name then
        p = e2lib.join(p, name)
    end
    if prefix then
        p = e2lib.join(prefix, p)
    end
    return p
end

--- Get project-relative directory for a source.
-- Returns the relative path to the sourcedir and optinally a name and prefix
-- (e.g. prefix/src/name).
-- @param name Optional source path component (string).
-- @param prefix Optional prefix path.
-- @return Path of the source.
function e2tool.sourcedir(name, prefix)
    local p = "src"
    if name then
        p = e2lib.join(p, name)
    end
    if prefix then
        p = e2lib.join(prefix, p)
    end
    return p
end

--- Get project-relative path to the result config.
-- @param name Result path component.
-- @param prefix Optional prefix path.
-- @return Path to the resultconfig.
function e2tool.resultconfig(name, prefix)
    assert(type(name) == "string")
    assert(prefix == nil or type(prefix) == "string")
    return e2lib.join(e2tool.resultdir(name, prefix), "config")
end

--- Get project-relative path to the result build-script
-- @param name Result path compnent name.
-- @param prefix Optional prefix path.
-- @return Path to the result build-script.
function e2tool.resultbuildscript(name, prefix)
    assert(type(name) == "string")
    assert(prefix == nil or type(prefix) == "string")
    return e2lib.join(e2tool.resultdir(name, prefix), "build-script")
end

--- Get project-relative path to the source config.
-- @param name Source path component.
-- @param prefix Optional prefix path.
-- @return Path to the sourceconfig.
function e2tool.sourceconfig(name, prefix)
    assert(type(name) == "string")
    assert(prefix == nil or type(prefix) == "string")
    return e2lib.join(e2tool.sourcedir(name, prefix), "config")
end

--- Returns a sorted vector with all depdencies of result, and all
-- the indirect dependencies. If result is a vector, calculates dependencies
-- for all results and includes those from result. If result is a result name,
-- calculates its dependencies but does not include the result itself.
-- @param resultv Vector of result names or single result name.
-- @return Vector of dependencies of the result, may or may not include result.
--         False on failure.
-- @return Error object on failure
function e2tool.dlist_recursive(resultv)
    assert(type(resultv) == "string" or type(resultv) == "table")

    local rc, re
    local seen = {}
    local path = {}
    local col = {}
    local t = {}
    local depends

    if type(resultv) == "string" then
        assertIsTable(result.results[resultv])
        depends = result.results[resultv]:depends_list()
    else
        depends = sl.sl:new()
        depends:insert_table(resultv)
    end

    local function visit(resultname)
        local deps, re

        if seen[resultname] then
            local removeupto = seen[resultname]-1

            -- remove depends not part of cycle
            for pos=1,removeupto do
                table.remove(path, 1)
            end

            -- improves visualization of cycle
            table.insert(path, resultname)

            return false,
                err.new("cyclic dependency: %s", table.concat(path, " -> "))
        end

        if not col[resultname] then
            table.insert(path, resultname)
            seen[resultname] = #path
            col[resultname] = true

            deps = result.results[resultname]:depends_list()

            for d in deps:iter() do
                rc, re = visit(d)
                if not rc then
                    return false, re
                end
            end
            table.insert(t, resultname)
            table.remove(path)
            seen[resultname] = nil
        end
        return true
    end

    for resultname in depends:iter() do
        rc, re = e2tool.verify_src_res_name_valid_chars(resultname)
        if not rc then
            return false, err.new("'%s' is not a valid result name", resultname)
        end

        if not result.results[resultname] then
            return false, err.new("selecting invalid result: %s", resultname)
        end

        rc, re = visit(resultname)
        if not rc then
            return false, re
        end
    end

    return t
end

--- Calls dlist_recursive() with the default results vector of the project.
-- @return Vector of results in topological order, or false on error.
-- @return Error object on failure.
-- @see e2tool.dlist_recursive
function e2tool.dsort()
    local dr = {}
    for r in project.default_results_iter() do
        table.insert(dr, r)
    end
    return e2tool.dlist_recursive(dr)
end

--- select (mark) results based upon a list of results usually given on the
-- command line. Parameters are assigned to all selected results.
-- @param results table: list of result names
-- @param force_rebuild bool
-- @param keep_chroot bool
-- @param build_mode table: build mode policy. Optional.
-- @param playground bool
-- @return bool
-- @return an error object on failure
function e2tool.select_results(results, force_rebuild, keep_chroot, build_mode, playground)
    local rc, re, res, settings

    for _,resultname in ipairs(results) do
        rc, re = e2tool.verify_src_res_name_valid_chars(resultname)
        if not rc then
            return false, err.new("'%s' is not a valid result name", resultname)
        end

        res = result.results[resultname]
        if not res then
            return false, err.new("selecting invalid result: %s", resultname)
        end

        settings = res:build_settings()

        settings:selected(true)

        if force_rebuild then
            settings:force_rebuild(true)
        end

        if keep_chroot then
            settings:keep_chroot(true)
        end

        if playground then
            settings:prep_playground(true)
        end

        if build_mode then
            res:build_mode(build_mode)
        end
    end

    return true
end

--- Build all results in resultv in-order.
-- @param resultv Result name vector.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2tool.build_results(resultv)
    e2lib.logf(3, "building results")

    for _, resultname in ipairs(resultv) do
        local rc, re, res
        local t1, t2, deltat
        local e = err.new("building result failed: %s", resultname)

        t1 = os.time()

        res = result.results[resultname]

        rc, re = res:build_process():build(res)
        if not rc then
            return false, e:cat(re)
        end

        t2 = os.time()
        deltat = os.difftime(t2, t1)
        e2lib.logf(3, "timing: result [%s] %d", resultname, deltat)
    end

    return true
end

--- Print selection status for a list of results
-- @param resultvec table: list of result names
-- @return bool
-- @return an error object on failure
function e2tool.print_selection(resultvec)
    for _,resultname in ipairs(resultvec) do
        local e = err.new("error printing selected results")
        local res = result.results[resultname]
        if not res then
            return false, e:append("no such result: %s", resultname)
        end

        local settings = res:build_settings()

        local s = settings:selected() and "[ selected ]" or "[dependency]"
        local f = settings:force_rebuild() and "[force rebuild]" or ""
        local p = settings:prep_playground() and "[playground]" or ""

        e2lib.logf(4, "Selected result: %-20s %s %s %s", resultname, s, f, p)
    end
    return true
end

return strict.lock(e2tool)

-- vim:sw=4:sts=4:et:
