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

local e2build = {}
local transport = require("transport")
local tools = require("tools")
local err = require("err")
local e2lib = require("e2lib")
local scm = require("scm")
local environment = require("environment")
local e2tool = require("e2tool")
local strict = require("strict")

-- table of functions to drive the build process
-- forward declaration, filled at the end of file
local build_process = {}

local function linklast(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("creating link to last results")
    -- calculate the path to the result
    local server, location = res.build_mode.storage(info.project_location,
    info.release_id)
    local location1 = string.format("%s/%s/%s", location, r,
    res.build_mode.buildid(res.buildid))
    local cache_flags = {
        check_only = true
    }
    local dst, re = info.cache:file_path(server, location1, cache_flags)
    if not dst then
        return false, e:cat(re)
    end
    -- create the last link
    local lnk_location = string.format("out/%s/last", r)
    local lnk, re = info.cache:file_path(info.root_server_name, lnk_location)
    if not lnk then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir(e2lib.dirname(lnk), "-p")  -- create the directory
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.rm(lnk, "-f")			-- remove the old link
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.symlink(dst, lnk)		-- create the new link
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

-- return true if the result given in c is already available, false otherwise
-- return the path to the result
-- check if a result is already available
-- @param info
-- @param r string: result name
-- @param return_flags table: return values through this table
-- @return bool
-- @return an error object on failure
local function result_available(info, r, return_flags)
    e2lib.log(4, string.format("result_available(%s)", tostring(r)))
    local res = info.results[r]
    local mode = res.build_mode
    local buildid = res.build_mode.buildid(e2tool.buildid(info, r))
    local sbid = e2tool.bid_display(buildid)
    local rc, re
    local e = err.new("error while checking if result is available: %s", r)
    local columns = tonumber(e2lib.globals.osenv["COLUMNS"])
    if res.playground then
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", r),
        columns, string.format("[%s] [playground]", sbid))
        return_flags.stop = false
        return true, nil
    end
    if res.build_mode.source_set() == "working-copy" or
        res.force_rebuild == true then
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", r),
        columns, string.format("[%s]", sbid))
        return_flags.stop = false
        return true, nil
    end
    local server, location = mode.storage(info.project_location, info.release_id)
    local dep_set = mode.buildid(e2tool.buildid(info, r))
    -- cache the result
    local result_location = string.format("%s/%s/%s/result.tar", location, r,
    dep_set)
    local cache_flags = {}
    rc, re = info.cache:cache_file(server, result_location, cache_flags)
    if not rc then
        e2lib.log(3, "caching result failed")
        -- ignore
    end
    local cache_flags = {}
    local path, re = info.cache:file_path(server, result_location, cache_flags)
    rc = e2lib.isfile(path)
    if not rc then
        -- result is not available. Build.
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", r),
        columns, string.format("[%s]", sbid))
        return_flags.stop = false
        return true, nil
    end
    e2lib.log(3, "result is available locally")
    --[[
    rc, re = update_result_timestamp(info, server, location)
    if not rc then
    return false, e:cat(re)
    end
    -- and push the updated metadata to the server again, if the result
    -- exists on the server.
    ]]
    rc, re = linklast(info, r, return_flags)
    if not rc then
        return false, e:cat(re)
    end
    -- return true
    return_flags.message = e2lib.align(columns,
    0, string.format("skipping %-20s", r),
    columns, string.format("[%s]", sbid))
    return_flags.stop = true
    return true, nil
end

--- build config
-- @class table
-- @name build config
-- @field mode       table:  the build mode policy
-- @field release id string: the release name
-- @field info       table: the info table
-- @field base       string: path to the build directory
-- @field c	     string: path to the chroot
-- @field chroot_marker string: path to chroot marker file
-- @field T          string: absolute path to the temporary build directory
--                           inside chroot
-- @field Tc         string: same as c.T but relative to c
-- @field strict     bool:   pseudo tag "^" not allowed when true
-- @field r          string: result name
-- @field buildlog   string: build log file
-- @field buildid    string: build id
-- @field groups     table of strings: chroot groups

--- generate build_config and store in res.build_config
-- @param info
-- @param r string: result name
-- @return bool
-- @return an error object on failure
function e2build.build_config(info, r)
    e2lib.log(4, string.format("build_config(%s, %s)",
    tostring(info), tostring(r)))
    local e = err.new("setting up build configuration for result `%s' failed",
    r)
    local res = info.results[r]
    if not res then
        return false, e:append("no such result: %s", r)
    end
    local buildid, re = e2tool.buildid(info, r)
    if not buildid then
        return false, e:cat(re)
    end
    res.build_config = {} -- build up a new build config
    local tab = res.build_config
    local tmpdir = string.format("%s/e2factory-%s.%s.%s-build/%s",
    e2lib.globals.tmpdir,
    buildconfig.MAJOR, buildconfig.MINOR, buildconfig.PATCHLEVEL,
    e2lib.globals.username)
    local project = info.name
    local builddir = "tmp/e2"
    tab.mode = nil -- XXX
    tab.location = nil -- XXX info.project_location
    tab.release_id = nil -- XXX release_id
    tab.base = string.format("%s/%s/%s", tmpdir, project, r)
    tab.c = string.format("%s/chroot", tab.base)
    tab.chroot_marker = string.format("%s/e2factory-chroot", tab.base)
    tab.chroot_lock = string.format("%s/e2factory-chroot-lock", tab.base)
    tab.T = string.format("%s/%s/%s/chroot/%s", tmpdir, project, r, builddir)
    tab.Tc = string.format("/%s", builddir)
    tab.r = string.format("%s", r)
    tab.chroot_call_prefix = info.chroot_call_prefix[info.project.chroot_arch]
    tab.buildlog = string.format("%s/log/build.%s.log", info.root, r)
    tab.scriptdir = "script"
    tab.build_driver = ""
    tab.build_driver_file = string.format("build-driver")
    tab.buildrc_file = string.format("buildrc")
    tab.buildrc_noinit_file = string.format("buildrc-noinit")
    tab.profile = string.format("/tmp/bashrc")
    tab.builtin_env = environment.new()
    tab.builtin_env:set("E2_BUILD_NUMBER", res.buildno)
    tab.builtin_env:set("E2_TMPDIR", res.build_config.Tc)
    tab.builtin_env:set("E2_RESULT", r)
    tab.builtin_env:set("E2_RELEASE_ID", info.project.release_id)
    tab.builtin_env:set("E2_PROJECT_NAME", info.project.name)
    tab.builtin_env:set("E2_BUILDID", buildid)
    tab.builtin_env:set("T", res.build_config.Tc)
    tab.builtin_env:set("r", r)
    tab.builtin_env:set("R", r)
    tab.env = e2tool.env_by_result(info, r)
    e2lib.logf(4, "build config for result %s: ", r)
    for k,v in pairs(tab) do
        v = tostring(v)
        e2lib.log(4, string.format("\t%-10s = %s", k, v))
    end
    tab.groups = {}
    for _,g in ipairs(res.chroot) do
        tab.groups[g] = true
    end
    return tab
end

local function chroot_lock(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("error locking chroot")
    rc, re = e2lib.mkdir(res.build_config.c, "-p")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.globals.lock:lock(res.build_config.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

local function chroot_unlock(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("error unlocking chroot")
    rc, re = e2lib.globals.lock:unlock(res.build_config.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

local function setup_chroot(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("error setting up chroot")
    -- create the chroot path and create the chroot marker file without root
    -- permissions. That makes sure we have write permissions here.
    rc, re = e2lib.mkdir(res.build_config.c, "-p")
    if not rc then
        return false, e:cat(re)
    end
    local rc, re = e2lib.touch(res.build_config.chroot_marker)
    if not rc then
        return false, e:cat(re)
    end

    e2tool.set_umask(info)
    local rc, re = e2lib.e2_su_2_2({"set_permissions_2_3", res.build_config.base})
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end
    for _,grp in ipairs(info.chroot.groups) do
        if res.build_config.groups[grp.name] then
            for _, f in ipairs(grp.files) do
                local flags = { cache = true }
                local rc, re = info.cache:cache_file(f.server, f.location, flags)
                if not rc then
                    return false, e:cat(re)
                end
                local path, re = info.cache:file_path(f.server, f.location, flags)
                if not path then
                    return false, e:cat(re)
                end
                if f.sha1 then
                    rc, re = e2tool.verify_hash(info, f.server, f.location, f.sha1)
                    if not rc then
                        return false, e:cat(re)
                    end
                end
                local tartype
                tartype, re = e2lib.tartype_by_suffix(path)
                if not tartype then
                    return false, e:cat(re)
                end

                e2tool.set_umask(info)
                local argv = { "extract_tar_2_3", res.build_config.base, tartype, path }
                local rc, re = e2lib.e2_su_2_2(argv)
                e2tool.reset_umask(info)
                if not rc then
                    return false, e:cat(re)
                end
            end
        end
    end
    return true, nil
end

function e2build.enter_playground(info, r, chroot_command)
    if not chroot_command then
        chroot_command = "/bin/bash"
    end
    local res = info.results[r]
    local rc, re
    local e = err.new("entering playground")
    e2lib.log(4, "entering playground for " .. r .. " ...")
    local term = e2lib.globals.terminal
    local e2_su = tools.get_tool("e2-su-2.2")
    local cmd = string.format("%s %s chroot_2_3 '%s' %s",
    res.build_config.chroot_call_prefix, e2_su,
    res.build_config.base, chroot_command)
    e2tool.set_umask(info)
    os.execute(cmd)
    e2tool.reset_umask(info)
    -- return code depends on user commands. Ignore.
    return true, nil
end

local function fix_permissions(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("fixing permissions failed")
    e2lib.log(3, "fix permissions")
    e2tool.set_umask(info)
    local argv = { "chroot_2_3", res.build_config.base, tools.get_tool("chown"),
        "-R", "root:root", res.build_config.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end
    e2tool.set_umask(info)
    argv = { "chroot_2_3", res.build_config.base, "chmod", "-R", "u=rwX,go=rX",
    res.build_config.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

local function playground(info, r, return_flags)
    local res = info.results[r]
    if res.playground then
        return_flags.message = string.format("playground done for: %-20s", r)
        return_flags.stop = true
        return true, nil
    end
    -- do nothing...
    return true, nil
end

local function runbuild(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("build failed")
    e2lib.log(3, "building " .. r .. " ...")
    local runbuild = string.format("/bin/bash -e -x %s/%s/%s",
    e2lib.shquote(res.build_config.Tc),
    e2lib.shquote(res.build_config.scriptdir),
    e2lib.shquote(res.build_config.build_driver_file))
    local e2_su = tools.get_tool("e2-su-2.2")
    local cmd = string.format("%s %s chroot_2_3 %s %s",
    e2lib.shquote(res.build_config.chroot_call_prefix),
    e2lib.shquote(e2_su),
    e2lib.shquote(res.build_config.base), runbuild)
    -- the build log is written to an external logfile
    rc, re = e2lib.rotate_log(res.build_config.buildlog)
    if not rc then
        return false, e:cat(re)
    end
    local out, msg = io.open(res.build_config.buildlog, "w")
    if not out then
        return false, e:cat(msg)
    end
    local function logto(output)
        e2lib.log(3, output)
        out:write(output)
        out:flush()
    end
    e2tool.set_umask(info)
    local rc = e2lib.callcmd_capture(cmd, logto)
    e2tool.reset_umask(info)
    out:close()
    if rc ~= 0 then
        e = err.new("build script for %s failed with exit status %d", r, rc)
        e:append("see %s for more information", res.build_config.buildlog)
        return false, e
    end
    return true, nil
end

local function chroot_remove(info, r, return_flags)
    local res = info.results[r]
    local e = err.new("removing chroot failed")
    e2tool.set_umask(info)
    local rc, re = e2lib.e2_su_2_2({"remove_chroot_2_3", res.build_config.base})
    e2tool.reset_umask(info)
    if not rc then
        return e:cat(re)
    end
    rc, re = e2lib.rm(res.build_config.chroot_marker)
    if not rc then
        return false, e:cat(re)
    end
    local f = string.format("%s/playground", info.root)
    local s = e2util.stat(f)
    if s and s.type == "symbolic-link" then
        local rc, e = e2lib.rm(f, "-f")
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

local function chroot_cleanup(info, r, return_flags)
    local res = info.results[r]
    -- do not remove chroot if the user requests to keep it
    if res.keep_chroot then
        return true, nil
    end
    return chroot_remove(info, r, return_flags)
end

local function chroot_cleanup_if_exists(info, r, return_flags)
    local res = info.results[r]
    if chroot_remove(info, r, return_flags) then
        return chroot_cleanup(info, r, return_flags)
    end
    return true, nil
end

--- check if a chroot exists for this result
-- @param info
-- @param r string: result name
-- @return bool
function e2build.chroot_exists(info, r)
    local res = info.results[r]
    return e2lib.isfile(res.build_config.chroot_marker)
end

function e2build.unpack_result(info, r, dep, destdir)
    local res = info.results[r]
    local rc, re
    local tmpdir = e2lib.mktempdir()
    local e = err.new("unpacking result failed: %s", dep)
    local d = info.results[dep]
    local buildid = e2tool.buildid(info, dep)

    local dep_set = res.build_mode.dep_set(buildid)
    local server, location = res.build_mode.storage(info.project_location,
    info.release_id)
    e2lib.log(3, string.format("searching for dependency %s in %s:%s",
    dep, server, location))
    local location1 = string.format("%s/%s/%s/result.tar", location, dep,
    dep_set)
    local cache_flags = {}
    local path, re = info.cache:file_path(server, location1, cache_flags)
    if not path then
        return false, e:cat(re)
    end
    rc, re = e2lib.chdir(tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir("result")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.tar({ "-xf", path, "-C", "result" })
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.chdir("result")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.call_tool("sha1sum", "-c checksums")
    if not rc then
        e:append("checksum mismatch in dependency: %s", dep)
        return false, e:cat(re)
    end
    rc, re = e2lib.chdir("files")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir(destdir, "-p")
    if not rc then
        return false, e:cat(re)
    end
    for f in e2lib.directory(".") do
        rc, re = e2lib.mv(f, destdir)
        if not rc then
            return false, e:cat(re)
        end
    end
    rc, re = e2tool.lcd(info, ".")
    if not rc then
        return false, e:cat(re)
    end
    e2lib.rmtempdir(tmpdir)
    return true, nil
end

--- write build driver files
-- @param info
-- @param r string:  result name
-- @param destdir string: where to store the scripts
-- @return bool
-- @return an error object on failure
local function write_build_driver(info, r, destdir)
    e2lib.log(4, "writing build driver")
    local res = info.results[r]
    local rc, re
    local e = err.new("generating build driver script failed")
    local buildrc_file = string.format("%s/%s", destdir,
    res.build_config.buildrc_file)
    local buildrc_noinit_file = string.format("%s/%s", destdir,
    res.build_config.buildrc_noinit_file)
    local build_driver_file = string.format("%s/%s", destdir,
    res.build_config.build_driver_file)
    local bd = ""
    bd=bd..string.format("source %s/env/builtin\n", res.build_config.Tc)
    bd=bd..string.format("source %s/env/env\n", res.build_config.Tc)
    local brc_noinit = bd
    for x in e2lib.directory(info.root .. "/proj/init") do
        if not e2lib.is_backup_file(x) then
            bd=bd..string.format("source %s/init/%s\n", res.build_config.Tc, x)
        end
    end
    bd=bd..string.format("cd %s/build\n", res.build_config.Tc)
    local brc = bd  -- the buildrc file
    bd=bd..string.format("set\n")
    bd=bd..string.format("cd %s/build\n", res.build_config.Tc)
    bd=bd..string.format("source %s/script/build-script\n", res.build_config.Tc)
    -- write buildrc file (for interactive use)
    local f, re = io.open(buildrc_file, "w")
    if not f then
        return false, e:cat(re)
    end
    f:write(brc)
    f:close()
    -- write buildrc file (for interactive use, without sourcing init files)
    local f, re = io.open(buildrc_noinit_file, "w")
    if not f then
        return false, e:cat(re)
    end
    f:write(brc_noinit)
    f:close()
    -- write the build driver
    local f, re = io.open(build_driver_file, "w")
    if not f then
        return false, e:cat(re)
    end
    f:write(bd)
    f:close()
    return true, nil
end

--- write the environment script for a result into a file
-- @param env env object
-- @param file string: the target filename
-- @return bool
-- @return an error object on failure
local function write_environment_script(env, file)
    local e = err.new("writing environment script")
    local f, msg = io.open(file, "w")
    if not f then
        e:append("%s: %s", file, msg)
        return false, e
    end
    for var, val in env:iter() do
        f:write(string.format("%s=\"%s\"\n", var, val))
    end
    f:close()
    return true, nil
end

local function sources(info, r, return_flags)
    local e = err.new("installing sources")
    local i, k, l, source, cp

    -- the development build case
    --
    -- install directory structure
    -- install build-script
    -- install e2-runbuild
    -- install build time dependencies
    --
    -- for each source do
    --   prepare_source
    -- end

    local function append_to_build_driver(info, r, script)
        local res = info.results[r]
        res.build_config.build_driver =
        res.build_config.build_driver .. string.format("%s\n", script)
    end

    local function install_directory_structure(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing directory structure")
        local dirs = {"out", "init", "script", "build", "root", "env", "dep"}
        for _, v in pairs(dirs) do
            local d = string.format("%s/%s", res.build_config.T, v)
            local rc, re = e2lib.mkdir(d, "-p")
            if not rc then
                return false, e:cat(re)
            end
        end
        return true, nil
    end

    local function install_build_script(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing build script")
        local location = e2tool.resultbuildscript(info.results[r].directory)
        local destdir = string.format("%s/script", res.build_config.T)
        rc, re = transport.fetch_file(info.root_server, location, destdir, nil)
        if not rc then
            return false, e:cat(re)
        end
        return true, nil
    end

    local function install_env(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing environment files failed")
        -- install builtin environment variables
        local file = string.format("%s/env/builtin", res.build_config.T)
        rc, re = write_environment_script(res.build_config.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        append_to_build_driver(info, r, string.format("source %s/env/builtin",
        res.build_config.Tc))
        -- install project specific environment variables
        local file = string.format("%s/env/env", res.build_config.T)
        rc, re = write_environment_script(res.build_config.env, file)
        if not rc then
            return false, e:cat(re)
        end
        append_to_build_driver(info, r, string.format("source %s/env/env",
        res.build_config.Tc))
        return true, nil
    end

    local function install_init_files(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing init files")
        for x in e2lib.directory(info.root .. "/proj/init") do
            if not e2lib.is_backup_file(x) then
                local location = string.format("proj/init/%s", x)
                local abslocation = string.format("%s/%s", info.root, location)
                local destdir = string.format("%s/init", res.build_config.T)

                if not e2lib.isfile(abslocation) then
                    return false, e:append("'%s' is not a regular file",
                        abslocation)
                end

                rc, re = transport.fetch_file(info.root_server, location, destdir)
                if not rc then
                    return false, e:cat(re)
                end
                append_to_build_driver(info, r, string.format("source %s/init/%s",
                res.build_config.Tc, x))
            end
        end
        return true, nil
    end

    local function install_build_driver(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("writing build driver script failed")
        local bc = res.build_config
        local destdir = string.format("%s/%s", bc.T, bc.scriptdir)
        rc, re = write_build_driver(info, r, destdir)
        if not rc then
            return false, e:cat(re)
        end
        return true, nil
    end

    local function install_build_time_dependencies(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing build time dependencies")
        e2lib.log(3, string.format("install_build_time_dependencies"))
        local deps
        deps = e2tool.get_depends(info, r)
        for i, dep in pairs(deps) do
            local destdir = string.format("%s/dep/%s", res.build_config.T, dep)
            rc, re = e2build.unpack_result(info, r, dep, destdir)
            if not rc then
                return false, e:cat(re)
            end
        end
        return true, nil
    end

    local function install_sources(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("installing sources")
        e2lib.log(3, "install sources")
        for i, source in pairs(res.sources) do
            local e = err.new("installing source failed: %s", source)
            local destdir = string.format("%s/build", res.build_config.T)
            local source_set = res.build_mode.source_set()
            local rc, re = scm.prepare_source(info, source, source_set,
            destdir)
            if not rc then
                return false, e:cat(re)
            end
        end
        return true, nil
    end

    local steps = {
        install_directory_structure,
        install_build_script,
        install_env,
        install_init_files,
        install_build_driver,
        install_build_time_dependencies,
        install_sources,
    }
    for _,f in ipairs(steps) do
        local rflags = {}
        local rc, re = f(info, r, rflags)
        if not rc then
            return false, re
        end
    end
    return true, nil
end

--- deploy a result to the archive
-- @param info
-- @param r string: result name
-- @param return_flags table
-- @return bool
-- @return an error object on failure
local function deploy(info, r, return_flags)
    --[[
    This function is called located in a temporary directory that contains
    the unpacked result structure and the result tarball itself as follows:
    ./result/build.log.gz
    ./result/checksums
    ./result/files/*
    ./result.tar

    This function pushes the result files and the checksum file as follows:
    -- result/checksums
    --   -> releases:<project>/<archive>/<release_id>/<result>/checksums
    -- result/files/*
    --   -> releases:<project>/<archive>/<release_id>/<result>/files/*
    --]]
    local res = info.results[r]
    if not res.build_mode.deploy then
        e2lib.logf(4, "deployment disabled for this build mode")
        return true
    end
    if not res._deploy then
        e2lib.logf(4, "deployment disabled for this result")
        return true
    end
    local files = {}
    for f in e2lib.directory("result/files") do
        table.insert(files, string.format("files/%s", f))
    end
    table.insert(files, "checksums")
    local server, location = res.build_mode.deploy_storage(info.project_location,
    info.release_id)

    -- do not re-deploy if this release was already done earlier
    local location1 = string.format("%s/%s/checksums", location, r)
    local cache_flags = {
        cache = false,
    }
    local rc, re = info.cache:fetch_file(server, location1, ".", nil, cache_flags)
    if rc then
        e2lib.warnf("WOTHER",
        "Skipping deployment. This release was already deployed.")
        return true
    end

    e2lib.logf(1, "deploying %s to %s:%s", r, server, location)
    for _,f in ipairs(files) do
        local sourcefile = string.format("result/%s", f)
        local location1 = string.format("%s/%s/%s", location, r, f)
        local cache_flags = {}
        local rc, re = info.cache:push_file(sourcefile, server, location1,
        cache_flags)
        if not rc then
            return false, re
        end
    end
    return true
end

--- store the result
-- @param info
-- @param r string: result name
-- @param return_flags table
-- @return bool
-- @return an error object on failure
local function store_result(info, r, return_flags)
    e2lib.logf(4, 'e2_build.store_result(%s, "%s", %s', tostring(info), r,
    tostring(return_flags))
    local res = info.results[r]
    local rc, re
    local e = err.new("fetching build results from chroot")
    e2lib.log(4, string.format("store_result"))

    -- create a temporary directory to build up the result
    local tmpdir = e2lib.mktempdir()

    -- build a stored result structure and store
    local rfilesdir = string.format("%s/out", res.build_config.T)
    rc, re = e2lib.chdir(tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir("result/files", "-p")
    if not rc then
        return false, e:cat(re)
    end
    local nfiles = 0
    for f in e2lib.directory(rfilesdir, false, true) do
        e2lib.logf(3, "result file: %s", f)
        local s = string.format("%s/%s", rfilesdir, f)
        local d = "result/files"
        rc, re = e2lib.ln(s, d)
        if not rc then
            e:cat(re)
            e2lib.warnf("WOTHER",
            "Creating hardlink failed. Falling back to copying.")
            rc, re = e2lib.cp(s, d)
            if not rc then
                return false, e:cat(re)
            end
        end
        nfiles = nfiles + 1
    end
    if nfiles < 1 then
        e:append("No output files available.")
        e:append("Please make sure your build script leaves at least one file in")
        e:append("the output directory.")
        return false, e
    end
    rc, re = e2lib.chdir("result")
    if not rc then
        return false, e:cat(re)
    end
    local args = "files/* >checksums"
    rc, re = e2lib.call_tool("sha1sum", args)
    if not rc then
        return false, e:cat(re)
    end
    -- include compressed build logfile into the result tarball
    rc, re = e2lib.cp(res.build_config.buildlog, "build.log")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.gzip({ "build.log" })
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.chdir("..")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.tar({ "-cf", "result.tar", "-C", "result", "." })
    if not rc then
        return false, e:cat(re)
    end
    local server, location = res.build_mode.storage(info.project_location,
    info.release_id)
    local buildid = res.build_mode.buildid(e2tool.buildid(info, r))
    local sourcefile = string.format("%s/result.tar", tmpdir)
    local location1 = string.format("%s/%s/%s/result.tar", location, r, buildid)
    local cache_flags = {
        try_hardlink = true,
    }
    local rc, re = info.cache:push_file(sourcefile, server, location1,
    cache_flags)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = deploy(info, r, return_flags)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2tool.lcd(info, ".")
    if not rc then
        return false, e:cat(re)
    end
    e2lib.rmtempdir(tmpdir)
    return true, nil
end

--- build a result
-- @param info
-- @param result string: result name
-- @return bool
-- @return an error object on failure
local function build_result(info, result, return_flags)
    e2lib.logf(3, "building result: %s", result)
    local res = info.results[result]
    for _,f in ipairs(build_process) do
        -- e2lib.logf(3, "running function: %s", f.name)
        local t1 = os.time()
        local flags = {}
        local rc, re = f.func(info, result, flags)
        local t2 = os.time()
        local deltat = os.difftime(t2, t1)
        e2lib.logf(3, "timing: step: %s [%s] %d", f.name, result, deltat)
        if not rc then
            -- do not insert an error message from this layer.
            return false, re
        end
        if flags.message then
            e2lib.log(2, flags.message)
        end
        if flags.stop then
            -- stop the build process for this result
            return true, nil
        end
        if flags.terminate then
            -- stop the build process for this result and terminate
            return true, nil
        end
    end
    return true, nil
end

--- build a set of results
-- @param info
-- @param results table: list of results, sorted by dependencies
-- @return bool
-- @return an error object on failure
local function build_results_default(info, results)
    e2lib.logf(3, "building results")
    for _, r in ipairs(results) do
        local e = err.new("building result failed: %s", r)
        local flags = {}
        local t1 = os.time()
        local rc, re = build_result(info, r, flags)
        if not rc then
            -- do not insert an error message from this layer.
            return false, e:cat(re)
        end
        local t2 = os.time()
        local deltat = os.difftime(t2, t1)
        e2lib.logf(3, "timing: result [%s] %d", r, deltat)
        if flags.stop then
            return true, nil
        end
    end
    return true, nil
end

local build_results_ftab = {
    build_results_default,
}

function e2build.build_results(info, results)
    for i,f in ipairs(build_results_ftab) do
        local rc, re = f(info, results)
        if not rc then
            return rc, re
        end
    end
    return true, nil
end

--- collect all data required to build the project.
-- skip results that depend on this result
-- example: toolchain, busybox, sources, iso,
-- sources being the result collecting the project:
-- the results sources and iso won't be included, as that would lead to
-- an impossibility to calculate buildids (infinite recursion)
-- @param c table: build context
-- @return bool
-- @return an error object on failure
local function collect_project(info, r, return_flags)
    local res = info.results[r]
    if not res.collect_project then
        -- nothing to be done here...
        return true, nil
    end
    e2lib.log(3, "providing project data to this build")
    local rc, re
    local e = err.new("providing project data to this build failed")
    -- project/proj/init/<files>
    local destdir = string.format("%s/project/proj/init",
    res.build_config.T)
    e2lib.mkdir(destdir, "-p")
    local init_files = e2util.directory(info.root .. "/proj/init")
    for _,f in ipairs(init_files) do
        e2lib.log(3, string.format("init file: %s", f))
        local server = "."
        local location = string.format("proj/init/%s", f)
        local cache_flags = {}
        rc, re = info.cache:fetch_file(server, location,
        destdir, nil, cache_flags)
        if not rc then
            return false, e:cat(re)
        end
    end
    -- write project configuration
    local file, destdir
    local lines = ""
    destdir = string.format("%s/project/proj", res.build_config.T)
    file = string.format("%s/config", destdir)
    local f, msg = io.open(file, "w")
    if not f then
        return false, e:cat(re)
    end
    f:write(string.format("name='%s'\n", info.name))
    f:write(string.format("release_id='%s'\n", info.release_id))
    f:write(string.format("default_results='%s'\n",
    res.collect_project_default_result))
    f:write(string.format("chroot_arch='%s'\n",
    info.project.chroot_arch))
    f:close()
    -- files from the project
    local destdir = string.format("%s/project/.e2/bin", res.build_config.T)
    e2lib.mkdir(destdir, "-p")
    -- generate build driver file for each result
    -- project/chroot/<group>/<files>
    for _,g in pairs(res.collect_project_chroot_groups) do
        e2lib.log(3, string.format("chroot group: %s", g))
        local grp = info.chroot.groups_byname[g]
        local destdir = string.format("%s/project/chroot/%s",
        res.build_config.T, g)
        e2lib.mkdir(destdir, "-p")
        local makefile, msg = io.open(
        string.format("%s/makefile", destdir), "w")
        if not makefile then
            return false, e:cat(msg)
        end
        makefile:write(string.format("place:\n"))
        for _,file in pairs(grp.files) do
            local cache_flags = {}
            rc, re = info.cache:fetch_file(file.server,
            file.location, destdir, nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
            if file.sha1 then
                local checksum_file = string.format(
                "%s/%s.sha1", destdir,
                e2lib.basename(file.location))
                local filename = e2lib.basename(file.location)
                rc, re = e2lib.write_file(checksum_file,
                string.format("%s  %s",
                file.sha1, filename))
                if not rc then
                    return false, e:cat(re)
                end
                makefile:write(string.format(
                "\tsha1sum -c '%s'\n",
                e2lib.basename(checksum_file)))
            end
            local tartype
            tartype, re = e2lib.tartype_by_suffix(file.location)
            if not tartype then
                return false, e:cat(re)
            end
            makefile:write(string.format(
            "\te2-su-2.2 extract_tar_2_3 $(chroot_base) "..
            "\"%s\" '%s'\n",
            tartype, e2lib.basename(file.location)))
        end
        makefile:close()
    end
    -- project/licences/<licence>/<files>
    for _,l in ipairs(res.collect_project_licences) do
        e2lib.logf(3, "licence: %s", l)
        local lic = info.licences[l]
        local destdir = string.format("%s/project/licences/%s",
        res.build_config.T, l)
        e2lib.mkdir(destdir, "-p")
        for _,file in ipairs(lic.files) do
            local cache_flags = {}
            if file.sha1 then
                rc, re = e2tool.verify_hash(info, file.server,
                file.location, file.sha1)
                if not rc then
                    return false, e:cat(re)
                end
            end
            rc, re = info.cache:fetch_file(file.server,
            file.location, destdir, nil,
            cache_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
    end
    -- project/results/<res>/<files>
    for _,n in ipairs(res.collect_project_results) do
        e2lib.log(3, string.format("result: %s", n))
        local rn = info.results[n]
        rc, re = e2build.build_config(info, n)
        if not rc then
            return false, e:cat(re)
        end
        local destdir = string.format("%s/project/%s",
        res.build_config.T, e2tool.resultdir(n))
        e2lib.mkdir(destdir, "-p")
        -- copy files
        local files = {
            e2tool.resultbuildscript(info.results[n].directory)
        }
        for _,file in pairs(files) do
            local server = info.root_server_name
            local cache_flags = {}
            rc, re = info.cache:fetch_file(server, file,
            destdir, nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
        local file, line
        -- generate environment script
        file = string.format("%s/env", destdir)
        rc, re = write_environment_script(rn.build_config.env, file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate builtin environment script
        local file = string.format("%s/builtin", destdir)
        rc, re = write_environment_script(
        rn.build_config.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate build driver
        rc, re = write_build_driver(info, n, destdir)
        if not rc then
            return false, e:cat(re)
        end
        -- generate config
        local config = string.format("%s/config", destdir)
        local f, msg = io.open(config, "w")
        if not f then
            e:cat(err.new("%s: %s", config, msg))
            return false, e
        end
        f:write(string.format(
        "### generated by e2 for result %s ###\n", n))
        f:write(string.format(
        "CHROOT='base %s'\n", table.concat(rn.chroot, " ")))
        f:write(string.format(
        "DEPEND='%s'\n", table.concat(rn.depends, " ")))
        f:write(string.format(
        "SOURCE='%s'\n", table.concat(rn.sources, " ")))
        f:close()
    end
    for _,s in ipairs(info.results[r].collect_project_sources) do
        local src = info.sources[s]
        e2lib.log(3, string.format("source: %s", s))
        local destdir = string.format("%s/project/%s",
        res.build_config.T, e2tool.sourcedir(s))
        e2lib.mkdir(destdir, "-p")
        local source_set = res.build_mode.source_set()
        local files, re = scm.toresult(info, src.name, source_set,
        destdir)
        if not files then
            return false, e:cat(re)
        end
    end
    -- write topologically sorted list of result
    local destdir = string.format("%s/project", res.build_config.T)
    local tsorted_results, re = e2tool.dlist_recursive(info,
    res.collect_project_results)
    if not tsorted_results then
        return false, e:cat(re)
    end
    local tsorted_results_string = table.concat(tsorted_results, "\n")
    local resultlist = string.format("%s/resultlist", destdir)
    rc, re = e2lib.write_file(resultlist, tsorted_results_string .. "\n")
    if not rc then
        return false, e:cat(re)
    end
    -- install the global Makefiles
    local server = "."
    local destdir = string.format("%s/project", res.build_config.T)
    local cache_flags = {}
    local locations = {
        ".e2/lib/make/Makefile",
        ".e2/lib/make/linux32.c",
        ".e2/lib/make/e2-su-2.2.c",
        ".e2/lib/make/build.sh",
        ".e2/lib/make/buildall.sh",
        ".e2/lib/make/detect_tool",
    }
    for _,location in ipairs(locations) do
        rc, re = info.cache:fetch_file(server, location,
        destdir, nil, cache_flags)
        if not rc then
            return false, e:cat(re)
        end
    end
    local executables = {
        "buildall.sh",
        "detect_tool",
    }
    for _,f in ipairs(executables) do
        local x = string.format("%s/%s", destdir, f)
        local rc, re = e2lib.chmod("755", x)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

--- register a function to extend the build process
-- @param info
-- @param name string: build function name (used for logging)
-- @param func function: build function
-- @param pos string: build function name. The new function will run before
--                     the named function
-- @return bool
-- @return an error object on failure
function e2build.register_build_function(info, name, func, pos)
    local e = err.new("register build function")
    local ipos = nil
    for i=1, #build_process, 1 do
        if build_process[i].name == pos then
            ipos = i
            break
        end
    end
    if not ipos then
        return false, e:append("Invalid position.")
    end
    local tab = {
        name = name,
        func = func,
    }
    table.insert(build_process, ipos, tab)
    return true, nil
end

build_process = {
    { name="build_config", func=e2build.build_config },
    { name="result_available", func=result_available },
    { name="chroot_lock", func=chroot_lock },
    { name="chroot_cleanup_if_exists",
        func=chroot_cleanup_if_exists },
    { name="setup_chroot", func=setup_chroot },
    { name="sources", func=sources },
    { name="collect_project", func=collect_project },
    { name="fix_permissions", func=fix_permissions},
    { name="playground", func=playground },
    { name="runbuild", func=runbuild },
    { name="store_result", func=store_result },
    { name="linklast", func=linklast },
    { name="chroot_cleanup", func=chroot_cleanup },
    { name="chroot_unlock", func=chroot_unlock },
}

return strict.lock(e2build)

-- vim:sw=4:sts=4:et:
