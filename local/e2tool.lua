--- Core e2factory data structure and functions around the build process.
-- @module local.e2tool

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

local e2tool = {}
package.loaded["e2tool"] = e2tool -- stop e2tool loading loop

local buildconfig = require("buildconfig")
local cache = require("cache")
local digest = require("digest")
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
local scm = require("scm")
local strict = require("strict")
local tools = require("tools")
local transport = require("transport")
local url = require("url")

-- Build function table, see end of file for details.
local e2tool_ftab = {}

--- Info table contains sources, results, servers, caches and more...
-- @table info
-- @field current_tool Name of the current local tool (string).
-- @field startup_cwd Current working dir at startup (string).
-- @field chroot_umask Umask setting for chroot (decimal number).
-- @field host_umask Default umask of the process (decimal number).
-- @field root Project root directory (string).
-- @field root_server string: url pointing to the project root
-- @field root_server_name string: name of the root server (".")
-- @field default_repo_server string: name of the default scm repo server
-- @field default_files_server string: name of the default files server
-- @field result_storage (deprecated)
-- @field sources table: sources
-- @field sources_sorted table: sorted list of sources
-- @field results table: results
-- @field results_sorted table: sorted list of results
-- @field chroot See info.chroot
-- @field project_location string: project location relative to the servers
-- @field env table: env table
-- @field env_files table: list of env files
-- @field local_template_path Path to the local templates (string).

--- table of sources records, keyed by source names
-- @name sources
-- @class table
-- @field name string: name of the package
-- @field licences table: list of licences
-- @field type string: type of sources ("files", "git", etc)
-- @field server string: server name
-- @field remote string: remote location name
-- @field working string: working directory name
-- @field branch string: branch name
-- @field tag table: table of tag names (strings)
-- @field file table: table of file records (tables)
-- @field fhash string: hash value for this source, for use in buildid
-- 			calculation
-- @field flist table: array of files
-- 			(deprecated, replaced by file records)

--- file records in the sources table
-- @name source.file
-- @class table
-- @field name string: filename
-- @field server string: server name

--- Table for a single result.
-- @table result
-- @field name string: name of the result
-- @field sources table of strings: array of source names
-- @field files OBSOLETE table of strings: array of result file names
-- @field depends table of strings: list of dependencies
-- @field chroot table of strings: list of chroot groups to use
-- @field env table of strings
-- @field _env
-- @field selected bool: select for build?
-- @field force_rebuild bool: force rebuild?
-- @field build_mode table: build mode policy object
-- @field build_config
-- @field directory
-- @see policy.build_mode
-- @see e2build.build_config
-- @see plugins.collect_project

--- Table of chroot configuration. Locked.
-- @table info.chroot
-- @field default_groups Chroot groups used in every result. Locked.
-- @field groups_byname Dict mapping group name to group table.
-- @field groups_sorted Vector of sorted group names. Locked.

--- chroot group table
-- @table chroot group table
-- @field name string: group name
-- @field server string: server name
-- @field files table: array of file names

--- env - environment table from "proj/env"
-- @name env
-- @class table

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

--- Load user configuration file.
-- @param info Info table.
-- @param path Path to file (string).
-- @param dest Destination table.
-- @param index Name of the newly created table inside destination (string).
-- @param var Table name in configuration file (string).
-- @return True on success, false on error.
-- @return Error object on failure.
local function load_user_config(info, path, dest, index, var)
    local rc, re
    local e = err.new("loading configuration failed")
    e2lib.logf(3, "loading %s", path)
    if not e2lib.exists(path) then
        return false, e:append("file does not exist: %s", path)
    end

    local function func(table)
        dest[index] = table
    end

    local rc, re = e2lib.dofile2(path, { [var] = func, env = info.env, string=string })
    if not rc then
        return false, e:cat(re)
    end

    if not dest[index] then
        return false, e:append("empty or invalid configuration: %s", path)
    end

    return true
end

--- config item
-- @class table
-- @class config_item
-- @field data table: config data
-- @field type string: config type
-- @field filename string: config file name

--- load config file and return a list of config item tables
-- @param info info table
-- @param path string: file to load
-- @param types list of strings: allowed config types
-- @return List of config items, or false on error.
-- @return Error object on failure
local function load_user_config2(info, path, types)
    local e = err.new("loading configuration file failed")
    local rc, re
    local list = {}

    -- the list of config types
    local f = {}
    f.e2source = function(data)
        local t = {}
        t.data = data
        t.type = "sources"
        t.filename = path
        table.insert(list, t)
    end
    f.e2result = function(data)
        local t = {}
        t.data = data
        t.type = "result"
        t.filename = path
        table.insert(list, t)
    end
    f.e2project = function(data)
        local t = {}
        t.data = data
        t.type = "project"
        t.filename = path
        table.insert(list, t)
    end
    f.e2chroot = function(data)
        local t = {}
        t.data = data
        t.type = "chroot"
        t.filename = path
        table.insert(list, t)
    end
    f.e2env = function(data)
        local t = {}
        t.data = data
        t.type = "env"
        t.filename = path
        table.insert(list, t)
    end

    local g = {}			-- compose the environment for the config file
    g.env = info.env			-- env
    g.string = string			-- string
    for _,typ in ipairs(types) do
        g[typ] = f[typ]			-- and some config functions
    end

    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, e:cat(re)
    end
    return list
end

--- check results.
local function check_results(info)
    local e, rc, re

    for _,f in ipairs(e2tool_ftab.check_result) do
        for r,_ in pairs(info.results) do
            rc, re = f(info, r)
            if not rc then
                e = err.new("Error while checking results")
                return false, e:cat(re)
            end
        end
    end

    return true
end

--- check result configuration
-- @param info table: the info table
-- @param resultname string: the result to check
local function check_result(info, resultname)
    local res = info.results[resultname]
    local e = err.new("in result %s:", resultname)
    if not res then
        e:append("result does not exist: %s", resultname)
        return false, e
    end
    if res.files then
        e2lib.warnf("WDEPRECATED", "in result %s", resultname)
        e2lib.warnf("WDEPRECATED",
        " files attribute is deprecated and no longer used")
        res.files = nil
    end
    if type(res.sources) == "nil" then
        e2lib.warnf("WDEFAULT", "in result %s:", resultname)
        e2lib.warnf("WDEFAULT", " sources attribute not configured." ..
        "Defaulting to empty list")
        res.sources = {}
    elseif type(res.sources) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", resultname)
        e2lib.warnf("WDEPRECATED", " sources attribute is string. "..
        "Converting to list")
        res.sources = { res.sources }
    end
    local rc, re = e2lib.vrfy_listofstrings(res.sources, "sources", true, false)
    if not rc then
        e:append("source attribute:")
        e:cat(re)
    else
        for i,s in ipairs(res.sources) do
            if not info.sources[s] then
                e:append("source does not exist: %s", s)
            end
        end
    end
    if type(res.depends) == "nil" then
        e2lib.warnf("WDEFAULT", "in result %s: ", resultname)
        e2lib.warnf("WDEFAULT", " depends attribute not configured. " ..
        "Defaulting to empty list")
        res.depends = {}
    elseif type(res.depends) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", resultname)
        e2lib.warnf("WDEPRECATED", " depends attribute is string. "..
        "Converting to list")
        res.depends = { res.depends }
    end
    local rc, re = e2lib.vrfy_listofstrings(res.depends, "depends", true, false)
    if not rc then
        e:append("dependency attribute:")
        e:cat(re)
    else
        for i,d in pairs(res.depends) do
            if not info.results[d] then
                e:append("dependency does not exist: %s", d)
            end
        end
    end
    if type(res.chroot) == "nil" then
        e2lib.warnf("WDEFAULT", "in result %s:", resultname)
        e2lib.warnf("WDEFAULT", " chroot groups not configured. " ..
        "Defaulting to empty list")
        res.chroot = {}
    elseif type(res.chroot) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", resultname)
        e2lib.warnf("WDEPRECATED", " chroot attribute is string. "..
        "Converting to list")
        res.chroot = { res.chroot }
    end
    local rc, re = e2lib.vrfy_listofstrings(res.chroot, "chroot", true, false)
    if not rc then
        e:append("chroot attribute:")
        e:cat(re)
    else
        -- apply default chroot groups
        for _,g in ipairs(info.chroot.default_groups) do
            table.insert(res.chroot, g)
        end
        -- The list may have duplicates now. Unify.
        rc, re = e2lib.vrfy_listofstrings(res.chroot, "chroot", false, true)
        if not rc then
            e:append("chroot attribute:")
            e:cat(re)
        end
        for _,g in ipairs(res.chroot) do
            if not info.chroot.groups_byname[g] then
                e:append("chroot group does not exist: %s", g)
            end
        end
        table.sort(res.chroot)
    end
    if res.env and type(res.env) ~= "table" then
        e:append("result has invalid `env' attribute")
    else
        if not res.env then
            e2lib.warnf("WDEFAULT",
            "result has no `env' attribute. "..
            "Defaulting to empty dictionary")
            res.env = {}
        end
        for k,v in pairs(res.env) do
            if type(k) ~= "string" then
                e:append("in `env' dictionary: "..
                "key is not a string: %s", tostring(k))
            elseif type(v) ~= "string" then
                e:append("in `env' dictionary: "..
                "value is not a string: %s", tostring(v))
            else
                res._env:set(k, v)
            end
        end
    end
    for _,r in ipairs(info.project.deploy_results) do
        if r == resultname then
            res._deploy = true
            break
        end
    end
    local build_script =
        e2tool.resultbuildscript(info.results[resultname].directory, info.root)
    if not e2lib.isfile(build_script) then
        e:append("build-script does not exist: %s", build_script)
    end

    if e:getcount() > 1 then
        return false, e
    end

    return true
end

--- set umask to value used for build processes
-- @param info
function e2tool.set_umask(info)
    e2lib.logf(4, "setting umask to %04o", info.chroot_umask)
    e2lib.umask(info.chroot_umask)
end

-- set umask back to the value used on the host
-- @param info
function e2tool.reset_umask(info)
    e2lib.logf(4, "setting umask to %04o", info.host_umask)
    e2lib.umask(info.host_umask)
end

-- initialize the umask set/reset mechanism (i.e. store the host umask)
-- @param info
local function init_umask(info)
    -- set the umask value to be used in chroot
    info.chroot_umask = 18   -- 022 octal

    -- save the umask value we run with
    info.host_umask = e2lib.umask(info.chroot_umask)

    -- restore the previous umask value again
    e2tool.reset_umask(info)
end

--- get dependencies for use in build order calculation
local function get_depends(info, resultname)
    local t = {}
    local res = info.results[resultname]
    if not res.depends then
        return t
    end
    for _,d in ipairs(res.depends) do
        table.insert(t, d)
    end
    return t
end

--- initialize the local library, load and initialize local plugins
-- @param path string: path to project tree
-- @param tool string: tool name (without the 'e2-' prefix)
-- @return table: the info table, or false on failure
-- @return an error object on failure
function e2tool.local_init(path, tool)
    local rc, re
    local e = err.new("initializing local tool")
    local info = {}

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

    rc, re = e2tool.register_check_result(info, check_result)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2tool.register_dlist(info, get_depends)
    if not rc then
        return false, e:cat(re)
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

--- load env config.
local function load_env_config(info, file)
    e2lib.logf(4, "loading environment: %s", file)
    local e = err.new("loading environment: %s", file)
    local rc, re

    local info = info
    local load_env_config = load_env_config
    local merge_error = false
    local function mergeenv(data)
        -- upvalues: info, load_env_config(), merge_error
        local rc, re
        if type(data) == "string" then
            -- include file
            rc, re = load_env_config(info, data)
            if not rc then
                -- no error checking in place, so set upvalue and return
                merge_error = re
                return
            end
        else
            -- environment table
            for var, val in pairs(data) do
                if type(var) ~= "string" or
                    (type(val) ~= "string" and type(val) ~= "table") then
                    merge_error = err.new("invalid environment entry in %s: %s=%s",
                    file, tostring(var), tostring(val))
                    return nil
                end
                if type(val) == "string" then
                    e2lib.logf(4, "global env: %-15s = %-15s", var, val)
                    info.env[var] = val
                    info.global_env:set(var, val)
                elseif type(val) == "table" then
                    for var1, val1 in pairs(val) do
                        if type(var1) ~= "string" or
                            (type(val1) ~= "string" and type(val1) ~= "table") then
                            merge_error = err.new(
                            "invalid environment entry in %s [%s]: %s=%s",
                            file, var, tostring(var1), tostring(val1))
                            return nil
                        end
                        e2lib.logf(4, "result env: %-15s = %-15s [%s]",
                        var1, val1, var)
                        info.env[var] = info.env[var] or {}
                        info.env[var][var1] = val1
                        info.result_env[var] = info.result_env[var] or environment.new()
                        info.result_env[var]:set(var1, val1)
                    end
                end
            end
        end
        return true
    end

    table.insert(info.env_files, file)
    local path = e2lib.join(info.root, file)
    local g = {
        e2env = info.env,
        string = string,
        env = mergeenv,
    }
    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, e:cat(re)
    end
    if merge_error then
        return false, merge_error
    end
    e2lib.logf(4, "loading environment done: %s", file)
    return true
end

--- read chroot configuration
-- @param info
-- @return bool
-- @return an error object on failure
local function read_chroot_config(info)
    local e = err.new("reading chroot config failed")
    local t = {}
    local rc, re =
        load_user_config(info, e2lib.join(info.root, "proj/chroot"),
            t, "chroot", "e2chroot")
    if not rc then
        return false, e:cat(re)
    end
    if type(t.chroot) ~= "table" then
        return false, e:append("chroot configuration table not available")
    end
    if type(t.chroot.groups) ~= "table" then
        return false, e:append("chroot.groups configuration is not a table")
    end
    if type(t.chroot.default_groups) ~= "table" then
        return false, e:append("chroot.default_groups is not a table")
    end
    info.chroot = {}
    info.chroot.default_groups = t.chroot.default_groups or {}
    info.chroot.groups_byname = {}
    info.chroot.groups_sorted = {}
    strict.lock(info.chroot)
    for _,grp in ipairs(t.chroot.groups) do
        if grp.group then
            e:append("in group: %s", grp.group)
            e:append(" `group' attribute is deprecated. Replace by `name'")
            return false, e
        end
        if not grp.name then
            return false, e:append("`name' attribute is missing in a group")
        end
        local g = grp.name
        table.insert(info.chroot.groups_sorted, g)
        if info.chroot.groups_byname[g] then
            return false, e:append("duplicate chroot group name: %s", g)
        end
        info.chroot.groups_byname[g] = grp
    end
    table.sort(info.chroot.groups_sorted)
    strict.lock(info.chroot.groups_sorted)
    strict.lock(info.chroot.default_groups)
    return true
end

--- Gather source paths.
-- @param info Info table.
-- @param basedir Nil or directory from where to start scanning for more
--                sources. Only for recursion.
-- @param sources Nil or table of source paths. Only for recursion.
-- @return Table with source paths, or false on error.
-- @return Error object on failure.
local function gather_source_paths(info, basedir, sources)
    sources = sources or {}

    local currdir = e2tool.sourcedir(basedir, info.root)
    for entry, re in e2lib.directory(currdir) do
        if not entry then
            return false, re
        end

        if basedir then
            entry = e2lib.join(basedir, entry)
        end

        local sdir = e2tool.sourcedir(entry, info.root)
        local sconfig = e2tool.sourceconfig(entry, info.root)
        local s = e2lib.stat(sdir, false)
        if s.type == "directory" then
            if e2lib.exists(sconfig) then
                table.insert(sources, entry)
            else
                -- try subfolder
                local rc, re = gather_source_paths(info, entry, sources)
                if not rc then
                    return false, re
                end
            end
        end
    end

    return sources
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

--- Load all source configs. Creates and populates the info.sources dictionary.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function load_source_configs(info)
    local e = err.new("error loading source configuration")
    info.sources = {}

    local sources, re = gather_source_paths(info)
    if not sources then
        return false, e:cat(re)
    end

    for _,src in ipairs(sources) do
        local list, re
        local path = e2tool.sourceconfig(src, info.root)
        local types = { "e2source", }
        local rc, re = e2tool.verify_src_res_pathname_valid_chars(src)
        if not rc then
            e:append("invalid source file name: %s", src)
            e:cat(re)
            return false, e
        end

        list, re = load_user_config2(info, path, types)
        if not list then
            return false, e:cat(re)
        end


        for _,item in ipairs(list) do
            local name = item.data.name
            item.data.directory = src
            if not name and #list == 1 then
                e2lib.warnf("WDEFAULT", "`name' attribute missing in source config.")
                e2lib.warnf("WDEFAULT", " Defaulting to directory name")
                item.data.name = e2tool.src_res_path_to_name(src)
                name = item.data.name
            end

            if not name then
                return false, e:append("`name' attribute missing in source config")
            end

            local rc, re = e2tool.verify_src_res_name_valid_chars(name)
            if not rc then
                e:append("invalid source name: %s", name)
                e:cat(re)
                return false, e
            end

            if info.sources[name] then
                return false, e:append("duplicate source: %s", name)
            end

            info.sources[name] = item.data
        end
    end
    return true
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
    return e2lib.join(e2tool.resultdir(name, prefix), "config")
end

--- Get project-relative path to the result build-script
-- @param name Result path compnent name.
-- @param prefix Optional prefix path.
-- @return Path to the result build-script.
function e2tool.resultbuildscript(name, prefix)
    return e2lib.join(e2tool.resultdir(name, prefix), "build-script")
end

--- Get project-relative path to the source config.
-- @param name Source path component.
-- @param prefix Optional prefix path.
-- @return Path to the sourceconfig.
function e2tool.sourceconfig(name, prefix)
    return e2lib.join(e2tool.sourcedir(name, prefix), "config")
end

--- Gather result paths.
-- @param info Info table.
-- @param basedir Nil or directory from where to start scanning for more
--                results. Only for recursion.
-- @param results Nil or table of result paths. Only for recursion.
-- @return Table with result paths, or false on error.
-- @return Error object on failure.
local function gather_result_paths(info, basedir, results)
    results = results or {}

    local currdir = e2tool.resultdir(basedir, info.root)
    for entry, re in e2lib.directory(currdir) do
        if not entry then
            return false, re
        end

        if basedir then
            entry = e2lib.join(basedir, entry)
        end

        local resdir = e2tool.resultdir(entry, info.root)
        local resconfig = e2tool.resultconfig(entry, info.root)
        local s = e2lib.stat(resdir, false)
        if s.type == "directory" then
            if e2lib.exists(resconfig) then
                table.insert(results, entry)
            else
                -- try subfolder
                local rc, re = gather_result_paths(info, entry, results)
                if not rc then
                    return false, re
                end
            end
        end
    end

    return results
end

--- Load all result configs. Creates and populates the info.results dictionary.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function load_result_configs(info)
    local e = err.new("error loading result configuration")
    info.results = {}

    local results, re = gather_result_paths(info)
    if not results then
        return false, e:cat(re)
    end

    for _,res in ipairs(results) do
        local list, re
        local path = e2tool.resultconfig(res, info.root)
        local types = { "e2result", }

        local rc, re = e2tool.verify_src_res_pathname_valid_chars(res)
        if not rc then
            e:append("invalid result file name: %s", res)
            e:cat(re)
            return false, e
        end

        list, re = load_user_config2(info, path, types)
        if not list then
            return false, e:cat(re)
        end
        if #list ~= 1 then
            return false, e:append("%s: only one result allowed per config file",
            path)
        end
        for _,item in ipairs(list) do
            local name = item.data.name
            item.data.directory = res

            if name and name ~= res then
                e:append("`name' attribute does not match configuration path")
                return false, e
            end

            item.data.name = e2tool.src_res_path_to_name(res)
            name = item.data.name

            local rc, re = e2tool.verify_src_res_name_valid_chars(name)
            if not rc then
                e:append("invalid result name: %s",name)
                e:cat(re)
                return false, e
            end

            if info.results[name] then
                return false, e:append("duplicate result: %s", name)
            end

            info.results[name] = item.data
        end
    end
    return true
end

--- Read project configuration file.
-- @return True on success, false on error.
-- @return Error object on failure.
local function read_project_config(info)

    --- Project configuration table (e2project).
    -- @table info.project
    -- @field release_id Release identifier, usually a git tag (string).
    -- @field name Name of project (string).
    -- @field deploy_results List of results that should be archived on
    --                       --release builds (table containing strings).
    -- @field default_results List of results that are built by default
    --                        (table containing strings).
    -- @field chroot_arch Chroot architecture (string).

    local rc, re

    local rc, re = load_user_config(info, e2lib.join(info.root, "proj/config"),
        info, "project", "e2project")
    if not rc then
        return false, re
    end

    local e = err.new("in project configuration:")
    if not info.project.release_id then
        e:append("key is not set: release_id")
    end
    if not info.project.name then
        e:append("key is not set: name")
    end
    if not info.project.default_results then
        e2lib.warnf("WDEFAULT", "in project configuration:")
        e2lib.warnf("WDEFAULT",
            "default_results is not set. Defaulting to empty list.")
        info.project.default_results = {}
    end
    rc, re = e2lib.vrfy_listofstrings(info.project.deploy_results,
        "deploy_results", true, true)
    if not rc then
        e:append("deploy_results is not a valid list of strings")
        e:cat(re)
    end
    rc, re = e2lib.vrfy_listofstrings(info.project.default_results,
        "default_results",  true, false)
    if not rc then
        e:append("default_results is not a valid list of strings")
        e:cat(re)
    end
    if not info.project.chroot_arch then
        e2lib.warnf("WDEFAULT", "in project configuration:")
        e2lib.warnf("WDEFAULT", " chroot_arch defaults to x86_32")
        info.project.chroot_arch = "x86_32"
    end
    if not info.chroot_call_prefix[info.project.chroot_arch] then
        e:append("chroot_arch is set to an invalid value")
    end
    local host_system_arch, re = e2lib.get_sys_arch()
    if not host_system_arch then
        e:cat(re)
    elseif info.project.chroot_arch == "x86_64" and
        host_system_arch ~= "x86_64" then
        e:append("running on x86_32: switching to x86_64 mode is impossible.")
    end
    if e:getcount() > 1 then
        return false, e
    end

    return true
end

--- check chroot config
-- @param chroot
-- @return bool
-- @return an error object on failure
local function check_chroot_config(info)
    local e = err.new("error validating chroot configuration")
    local grp

    for _,cgrpnm in ipairs(info.chroot.groups_sorted) do
        grp = info.chroot.groups_byname[cgrpnm]
        if not grp.server then
            e:append("in group: %s", grp.name)
            e:append(" `server' attribute missing")
        elseif not cache.valid_server(info.cache, grp.server) then
            e:append("in group: %s", grp.name)
            e:append(" no such server: %s", grp.server)
        end
        if (not grp.files) or (#grp.files) == 0 then
            e:append("in group: %s", grp.name)
            e:append(" list of files is empty")
        else
            for _,f in ipairs(grp.files) do
                local inherit = {
                    server = grp.server,
                }
                local keys = {
                    server = {
                        mandatory = true,
                        type = "string",
                        inherit = true,
                    },
                    location = {
                        mandatory = true,
                        type = "string",
                        inherit = false,
                    },
                    sha1 = {
                        mandatory = false,
                        type = "string",
                        inherit = false,
                    },
                }
                local rc, re = e2lib.vrfy_table_attributes(f, keys, inherit)
                if not rc then
                    e:append("in group: %s", grp.name)
                    e:cat(re)
                end
                if f.server ~= info.root_server_name and not f.sha1 then
                    e:append("in group: %s", grp.name)
                    e:append("file entry for remote file without `sha1` attribute")
                end
            end
        end
    end
    if #info.chroot.default_groups == 0 then
        e:append(" `default_groups' attribute is missing or empty list")
    else
        for _,g in ipairs(info.chroot.default_groups) do
            if not info.chroot.groups_byname[g] then
                e:append(" unknown group in default groups list: %s", g)
            end
        end
    end
    if e:getcount() > 1 then
        return false, e
    end
    return true
end

--- check source.
local function check_source(info, sourcename)
    local src = info.sources[sourcename]
    local rc, e, re
    if not src then
        e = err.new("no source by that name: %s", sourcename)
        return false, e
    end
    local e = err.new("in source: %s", sourcename)
    if not src.type then
        e2lib.warnf("WDEFAULT", "in source %s", sourcename)
        e2lib.warnf("WDEFAULT", " type attribute defaults to `files'")
        src.type = "files"
    end
    rc, re = scm.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    return true
end

--- check sources.
local function check_sources(info)
    local e = err.new("Error while checking sources")
    local rc, re
    for n,s in pairs(info.sources) do
        rc, re = check_source(info, n)
        if not rc then
            e:cat(re)
        end
    end
    if e:getcount() > 1 then
        return false, e
    end
    return true
end

--- Checks project information for consistancy.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function check_project_info(info)
    local rc, re
    local e = err.new("error in project configuration")
    rc, re = check_chroot_config(info)
    if not rc then
        return false, e:cat(re)
    end
    local rc, re = check_sources(info)
    if not rc then
        return false, e:cat(re)
    end
    local rc, re = check_results(info)
    if not rc then
        return false, e:cat(re)
    end
    for _, r in ipairs(info.project.default_results) do
        if not info.results[r] then
            e:append("default_results: No such result: %s", r)
        end
    end
    for _, r in ipairs(info.project.deploy_results) do
        if not info.results[r] then
            e:append("deploy_results: No such result: %s", r)
        end
    end
    if e:getcount() > 1 then
        return false, e
    end
    local rc = e2tool.dsort(info)
    if not rc then
        return false, e:cat("cyclic dependencies")
    end
    return true
end

--- collect project info.
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

    local rc, re = opendebuglogfile(info)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.logf(4, "VERSION:       %s", buildconfig.VERSION)
    e2lib.logf(4, "VERSIONSTRING: %s", buildconfig.VERSIONSTRING)

    hash.hcache_load(e2lib.join(info.root, ".e2/hashcache"))
    -- no error check required

    --XXX create some policy module where the following policy settings
    --XXX and functions reside (server names, paths, etc.)

    -- the '.' server as url
    info.root_server = "file://" .. info.root
    info.root_server_name = "."

    -- the proj_storage server is equivalent to
    --  info.default_repo_server:info.project-locaton
    info.proj_storage_server_name = "proj-storage"

    -- need to configure the results server in the configuration, named 'results'
    info.result_server_name = "results"

    info.default_repo_server = "projects"
    info.default_files_server = "upstream"

    -- prefix the chroot call with this tool (switch to 32bit on amd64)
    -- XXX not in buildid, as it is filesystem location dependent...
    info.chroot_call_prefix = {}
    info.chroot_call_prefix["x86_32"] =
        e2lib.join(info.root, ".e2/bin/e2-linux32")
    -- either we are on x86_64 or we are on x86_32 and refuse to work anyway
    -- if x86_64 mode is requested.
    info.chroot_call_prefix["x86_64"] = ""

    if e2option.opts["check"] then
        local f = e2lib.join(info.root, e2lib.globals.e2version_file)
        local v, re = e2lib.parse_e2versionfile(f)
        if not v then
            return false, re
        end

        if v.tag == "^" then
            return false, err.new("local tool version is not configured to " ..
                "a fixed tag\nfix you configuration in %s before running " ..
                "e2factory in release mode", f)
        elseif v.tag ~= buildconfig.VERSIONSTRING then
            return false, err.new("local tool version does not match the " ..
                "version configured\n in `%s`\n local tool version is %s\n" ..
                "required version is %s", f, buildconfig.VERSIONSTRING, v.tag)
        end
    end

    info.sources = {}

    -- read environment configuration
    info.env = {}		-- global and result specfic env (deprecated)
    info.env_files = {}   -- a list of environment files
    info.global_env = environment.new()
    info.result_env = {} -- result specific env only
    local rc, re = load_env_config(info, "proj/env")
    if not rc then
        return false, e:cat(re)
    end

    -- read project configuration
    rc, re = read_project_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- chroot config
    rc, re = read_chroot_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- licences
    rc, re = licence.load_licence_config(info)
    if not rc then
        return false, e:cat(re)
    end

    -- sources
    rc, re = load_source_configs(info)
    if not rc then
        return false, e:cat(re)
    end

    -- results
    rc, re = load_result_configs(info)
    if not rc then
        return false, e:cat(re)
    end

    -- distribute result specific environment to the results,
    -- provide environment for all results, even if it is empty
    for r, res in pairs(info.results) do
        if not info.result_env[r] then
            info.result_env[r] = environment.new()
        end
        res._env = info.result_env[r]
    end

    -- check for environment for non-existent results
    for r, t in pairs(info.result_env) do
        if not info.results[r] then
            e:append("configured environment for non existent result: %s", r)
        end
    end
    if e:getcount() > 1 then
        return false, e
    end

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

    info.cache, re = e2lib.setup_cache()
    if not info.cache then
        return false, e:cat(re)
    end
    rc = cache.new_cache_entry(info.cache, info.root_server_name,
        info.root_server, { writeback=true },  nil, nil )
    rc = cache.new_cache_entry(info.cache, info.proj_storage_server_name,
        nil, nil, info.default_repo_server, info.project_location)

    --e2tool.add_source_results(info)

    -- provide a sorted list of results
    info.results_sorted = {}
    for r,res in pairs(info.results) do
        table.insert(info.results_sorted, r)
    end
    table.sort(info.results_sorted)

    -- provided sorted list of sources
    info.sources_sorted = {}
    for s,src in pairs(info.sources) do
        table.insert(info.sources_sorted, s)
    end
    table.sort(info.sources_sorted)

    rc, re = policy.init(info)
    if not rc then
        return false, e:cat(re)
    end

    if e2option.opts["check"] then
        local dirty, mismatch

        rc, re, mismatch = generic_git.verify_head_match_tag(info.root,
            info.project.release_id)
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
            e2lib.join(info.root, ".git"), info.project.release_id)
        if not rc then
            e:append("verifying remote tag failed")
            return false, e:cat(re)
        end
    end

    for _,f in ipairs(e2tool_ftab.collect_project_info) do
        rc, re = f(info)
        if not rc then
            return false, e:cat(re)
        end
    end

    rc, re = check_project_info(info)
    if not rc then
        return false, re
    end

    return info
end

--- Returns a sorted vector with all dependencies for the given result
-- in the project. The result itself is excluded.
-- @param info Info table.
-- @param resultname Result name.
-- @return Sorted vector of result dependencies.
function e2tool.dlist(info, resultname)
    local t = {}
    for _,f in ipairs(e2tool_ftab.dlist) do
        local deps = f(info, resultname)
        for _,d in ipairs(deps) do
            table.insert(t, d)
        end
    end
    return t
end

--- Returns a sorted vector with all depdencies of result, and all
-- the indirect dependencies. If result is a vector, calculates dependencies
-- for all results and includes those from result. If result is a result name,
-- calculates its dependencies but does not include the result itself.
-- @param info Info table
-- @param result Vector of result names or single result name.
-- @return Vector of dependencies of the result, may or may not include result.
--         False on failure.
-- @return Error object on failure
-- @see e2tool.dlist
function e2tool.dlist_recursive(info, result)
    local rc, re
    local had = {}
    local path = {}
    local col = {}
    local t = {}

    if type(result) == "string" then
        result = e2tool.dlist(info, result)
    end

    local function visit(res)
        if had[res] then
            return false,
                err.new("cyclic dependency: %s", table.concat(path, " "))
        elseif not col[res] then
            table.insert(path, res)
            had[res] = true
            col[res] = true
            for _, d in ipairs(e2tool.dlist(info, res)) do
                rc, re = visit(d)
                if not rc then
                    return false, re
                end
            end
            table.insert(t, res)
            had[res] = nil
            path[#path] = nil
        end
        return true
    end

    for _, r in ipairs(result) do
        rc, re = visit(r)
        if not rc then
            return false, re
        end
    end

    return t
end

--- Calls dlist_recursive() with the default results vector of the project.
-- @param info Info table.
-- @return Vector of results in topological order, or false on error.
-- @return Error object on failure.
-- @see e2tool.dlist_recursive
function e2tool.dsort(info)
    return e2tool.dlist_recursive(info, info.project.default_results)
end

--- verify that a file addressed by server name and location matches the
-- checksum given in the sha1 parameter.
-- @param info info structure
-- @param server the server name
-- @param location file location relative to the server
-- @param sha1 string: the hash to verify against
-- @return bool true if verify succeeds, false otherwise
-- @return Error object on failure.
function e2tool.verify_hash(info, server, location, sha1)
    local rc, re
    local e = err.new("error verifying checksum")
    local is_sha1, re = e2tool.fileid(info, {server=server, location=location})
    if not is_sha1 then
        return false, e:cat(re)
    end
    if is_sha1 ~= sha1 then
        e = err.new("checksum mismatch in file:")
        return false, e:append("%s:%s", server, location)
    end
    e2lib.logf(4, "checksum matches: %s:%s", server, location)
    return true
end

--- Cache for projid() result.
local projid_cache = false

--- Calculate the Project ID. The Project ID consists of files in proj/init
-- as well as some keys from proj/config and buildconfig. Returns a cached
-- value after the first call.
-- @return Project ID or false on error.
-- @return Error object on failure
local function projid(info)
    local rc, re, hc, cs

    if projid_cache then
        return projid_cache
    end

    -- catch proj/init/*
    hc, re = hash.hash_start()
    if not hc then return false, re end

    for f, re in e2lib.directory(e2lib.join(info.root, "proj/init")) do
        if not f then
            return false, re
        end

        local location, file, fileid
        if not e2lib.is_backup_file(f) then
            location = e2lib.join("proj/init", f)
            file = {
                server = info.root_server_name,
                location = location,
            }

            fileid, re = e2tool.fileid(info, file)
            if not fileid then
                return false, re
            end

            rc, re = hash.hash_line(hc, location)   -- the filename
            if not rc then return false, re end

            rc, re = hash.hash_line(hc, fileid)     -- the file content cs
            if not rc then return false, re end
        end
    end
    rc, re = hash.hash_line(hc, info.project.release_id)
    if not rc then return false, re end
    rc, re = hash.hash_line(hc, info.project.name)
    if not rc then return false, re end
    rc, re = hash.hash_line(hc, info.project.chroot_arch)
    if not rc then return false, re end
    rc, re = hash.hash_line(hc, buildconfig.VERSION)
    if not rc then return false, re end

    cs, re = hash.hash_finish(hc)
    if not cs then return false, re end

    projid_cache = cs

    return cs
end

--- verify that remote files match the checksum. The check is skipped when
-- check-remote is not enabled or cache is not enabled.
-- @param info
-- @param file table: file table from configuration
-- @param fileid string: hash to verify against
-- @return bool
-- @return an error object on failure
local function verify_remote_fileid(info, file, fileid)
    local rc, re, hc
    local e = err.new("error calculating remote file id for file: %s:%s",
    file.server, file.location)
    if not cache.cache_enabled(info.cache, file.server) or
        not e2option.opts["check-remote"] then
        e2lib.logf(4, "checksum for remote file %s:%s skip verifying",
        file.server, file.location)
        return true
    end
    local surl, re = cache.remote_url(info.cache, file.server, file.location)
    if not surl then
        return false, e:cat(re)
    end
    local u, re = url.parse(surl)
    if not u then
        return false, e:cat(re)
    end

    local remote_fileid = ""

    if u.transport == "ssh" or u.transport == "scp" or
        u.transport == "rsync+ssh" then
        local argv, stdout, dt, sha1sum_remote

        sha1sum_remote =  { "sha1sum", e2lib.join("/", u.path) }
        rc, re, stdout = e2lib.ssh_remote_cmd(u, sha1sum_remote)
        if not rc then
            return false, e:cat(re)
        end

        dt, re = digest.parsestring(stdout)
        if not dt then
            return false, e:cat(re)
        end

        for k,dt_entry in ipairs(dt) do
            if dt_entry.name == e2lib.join("/", u.path) then
                remote_fileid = dt_entry.checksum
                break;
            end
        end

        if #remote_fileid ~= digest.SHA1_LEN then
            return false,
                e:cat(err.new("Could not extract digest from digest table"))
        end
    elseif u.transport == "file" then
        remote_fileid, re = hash.hash_file_once(e2lib.join("/", u.path))
        if not remote_fileid then
            return false, e:cat(re)
        end
    elseif u.transport == "http" or u.transport == "https" then
        local ce, re = cache.ce_by_server(info.cache, file.server)
        if not ce then
            return false, e:cat(re)
        end

        local tmpfile, re = e2lib.mktempfile()
        if not tmpfile then
            return false, e:cat(re)
        end

        rc, re = transport.fetch_file(ce.remote_url, file.location,
            e2lib.dirname(tmpfile), e2lib.basename(tmpfile))
        if not rc then
            return false, e:cat(re)
        end

        remote_fileid, re = hash.hash_file_once(tmpfile)
        if not remote_fileid then
            return false, e:cat(re)
        end

        e2lib.rmtempfile(tmpfile)
    else
        return false, err.new("verify remote fileid: transport not supported: %s",
            u.transport)
    end
    if fileid ~= remote_fileid then
        return false, err.new(
        "checksum for remote file %s:%s (%s) does not match" ..
        " configured checksum (%s)",
        file.server, file.location, remote_fileid, fileid)
    end
    e2lib.logf(4, "checksum for remote file %s:%s matches (%s)",
    file.server, file.location, fileid)
    return true
end

--- calculate a representation for file content. The name and location
-- attributes are not included.
-- @param info info table
-- @param file table: file table from configuration
-- @return fileid string: hash value, or false on error.
-- @return an error object on failure
function e2tool.fileid(info, file)
    local rc, re, e, fileid, path
    local cache_flags = { cache = true }

    e = err.new("error calculating file id for file: %s:%s",
        file.server, file.location)

    if file.sha1 then
        fileid = file.sha1
    else
        rc, re = cache.cache_file(info.cache, file.server,
            file.location, cache_flags)
        if not rc then
            return false, e:cat(re)
        end

        path, re = cache.file_path(info.cache, file.server,
            file.location, cache_flags)
        if not path then
            return false, e:cat(re)
        end

        fileid, re = hash.hash_file_once(path)
        if not fileid then
            return false, e:cat(re)
        end
    end

    rc, re = verify_remote_fileid(info, file, fileid)
    if not rc then
        return false, e:cat(re)
    end

    return fileid
end

--- return the first eight digits of buildid hash
-- @param buildid string: hash value
-- @return string: a short representation of the hash value
function e2tool.bid_display(buildid)
    return string.format("%s...", string.sub(buildid, 1, 8))
end

--- Get the buildid for a result, calculating it if required.
-- @param info Info table.
-- @param resultname Result name.
-- @return Build ID or false on error
-- @return Error object on failure
function e2tool.buildid(info, resultname)
    local r = info.results[resultname]
    local id, e = e2tool.pbuildid(info, resultname)
    if not id then
        return false, e
    end
    local hc = hash.hash_start()
    hash.hash_line(hc, r.pbuildid)
    r.buildid = hash.hash_finish(hc)
    return r.build_mode.buildid(r.buildid)
end

--- chroot group id.
-- @param info Info table.
-- @param groupname
-- @return Chroot group ID or false on error.
-- @return Error object on failure.
local function chrootgroupid(info, groupname)
    local e = err.new("calculating chroot group id failed for group %s",
        groupname)
    local g = info.chroot.groups_byname[groupname]
    if g.groupid then
        return g.groupid
    end
    local hc = hash.hash_start()
    hash.hash_line(hc, g.name)
    for _,f in ipairs(g.files) do
        hash.hash_line(hc, f.server)
        hash.hash_line(hc, f.location)
        local fileid, re = e2tool.fileid(info, f)
        if not fileid then
            return false, e:cat(re)
        end
        hash.hash_line(hc, fileid)
    end
    g.groupid = hash.hash_finish(hc)
    return g.groupid
end

--- envid: calculate a value represennting the environment for a result
-- @param info the info table
-- @param resultname string: name of a result
-- @return string: envid value
local function envid(info, resultname)
    return e2tool.env_by_result(info, resultname):id()
end

--- Get the project-wide buildid for a result, calculating it if required.
-- @param info
-- @param resultname
-- @return Build ID or false on error.
-- @return Error object on failure.
function e2tool.pbuildid(info, resultname)
    local e = err.new("error calculating result id for result: %s",
        resultname)
    local r = info.results[resultname]
    if r.pbuildid then
        return r.build_mode.buildid(r.pbuildid)
    end
    local hc = hash.hash_start()

    hash.hash_line(hc, r.name)

    for _,s in ipairs(r.sources) do
        local src = info.sources[s]
        local source_set = r.build_mode.source_set()
        local rc, re, sourceid = scm.sourceid(info, s, source_set)
        if not rc then
            return false, e:cat(re)
        end
        hash.hash_line(hc, s)			-- source name
        hash.hash_line(hc, sourceid)		-- sourceid
    end
    for _,d in ipairs(r.depends) do
        hash.hash_line(hc, d)			-- dependency name
    end

    if r.chroot then
        for _,g in ipairs(r.chroot) do
            local groupid, re = chrootgroupid(info, g)
            if not groupid then
                return false, e:cat(re)
            end
            hash.hash_line(hc, g)
            hash.hash_line(hc, groupid)
        end
    end
    r.envid = envid(info, resultname)
    hash.hash_line(hc, r.envid)

    local location = e2tool.resultbuildscript(info.results[resultname].directory)
    local f = {
        server = info.root_server_name,
        location = location,
    }
    local fileid, re = e2tool.fileid(info, f)
    if not fileid then
        return false, e:cat(re)
    end
    hash.hash_line(hc, fileid)			-- build script hash

    for _,f in ipairs(e2tool_ftab.resultid) do
        local rhash, re = f(info, resultname)
        -- nil -> error
        -- false -> don't modify the hash
        if rhash == nil then
            return false, e:cat(re)
        elseif rhash ~= false then
            hash.hash_line(hc, rhash)
        end
    end
    r.resultid = hash.hash_finish(hc)	-- result id (without deps)

    local projid, re = projid(info)
    if not projid then
        return false, e:cat(re)
    end
    hc = hash.hash_start()
    hash.hash_line(hc, projid)		-- project id
    hash.hash_line(hc, r.resultid)	-- result id
    for _,d in ipairs(r.depends) do
        local id, re = e2tool.pbuildid(info, d)
        if not id then
            return false, re
        end
        hash.hash_line(hc, id)		-- buildid of dependency
    end
    for _,f in ipairs(e2tool_ftab.pbuildid) do
        local rhash, re = f(info, resultname)
        -- nil -> error
        -- false -> don't modify the hash
        if rhash == nil then
            return false, e:cat(re)
        elseif rhash ~= false then
            hash.hash_line(hc, rhash)
        end
    end
    r.pbuildid = hash.hash_finish(hc)	-- buildid (with deps)
    return r.build_mode.buildid(r.pbuildid)
end

--- return a table of environment variables valid for a result
-- @param info the info table
-- @param resultname string: name of a result
-- @return table: environment variables valid for the result
function e2tool.env_by_result(info, resultname)
    local res = info.results[resultname]
    local env = environment.new()
    env:merge(info.global_env, false)
    for _, s in ipairs(res.sources) do
        env:merge(info.sources[s]._env, true)
    end
    env:merge(res._env, true)
    return env
end

--- select results based upon a list of results usually given on the
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
    local rc, re, res

    for _,r in ipairs(results) do
        rc, re = e2tool.verify_src_res_name_valid_chars(r)
        if not rc then
            return false, err.new("'%s' is not a valid result name", r)
        end

        res = info.results[r]
        if not res then
            return false, err.new("selecting invalid result: %s", r)
        end
        res.selected = true
        res.force_rebuild = force_rebuild
        res.keep_chroot = keep_chroot
        if build_mode then
            res.build_mode = build_mode
        end
        res.playground = playground
    end

    return true
end

--- print selection status for a list of results
-- @param info
-- @param results table: list of result names
-- @return bool
-- @return an error object on failure
function e2tool.print_selection(info, results)
    for _,r in ipairs(results) do
        local e = err.new("error printing selected results")
        local res = info.results[r]
        if not res then
            return false, e:append("no such result: %s", r)
        end
        local s = res.selected and "[ selected ]" or "[dependency]"
        local f = res.force_rebuild and "[force rebuild]" or ""
        local p = res.playground and "[playground]" or ""
        e2lib.logf(3, "Selected result: %-20s %s %s %s", r, s, f, p)
    end
    return true
end

--- register collect project info.
function e2tool.register_collect_project_info(info, func)
    if type(info) ~= "table" or type(func) ~= "function" then
        return false, err.new("register_collect_project_info: invalid argument")
    end
    table.insert(e2tool_ftab.collect_project_info, func)
    return true
end

--- register check result.
function e2tool.register_check_result(info, func)
    if type(info) ~= "table" or type(func) ~= "function" then
        return false, err.new("register_check_result: invalid argument")
    end
    table.insert(e2tool_ftab.check_result, func)
    return true
end

--- register resultid.
function e2tool.register_resultid(info, func)
    if type(info) ~= "table" or type(func) ~= "function" then
        return false, err.new("register_resultid: invalid argument")
    end
    table.insert(e2tool_ftab.resultid, func)
    return true
end

--- register project buildid.
function e2tool.register_pbuildid(info, func)
    if type(info) ~= "table" or type(func) ~= "function" then
        return false, err.new("register_pbuildid: invalid argument")
    end
    table.insert(e2tool_ftab.pbuildid, func)
    return true
end

--- register dlist.
function e2tool.register_dlist(info, func)
    if type(info) ~= "table" or type(func) ~= "function" then
        return false, err.new("register_dlist: invalid argument")
    end
    table.insert(e2tool_ftab.dlist, func)
    return true
end

--- Function table, driving the build process. Contains further tables to
-- which e2factory core and plugins add functions that comprise the
-- build process.
-- @field collect_project_info Called f(info). Populates the info table,
--                             not to be confused with the "collect_project"
--                             feature.
-- @field check_result Called f(info, resultname).
-- @field resultid Called f(info, resultname).
--        Returns nil on error, false to skip, or a resultid string.
-- @field pbuildid Called f(info, resultname).
-- @field dlist Called f(info, resultname).
e2tool_ftab = {
    collect_project_info = {},
    check_result = {},
    resultid = {},
    pbuildid = {},
    dlist = {},
}

strict.lock(e2tool_ftab)

return strict.lock(e2tool)

-- vim:sw=4:sts=4:et:
