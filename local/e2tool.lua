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
local scm = require("scm")
local sl = require("sl")
local source = require("source")
local strict = require("strict")
local tools = require("tools")
local url = require("url")

--- @type file_class
e2tool.file_class = class("file_class")

--- File_class constructor.
-- A file_class represents a single file entry in various e2 config files.
-- Server name and location are required, everything else is optional and some
-- attributes are not universal. Most error checking is thus left to other
-- layers, except for some basic assert statements.
-- @param server Server name (as known to cache)
-- @param location Path to file relative to server
-- @raise Assert on bad input
function e2tool.file_class:initialize(server, location)
    assertIsStringN(server)
    assertIsStringN(location)
    self._server = server
    self._location = location
    self._sha1 = nil
    self._licences = nil
    self._unpack = nil
    self._copy = nil
    self._patch = nil
end

--- Create a new instance.
-- Note that the licences sl is NOT copied.
-- @return object copy
-- @see sl.sl
function e2tool.file_class:instance_copy()
    local c = e2tool.file_class:new(self._server, self._location)
    c:sha1(self._sha1)
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

--- Compute checksum of file by retreiving it via the cache transport,
-- and hashing local.
-- @param flags cache flags
-- @return SHA1 checksum on success, false if an error occured.
-- @return error object on failure.
function e2tool.file_class:_compute_checksum(flags)
    local rc, re, info, path, checksum

    info = e2tool.info()

    path, re = cache.fetch_file_path(info.cache, self._server, self._location,
        flags)
    if not path then
        return false, re
    end

    checksum, re = hash.hash_file_once(path)
    if not checksum then
        return false, re
    end

    return checksum
end

--- Compute checksum of file on the remote server, if transport supports it.
-- @return SHA1 checksum on success - false if not possible or on failure
-- @return error object on failure.
function e2tool.file_class:_compute_remote_checksum()
    local rc, re, info, surl, u, checksum

    info = e2tool.info()

    surl, re = cache.remote_url(info.cache, self._server, self._location)
    if not surl then
        return false, re
    end

    u, re = url.parse(surl)
    if not u then
        return false, re
    end

    if u.transport == "ssh" or u.transport == "scp" or
        u.transport == "rsync+ssh" then
        local argv, stdout, dt, sha1sum_remote

        sha1sum_remote =  { "sha1sum", e2lib.join("/", u.path) }
        rc, re, stdout = e2lib.ssh_remote_cmd(u, sha1sum_remote)
        if not rc then
            return false, re
        end

        dt, re = digest.parsestring(stdout)
        if not dt then
            return false, re
        end

        for k,dt_entry in ipairs(dt) do
            if dt_entry.name == e2lib.join("/", u.path) then
                checksum = dt_entry.checksum
                break;
            end
        end

        if not checksum or #checksum ~= digest.SHA1_LEN then
            return false,
                err.new("could not extract checksum from remote output")
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
    local rc, re, e, fileid

    e = err.new("error calculating file id for file: %s", self:servloc())

    if self:sha1() then
        fileid = self:sha1()
    else
        fileid, re = self:_compute_checksum()
        if not fileid then
            return false, e:cat(re)
        end
    end

    if e2option.opts["check-remote"] then
        rc, re = self:checksum_verify()
        if not rc then
            return false, e:cat(re)
        end
    end

    local hc, info
    info = e2tool.info()
    hc = hash.hash_start()
    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._location)

    hash.hash_append(hc, fileid)

    if self._licences then
        local lid

        for licencename in self._licences:iter() do
            local lid, re = licence.licences[licencename]:licenceid(info)
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

    return hash.hash_finish(hc)
end

--- Verify file addressed by server name and location matches configured
-- checksum (if available).
-- @return True if verify succeeds, False otherwise
-- @return Error object on failure.
function e2tool.file_class:checksum_verify()
    local rc, re, e, cs_cache, cs_remote, cs_fetch, checksum, info

    e = err.new("error verifying checksum of %s", self:servloc())

    info = e2tool.info()

    if cache.cache_enabled(info.cache, self._server) then
        cs_cache, re = self:_compute_checksum()
        if not cs_cache then
            return false, e:cat(re)
        end
    end

    -- Server-side checksum computation for ssh-like transports
    if e2option.opts["check-remote"] then
        cs_remote, re = self:_compute_remote_checksum()
        if re then
            return false, e:cat(re)
        end
    end

    if not cs_cache or (e2option.opts["check-remote"] and not cs_remote) then
        cs_fetch, re = self:_compute_checksum({ cache = false })
        if not cs_fetch then
            return false, e:cat(re)
        end
    end

    assert(cs_cache or cs_fetch, "verify_hash() failed to report error")

    rc = true
    if (cs_cache and cs_fetch) and cs_cache ~= cs_fetch then
        e:append("checksum verification failed: cached file checksum differs from fetched file checksum")
        e:append("cache: %s fetched: %s", cs_cache, cs_fetch)
        rc = false
    end

    if (cs_cache and cs_remote) and cs_cache ~= cs_remote then
        e:append("checksum verification failed: cached file checksum differs from remote file checksum")
        e:append("cache: %s remote: %s", cs_cache, cs_remote)
        rc = false
    end

    if (cs_fetch and cs_remote) and cs_fetch ~= cs_remote then
        e:append("checksum verification failed: refetched file checksum differs from remote file checksum")
        e:append("refetched: %s remote: %s", cs_fetch, cs_remote)
        rc = false
    end

    checksum = cs_cache or cs_fetch

    if self._sha1 and self._sha1 ~= checksum then
        e:append("checksum verification failed: configured file checksum differs from computed file checksum")
        e:append("configured: %s computed: %s", self._sha1, checksum)
        rc = false
    end

    if rc then
        return true
    end

    return false, e
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

--- Info table contains servers, caches and more...
-- @table info
-- @field current_tool Name of the current local tool (string).
-- @field startup_cwd Current working dir at startup (string).
-- @field chroot_umask Umask setting for chroot (decimal number).
-- @field host_umask Default umask of the process (decimal number).
-- @field root Project root directory (string).
-- @field project_location string: project location relative to the servers
-- @field local_template_path Path to the local templates (string).
-- @field cache The cache object.
local _info = false

--- Open debug logfile.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function opendebuglogfile(info)
    local rc, re, e, logfile, debuglogfile

    rc, re = e2lib.mkdir_recursive(e2lib.join(info.root, "log"))
    if not rc then
        e = err.new("error making log directory")
        return false, e:cat(re)
    end
    logfile = e2lib.join(info.root, "log/debug.log")
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

-- set the umask value to be used in chroot
local _chroot_umask = 18 -- 022 octal
local _host_umask

--- set umask to value used for build processes
function e2tool.set_umask()
    e2lib.umask(_chroot_umask)
end

--- set umask back to the value used on the host
function e2tool.reset_umask()
    e2lib.umask(_host_umask)
end

--- initialize the umask set/reset mechanism (i.e. store the host umask)
local function init_umask()
    -- save the umask value we run with
    _host_umask = e2lib.umask(_chroot_umask)

    -- restore the previous umask value again
    e2tool.reset_umask()
end

--- Set a new info table.
-- @param t Table to use for info.
-- @return The new info table.
local function set_info(t)
    assertIsTable(t)
    _info = t
    return _info
end

--- Return the info table.
-- @return Info table on success,
--         false if the info table has not been initialised yet.
function e2tool.info()
    return _info
end

--- initialize the local library, load and initialize local plugins
-- @param path string: path to project tree (optional)
-- @param tool string: tool name (without the 'e2-' prefix)
-- @return table: the info table, or false on failure
-- @return an error object on failure
function e2tool.local_init(path, tool)
    local rc, re
    local e = err.new("initializing local tool")
    local info

    info = set_info({})

    info.current_tool = tool

    rc, re = e2lib.cwd()
    if not rc then
        return false, e:cat(re)
    end
    info.startup_cwd = rc

    init_umask(info)

    info.root, re = e2lib.locate_project_root(path)
    if not info.root then
        return false, e:append("not located in a project directory")
    end

    -- load local plugins
    local ctx = {  -- plugin context
        info = info,
    }
    local plugindir = e2lib.join(info.root, ".e2/plugins")
    rc, re = plugin.load_plugins(plugindir, ctx)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = plugin.init_plugins()
    if not rc then
        return false, e:cat(re)
    end

    return info
end

--- check for configuration syntax compatibility and log informational
-- message including list of supported syntaxes if incompatibility is
-- detected.
-- @param info
-- @return bool
-- @return an error object on failure
local function check_config_syntax_compat(info)
    local re, e, sf, l

    e = err.new("checking configuration syntax compatibilitly failed")
    sf = e2lib.join(info.root, e2lib.globals.syntax_file)

    l, re = eio.file_read_line(sf)
    if not l then
        return false, e:cat(re)
    end

    for _,m in ipairs(info.config_syntax_compat) do
        m = string.format("^%s$", m)
        if l:match(m) then
            return true
        end
    end

    local s = [[
Your configuration syntax is incompatible with this tool version.
Please read the configuration Changelog, update your project configuration
and finally insert the new configuration syntax version into %s

Configuration syntax versions supported by this version of the tools are:]]
    e2lib.logf(2, s, sf)
    for _,m in ipairs(info.config_syntax_compat) do
        e2lib.logf(2, "%s", m)
    end
    e2lib.logf(2, "Currently configured configuration syntax is: %q", l)
    return false, e:append("configuration syntax mismatch")
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

--- collect project info.
-- @param info Info table.
-- @param skip_load_config If true, skip loading config files etc.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2tool.collect_project_info(info, skip_load_config)
    local rc, re
    local e = err.new("reading project configuration")

    -- check for configuration compatibility
    info.config_syntax_compat = buildconfig.SYNTAX
    rc, re = check_config_syntax_compat(info)
    if not rc then
        e2lib.finish(1)
    end

    info.local_template_path = e2lib.join(info.root, ".e2/lib/e2/templates")

    rc, re = e2lib.init2() -- configuration must be available
    if not rc then
        return false, re
    end

    if skip_load_config == true then
        return info
    end

    rc, re = opendebuglogfile(info)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.logf(4, "VERSION:       %s", buildconfig.VERSION)
    e2lib.logf(4, "VERSIONSTRING: %s", buildconfig.VERSIONSTRING)

    -- no error check required
    hash.hcache_load(e2lib.join(info.root, ".e2/hashcache"))

    -- read .e2/proj-location
    local plf = e2lib.join(info.root, e2lib.globals.project_location_file)
    local line, re = eio.file_read_line(plf)
    if not line then
        return false, e:cat(re)
    end
    local _, _, l = string.find(line, "^%s*(%S+)%s*$")
    if not l then
        return false, e:append("%s: can't parse project location", plf)
    end
    info.project_location = l
    e2lib.logf(4, "project location is %s", info.project_location)

    -- setup cache
    local config, re = e2lib.get_global_config()
    if not config then
        return false, e:cat(re)
    end

    info.cache, re = cache.setup_cache(config)
    if not info.cache then
        return false, e:cat(re)
    end

    rc, re = cache.setup_cache_local(info.cache, info.root, info.project_location)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = cache.setup_cache_apply_opts(info.cache)
    if not rc then
        return false, e:cat(re)
    end

    local f = e2lib.join(info.root, e2lib.globals.e2version_file)
    local v, re = e2lib.parse_e2versionfile(f)
    if not v then
        return false, re
    end

    if v.tag ~= buildconfig.VERSIONSTRING then
        return false, err.new("local tool version does not match the " ..
            "version configured\n in `%s`\nlocal tool version is %s\n" ..
            "required version is %s", f, buildconfig.VERSIONSTRING, v.tag)
    end

    -- read environment configuration
    rc, re = projenv.load_env_config("proj/env")
    if not rc then
        return false, e:cat(re)
    end

    -- read project configuration
    rc, re = project.load_project_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- chroot config
    rc, re = chroot.load_chroot_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- licences
    rc, re = licence.load_licence_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- sources
    rc, re = source.load_source_configs(info)
    if not rc then
        return false, e:cat(re)
    end

    -- results
    rc, re = result.load_result_configs(info)
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

    if e:getcount() > 1 then
        return false, e
    end

    -- read global interface version and check if this version of the local
    -- tools supports the version used for the project
    local givf = e2lib.join(info.root, e2lib.globals.global_interface_version_file)
    local line, re = eio.file_read_line(givf)
    if not line then
        return false, e:cat(re)
    end
    info.global_interface_version = line:match("^%s*(%d+)%s*$")
    local supported = false
    for _,v in ipairs(buildconfig.GLOBAL_INTERFACE_VERSION) do
        if v == info.global_interface_version then
            supported = true
        end
    end
    if not supported then
        e:append("%s: Invalid global interface version",
        e2lib.globals.global_interface_version_file)
        e:append("supported global interface versions are: %s",
        table.concat(buildconfig.GLOBAL_INTERFACE_VERSION), " ")
        return false, e
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
        local path = e2lib.join(info.root, f)
        if e2lib.exists(path) then
            e2lib.warnf("WDEPRECATED", "File exists but is no longer used: `%s'", f)
        end
    end

    rc, re = policy.init(info)
    if not rc then
        return false, e:cat(re)
    end

    if e2option.opts["check"] then
        local dirty, mismatch

        rc, re, mismatch = generic_git.verify_head_match_tag(info.root,
            project.release_id())
        if not rc then
            if mismatch then
                e:append("project repository tag does not match " ..
                    "the ReleaseId given in proj/config")
            else
                return false, e:cat(re)
            end
        end

        rc, re, dirty = generic_git.verify_clean_repository(info.root)
        if not rc then
            if dirty then
                e = err.new("project repository is not clean")
                return false, e:cat(re)
            else
                return false, e:cat(re)
            end
        end
    end

    if e2option.opts["check-remote"] then
        rc, re = generic_git.verify_remote_tag(
            e2lib.join(info.root, ".git"), project.release_id())
        if not rc then
            e:append("verifying remote tag failed")
            return false, e:cat(re)
        end
    end

    return strict.lock(info)
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
-- @param info the info structure
-- @param results table: list of result names
-- @param force_rebuild bool
-- @param keep_chroot bool
-- @param build_mode table: build mode policy. Optional.
-- @param playground bool
-- @return bool
-- @return an error object on failure
function e2tool.select_results(info, results, force_rebuild, keep_chroot, build_mode, playground)
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
-- @param info
-- @param resultvec table: list of result names
-- @return bool
-- @return an error object on failure
function e2tool.print_selection(info, resultvec)
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

        e2lib.logf(3, "Selected result: %-20s %s %s %s", resultname, s, f, p)
    end
    return true
end

return strict.lock(e2tool)

-- vim:sw=4:sts=4:et:
