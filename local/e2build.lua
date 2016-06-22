--- Core build logic
-- @module local.e2build

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
local buildconfig = require("buildconfig")
local cache = require("cache")
local chroot = require("chroot")
local digest = require("digest")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local project = require("project")
local result = require("result")
local scm = require("scm")
local strict = require("strict")
local tools = require("tools")
local transport = require("transport")

-- Table driving the build process, see documentation at the bottom.
local build_process = {}

--- TODO
local function linklast(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re
    local e = err.new("creating link to last results")
    -- calculate the path to the result
    local server, location = res:get_build_mode().storage(info.project_location,
        project.release_id())

    local buildid, re = e2tool.buildid(info, resultname)
    if not buildid then
        return false, e:cat(re)
    end
    local location1 = e2lib.join(location, resultname, buildid)
    local cache_flags = {
        check_only = true
    }
    local dst, re = cache.file_path(info.cache, server, location1, cache_flags)
    if not dst then
        return false, e:cat(re)
    end
    -- create the last link
    local lnk_location = e2lib.join("out", resultname, "last")
    local lnk, re = cache.file_path(info.cache, info.root_server_name, lnk_location)
    if not lnk then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir_recursive(e2lib.dirname(lnk))
    if not rc then
        return false, e:cat(re)
    end

    if e2lib.stat(lnk, false) then
        e2lib.unlink(lnk) -- ignore errors, symlink will catch it
    end

    rc, re = e2lib.symlink(dst, lnk)		-- create the new link
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

--- Return true if the result given in c is already available, false otherwise
-- return the path to the result
-- check if a result is already available
-- @param info
-- @param resultname string: result name
-- @param return_flags table: return values through this table
-- @return bool
-- @return an error object on failure
local function result_available(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re
    local buildid, sbid
    local e = err.new("error while checking if result is available: %s", resultname)
    local columns = tonumber(e2lib.globals.osenv["COLUMNS"])

    buildid, re = e2tool.buildid(info, resultname)
    if not buildid then
        return false, e:cat(re)
    end

    sbid = e2tool.bid_display(buildid)

    if result.build_settings.playground:lookup(resultname) then
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", resultname),
        columns, string.format("[%s] [playground]", sbid))
        return_flags.stop = false
        return true, nil
    end
    if res:get_build_mode().source_set() == "working-copy" or
        result.build_settings.force_rebuild:lookup(resultname) then
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", resultname),
        columns, string.format("[%s]", sbid))
        return_flags.stop = false
        return true, nil
    end
    local server, location =
        res:get_build_mode().storage(info.project_location, project.release_id())
    local dep_set = res:get_build_mode().dep_set(buildid)

    -- cache the result
    local result_location = e2lib.join(location, resultname, dep_set, "result.tar")
    local cache_flags = {}
    rc, re = cache.cache_file(info.cache, server, result_location, cache_flags)
    if not rc then
        e2lib.log(3, "caching result failed")
        -- ignore
    end
    local cache_flags = {}
    local path, re = cache.file_path(info.cache, server, result_location,
        cache_flags)
    rc = e2lib.isfile(path)
    if not rc then
        -- result is not available. Build.
        return_flags.message = e2lib.align(columns,
        0, string.format("building %-20s", resultname),
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
    rc, re = linklast(info, resultname, return_flags)
    if not rc then
        return false, e:cat(re)
    end
    -- return true
    return_flags.message = e2lib.align(columns,
    0, string.format("skipping %-20s", resultname),
    columns, string.format("[%s]", sbid))
    return_flags.stop = true
    return true, nil
end

--- Build config per result. This table is locked.
-- @table build_config
-- @field base       string: path to the build directory
-- @field c	     string: path to the chroot
-- @field chroot_marker string: path to chroot marker file
-- @field chroot_lock Path to chroot lock file (string).
-- @field T          string: absolute path to the temporary build directory
--                           inside chroot
-- @field Tc         string: same as c.T but relative to c
-- @field resultname          string: result name
-- @field chroot_call_prefix XXX
-- @field buildlog   string: build log file
-- @field scriptdir XXX
-- @field build_driver XXX
-- @field build_driver_file XXX
-- @field buildrc_file XXX
-- @field buildrc_noinit_file XXX
-- @field profile Configuration file passed to the shell (string).
-- @field builtin_env Environment that's built in like E2_TMPDIR.

--- Generate build_config and store in res.build_config.
-- @param info Info table.
-- @param resultname Result name (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_config(info, resultname)
    local e = err.new("setting up build configuration for result `%s' failed", resultname)
    local res = result.results[resultname]
    if not res then
        return false, e:append("no such result: %s", resultname)
    end

    local buildid, re = e2tool.buildid(info, resultname)
    if not buildid then
        return false, e:cat(re)
    end

    local bc = {}

    local tmpdir = string.format("%s/e2factory-%s.%s.%s-build/%s",
        e2lib.globals.tmpdir, buildconfig.MAJOR, buildconfig.MINOR,
        buildconfig.PATCHLEVEL, e2lib.globals.osenv["USER"])
    local builddir = "tmp/e2"

    bc.base = e2lib.join(tmpdir, project.name(), resultname)
    bc.c = e2lib.join(bc.base, "chroot")
    bc.chroot_marker = e2lib.join(bc.base, "e2factory-chroot")
    bc.chroot_lock = e2lib.join(bc.base, "e2factory-chroot-lock")
    bc.T = e2lib.join(tmpdir, project.name(), resultname, "chroot", builddir)
    bc.Tc = e2lib.join("/", builddir)
    bc.r = resultname
    bc.chroot_call_prefix = info.chroot_call_prefix[project.chroot_arch()]
    bc.buildlog = string.format("%s/log/build.%s.log", info.root, resultname)
    bc.scriptdir = "script"
    bc.build_driver = ""
    bc.build_driver_file = "build-driver"
    bc.buildrc_file = "buildrc"
    bc.buildrc_noinit_file = "buildrc-noinit"
    bc.profile = "/tmp/bashrc"
    bc.builtin_env = environment.new()
    bc.builtin_env:set("E2_TMPDIR", bc.Tc)
    bc.builtin_env:set("E2_RESULT", resultname)
    bc.builtin_env:set("E2_RELEASE_ID", project.release_id())
    bc.builtin_env:set("E2_PROJECT_NAME", project.name())
    bc.builtin_env:set("E2_BUILDID", buildid)
    bc.builtin_env:set("T", bc.Tc)
    bc.builtin_env:set("r", resultname)
    bc.builtin_env:set("R", resultname)

    res:set_buildconfig(strict.lock(bc))

    return true
end

--- TODO
local function chroot_lock(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re, bc
    local e = err.new("error locking chroot")
    bc = res:buildconfig()
    rc, re = e2lib.mkdir_recursive(bc.c)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.globals.lock:lock(bc.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

--- TODO
local function chroot_unlock(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re, bc
    local e = err.new("error unlocking chroot")
    bc = res:buildconfig()
    rc, re = e2lib.globals.lock:unlock(bc.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

--- TODO
local function setup_chroot(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re, bc
    local e = err.new("error setting up chroot")
    -- create the chroot path and create the chroot marker file without root
    -- permissions. That makes sure we have write permissions here.
    bc = res:buildconfig()
    rc, re = e2lib.mkdir_recursive(bc.c)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = eio.fopen(bc.chroot_marker, "w")
    if not rc then
        return false, e:cat(re)
    end

    local cm = rc

    rc, re = eio.fclose(cm)
    if not rc then
        return false, e:cat(re)
    end

    e2tool.set_umask(info)
    rc, re = e2lib.e2_su_2_2({"set_permissions_2_3", bc.base})
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end

    local grp
    for cgrpnm in res:my_chroot_list():iter_sorted() do
        grp = chroot.groups_byname[cgrpnm]

        for f in grp:file_iter() do
            local flags = { cache = true }
            local rc, re = cache.cache_file(info.cache, f.server,
                f.location, flags)
            if not rc then
                return false, e:cat(re)
            end
            local path, re = cache.file_path(info.cache, f.server,
                f.location, flags)
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
            local argv = { "extract_tar_2_3", bc.base, tartype, path }
            rc, re = e2lib.e2_su_2_2(argv)
            e2tool.reset_umask(info)
            if not rc then
                return false, e:cat(re)
            end
        end
    end
    return true, nil
end

--- Enter playground.
-- @param info
-- @param resultname
-- @param chroot_command (optional)
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.enter_playground(info, resultname, chroot_command)
    local rc, re, e, res, e2_su, cmd, bc

    res = result.results[resultname]
    bc = res:buildconfig()
    e = err.new("entering playground")

    e2_su = tools.get_tool("e2-su-2.2")
    if not e2_su then
        return false, e:cat(re)
    end

    cmd = {
        e2_su,
        "chroot_2_3",
        bc.base,
    }

    if #bc.chroot_call_prefix > 0 then
        table.insert(cmd, 1, bc.chroot_call_prefix)
    end

    if chroot_command then
        table.insert(cmd, "/bin/sh")
        table.insert(cmd, "-c")
        table.insert(cmd, chroot_command)
    else
        table.insert(cmd, "/bin/bash")
    end

    e2tool.set_umask(info)
    rc, re = e2lib.callcmd(cmd, {})
    if not rc then
        e2tool.reset_umask(info)
        return false, e:cat(re)
    end
    -- return code depends on user commands. Ignore.

    e2tool.reset_umask(info)

    return true
end

--- TODO
local function fix_permissions(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re, bc
    local e = err.new("fixing permissions failed")
    e2lib.log(3, "fix permissions")
    e2tool.set_umask(info)
    bc = res:buildconfig()
    local argv = { "chroot_2_3", bc.base, "chown", "-R", "root:root", bc.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end
    e2tool.set_umask(info)
    argv = { "chroot_2_3", bc.base, "chmod", "-R", "u=rwX,go=rX", bc.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask(info)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

--- TODO
local function playground(info, resultname, return_flags)
    local res = result.results[resultname]
    if result.build_settings.playground:lookup(resultname)  then
        return_flags.message = string.format("playground done for: %-20s", resultname)
        return_flags.stop = true
        return true, nil
    end
    -- do nothing...
    return true, nil
end

--- TODO
local function runbuild(info, resultname, return_flags)
    local res = result.results[resultname]
    local rc, re, out, bc
    local e = err.new("build failed")
    e2lib.logf(3, "building %s ...", resultname)
    local e2_su, re = tools.get_tool("e2-su-2.2")
    if not e2_su then
        return false, e:cat(re)
    end
    bc = res:buildconfig()
    -- the build log is written to an external logfile
    rc, re = e2lib.rotate_log(bc.buildlog)
    if not rc then
        return false, e:cat(re)
    end

    out, re = eio.fopen(bc.buildlog, "w")
    if not out then
        return false, e:cat(re)
    end

    local function logto(output)
        e2lib.log(3, output)
        eio.fwrite(out, output)
    end

    e2tool.set_umask(info)

    local cmd = {
        e2_su,
        "chroot_2_3",
        bc.base,
        "/bin/bash",
        "-e", "-x",
        e2lib.join(bc.Tc, bc.scriptdir, bc.build_driver_file)
    }

    if #bc.chroot_call_prefix > 0 then
        table.insert(cmd, 1, bc.chroot_call_prefix)
    end

    rc, re = e2lib.callcmd_capture(cmd, logto)
    if not rc then
        eio.fclose(out)
        return false, e:cat(re)
    end
    e2tool.reset_umask(info)
    if rc ~= 0 then
        eio.fclose(out)
        e = err.new("build script for %s failed with exit status %d", resultname, rc)
        e:append("see %s for more information", bc.buildlog)
        return false, e
    end

    rc, re = eio.fclose(out)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- TODO
local function chroot_remove(info, resultname, return_flags)
    local res = result.results[resultname]
    local e = err.new("removing chroot failed")
    local rc, re, bc
    bc = res:buildconfig()
    e2tool.set_umask(info)
    rc, re = e2lib.e2_su_2_2({"remove_chroot_2_3", bc.base})
    e2tool.reset_umask(info)
    if not rc then
        return e:cat(re)
    end
    rc, re = e2lib.unlink(bc.chroot_marker)
    if not rc then
        return false, e:cat(re)
    end
    local f = e2lib.join(info.root, "playground")
    local s = e2lib.stat(f)
    if s and s.type == "symbolic-link" then
        rc, re = e2lib.unlink(f)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

--- TODO
local function chroot_cleanup(info, resultname, return_flags)
    local res = result.results[resultname]
    -- do not remove chroot if the user requests to keep it
    if result.build_settings.keep_chroot:lookup(resultname) then
        return true
    end
    return chroot_remove(info, resultname, return_flags)
end

--- TODO
local function chroot_cleanup_if_exists(info, resultname, return_flags)
    local res = result.results[resultname]
    if chroot_remove(info, resultname, return_flags) then
        return chroot_cleanup(info, resultname, return_flags)
    end
    return true, nil
end

--- check if a chroot exists for this result
-- @param info Info table
-- @param resultname Result name
-- @return True if chroot for result could be found, false otherwise.
function e2build.chroot_exists(info, resultname)
    local res = result.results[resultname]
    local bc = res:buildconfig()
    return e2lib.isfile(bc.chroot_marker)
end

--- TODO
function e2build.unpack_result(info, resultname, dep, destdir)
    local res = result.results[resultname]
    local rc, re
    local e = err.new("unpacking result failed: %s", dep)
    local d = result.results[dep]
    local dt

    local buildid, re = e2tool.buildid(info, dep)
    if not buildid then
        return false, re
    end

    local dep_set = d:get_build_mode().dep_set(buildid)
    local server, location =
        d:get_build_mode().storage(info.project_location, project.release_id())
    e2lib.logf(3, "searching for dependency %s in %s:%s", dep, server, location)
    local location1 = e2lib.join(location, dep, dep_set, "result.tar")
    local cache_flags = {}
    local path, re = cache.file_path(info.cache, server, location1, cache_flags)
    if not path then
        return false, e:cat(re)
    end
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
    end

    local resdir = e2lib.join(tmpdir, "result")

    rc, re = e2lib.mkdir(resdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.tar({ "-xf", path, "-C", resdir })
    if not rc then
        return false, e:cat(re)
    end

    dt, re = digest.parse(e2lib.join(resdir, "checksums"))
    if not dt then
        return false, e:cat(re)
    end

    rc, re = digest.verify(dt, resdir)
    if not rc then
        e:append("checksum mismatch in dependency: %s", dep)
        return false, e:cat(re)
    end

    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end
    local filesdir = e2lib.join(resdir, "files")
    for f, re in e2lib.directory(filesdir) do
        if not f then
            return false, e:cat(re)
        end

        rc, re = e2lib.mv(e2lib.join(filesdir, f), destdir)
        if not rc then
            return false, e:cat(re)
        end
    end

    e2lib.rmtempdir(tmpdir)
    return true, nil
end

--- write build driver files
-- @param info
-- @param resultname string:  result name
-- @param destdir string: where to store the scripts
-- @return bool
-- @return an error object on failure
function e2build.write_build_driver(info, resultname, destdir)
    local rc, re, e, res, bd, buildrc_noinit_file, buildrc_file, bc
    local build_driver_file

    e = err.new("generating build driver script failed")

    res = result.results[resultname]
    bc = res:buildconfig()

    bd = {
        string.format("source %s/env/builtin\n", bc.Tc),
        string.format("source %s/env/env\n", bc.Tc)
    }

    -- write buildrc file (for interactive use, without sourcing init files)
    buildrc_noinit_file = e2lib.join(destdir,
        bc.buildrc_noinit_file)
    rc, re = eio.file_write(buildrc_noinit_file, table.concat(bd))
    if not rc then
        return false, e:cat(re)
    end

    for fn, re in e2lib.directory(e2lib.join(info.root, "proj/init")) do
        if not fn then
            return false, e:cat(re)
        end

        if not e2lib.is_backup_file(fn) then
            table.insert(bd, string.format("source %s/init/%s\n",
                bc.Tc, fn))
        end
    end
    table.insert(bd, string.format("cd %s/build\n", bc.Tc))

    -- write buildrc file (for interactive use)
    buildrc_file = e2lib.join(destdir, bc.buildrc_file)
    rc, re = eio.file_write(buildrc_file, table.concat(bd))
    if not rc then
        return false, e:cat(re)
    end

    table.insert(bd, "set\n")
    table.insert(bd, string.format("cd %s/build\n", bc.Tc))
    table.insert(bd, string.format("source %s/script/build-script\n",
        bc.Tc))

    -- write the build driver
    build_driver_file = e2lib.join(destdir, bc.build_driver_file)
    rc, re = eio.file_write(build_driver_file, table.concat(bd))
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- write the environment script for a result into a file
-- @param env env object
-- @param file string: the target filename
-- @return bool
-- @return an error object on failure
local function write_environment_script(env, file)
    local rc, re, e, out

    out = {}
    for var, val in env:iter() do
        table.insert(out, string.format("%s=%s\n", var, e2lib.shquote(val)))
    end

    rc, re = eio.file_write(file, table.concat(out))
    if not rc then
        e = err.new("writing environment script")
        return false, e:cat(re)
    end

    return true
end

--- TODO
local function sources(info, resultname, return_flags)
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

    local function append_to_build_driver(info, resultname, script)
        local res, bc
        res = result.results[resultname]
        bc = res:buildconfig()
        bc.build_driver = bc.build_driver .. string.format("%s\n", script)
    end

    local function install_directory_structure(info, resultname, return_flags)
        local rc, re, e, res, bc, dirs
        e = err.new("installing directory structure")
        res = result.results[resultname]
        bc = res:buildconfig()
        dirs = {"out", "init", "script", "build", "root", "env", "dep"}
        for _, v in pairs(dirs) do
            rc, re = e2lib.mkdir_recursive(e2lib.join(bc.T, v))
            if not rc then
                return false, e:cat(re)
            end
        end
        return true, nil
    end

    local function install_build_script(info, resultname, return_flags)
        local rc, re, e, res, bc, location, destdir
        e = err.new("installing build script")
        res = result.results[resultname]
        bc = res:buildconfig()
        location = e2tool.resultbuildscript(res:get_name_as_path())
        destdir = e2lib.join(bc.T, "script")
        rc, re = transport.fetch_file(info.root_server, location, destdir, nil)
        if not rc then
            return false, e:cat(re)
        end
        return true, nil
    end

    local function install_env(info, resultname, return_flags)
        local rc, re, e, res, bc
        e = err.new("installing environment files failed")
        res = result.results[resultname]
        bc = res:buildconfig()

        -- install builtin environment variables
        local file = e2lib.join(bc.T, "env/builtin")
        rc, re = write_environment_script(bc.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        append_to_build_driver(info, resultname,
            string.format("source %s/env/builtin", bc.Tc))
        -- install project specific environment variables
        local file = e2lib.join(bc.T, "env/env")
        rc, re = write_environment_script(res:merged_env(), file)
        if not rc then
            return false, e:cat(re)
        end
        append_to_build_driver(info, resultname,
            string.format("source %s/env/env", bc.Tc))
        return true
    end

    local function install_init_files(info, resultname, return_flags)
        local res = result.results[resultname]
        local bc = res:buildconfig()
        local rc, re
        local e = err.new("installing init files")
        for x, re in e2lib.directory(info.root .. "/proj/init") do
            if not x then
                return false, e:cat(re)
            end

            if not e2lib.is_backup_file(x) then
                local location = e2lib.join("proj/init", x)
                local abslocation = e2lib.join(info.root, location)
                local destdir = e2lib.join(bc.T, "init")

                if not e2lib.isfile(abslocation) then
                    return false, e:append("'%s' is not a regular file",
                        abslocation)
                end

                rc, re = transport.fetch_file(info.root_server, location, destdir)
                if not rc then
                    return false, e:cat(re)
                end
                append_to_build_driver(info, resultname,
                    string.format("source %s/init/%s", bc.Tc, x))
            end
        end
        return true, nil
    end

    local function install_build_driver(info, resultname, return_flags)
        local res = result.results[resultname]
        local rc, re
        local e = err.new("writing build driver script failed")
        local bc = res:buildconfig()
        local destdir = e2lib.join(bc.T, bc.scriptdir)
        rc, re = e2build.write_build_driver(info, resultname, destdir)
        if not rc then
            return false, e:cat(re)
        end
        return true, nil
    end

    local function install_build_time_dependencies(info, resultname, return_flags)
        local res = result.results[resultname]
        local bc = res:buildconfig()
        local rc, re
        local e = err.new("installing build time dependencies")
        local deps
        deps, re = e2tool.dlist(resultname)
        if not deps then
            return false, e:cat(re)
        end
        for i, dep in pairs(deps) do
            local destdir = e2lib.join(bc.T, "dep", dep)
            rc, re = e2build.unpack_result(info, resultname, dep, destdir)
            if not rc then
                return false, e:cat(re)
            end
        end
        return true, nil
    end

    local function install_sources(info, resultname, return_flags)
        local res = result.results[resultname]
        local bc = res:buildconfig()
        local rc, re
        local e = err.new("installing sources")
        e2lib.log(3, "install sources")
        for sourcename in res:my_sources_list():iter_sorted() do
            local e = err.new("installing source failed: %s", sourcename)
            local destdir = e2lib.join(bc.T, "build")
            local source_set = res:get_build_mode().source_set()
            local rc, re = scm.prepare_source(info, sourcename, source_set,
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
        local rc, re = f(info, resultname, rflags)
        if not rc then
            return false, re
        end
    end
    return true, nil
end

--- deploy a result to the archive
-- @param info
-- @param resultname string: result name
-- @param tmpdir Directory containing the result etc.
-- @return bool
-- @return an error object on failure
local function deploy(info, resultname, tmpdir)
    --[[
    This function is given a temporary directory that contains
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
    local res = result.results[resultname]
    if not res:get_build_mode().deploy then
        e2lib.log(4, "deployment disabled for this build mode")
        return true
    end
    if not project.deploy_results_lookup(resultname) then
        e2lib.log(4, "deployment disabled for this result")
        return true
    end
    local files = {}
    local re

    local filesdir = e2lib.join(tmpdir, "result/files")
    local resdir = e2lib.join(tmpdir, "result")

    for f, re in e2lib.directory(filesdir) do
        if not f then
            return false, re
        end

        table.insert(files, e2lib.join("files", f))
    end
    table.insert(files, "checksums")
    local server, location = res:get_build_mode().deploy_storage(
        info.project_location, project.release_id())

    -- do not re-deploy if this release was already done earlier
    local location1 = e2lib.join(location, resultname, "checksums")
    local cache_flags = {
        cache = false,
    }
    local rc, re = cache.fetch_file(info.cache, server, location1, tmpdir,
        nil, cache_flags)
    if rc then
        e2lib.warnf("WOTHER",
            "Skipping deployment. This release was already deployed.")
        return true
    end


    e2lib.logf(1, "deploying %s to %s:%s", resultname, server, location)
    local cache_flags = {}

    for _,f in ipairs(files) do
        local sourcefile, location1

        sourcefile = e2lib.join(resdir, f)
        location1 = e2lib.join(location, resultname, f)
        rc, re = cache.push_file(info.cache, sourcefile, server, location1,
            cache_flags)
        if not rc then
            return false, re
        end
    end
    if cache.writeback_state(info.cache, server, cache_flags) == false then
        e2lib.warnf("WOTHER",
            "Writeback is disabled for server %q. Release not deployed!", server)
    end

    return true
end

--- store the result
-- @param info
-- @param resultname string: result name
-- @param return_flags table
-- @return bool
-- @return an error object on failure
local function store_result(info, resultname, return_flags)
    local res = result.results[resultname]
    local bc = res:buildconfig()
    local rc, re
    local e = err.new("fetching build results from chroot")
    local dt

    -- create a temporary directory to build up the result
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
    end

    -- build a stored result structure and store
    local rfilesdir = e2lib.join(bc.T, "out")
    local filesdir = e2lib.join(tmpdir, "result/files")
    local resdir = e2lib.join(tmpdir, "result")
    rc, re = e2lib.mkdir_recursive(filesdir)
    if not rc then
        return false, e:cat(re)
    end
    local nfiles = 0
    for f in e2lib.directory(rfilesdir, false, true) do
        e2lib.logf(3, "result file: %s", f)
        local s = e2lib.join(rfilesdir, f)
        local d = e2lib.join(filesdir, f)
        rc, re = e2lib.hardlink(s, d)
        if not rc then
            -- There are three reasons this might fail
            -- a) Legitimate IO etc. errors.
            -- b) Source and destination are not on the same filesystem.
            -- c) The file being linked to is owned by root, but the process is
            --    not root. It would be nice to fix this case by changing
            --    ownership of the source before copying, since this security
            --    feature (of recentish Linux) basically makes the optimization
            --    moot.
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

    dt = digest.new()
    for f,re in e2lib.directory(filesdir, false, true) do
        if not f then
            return false, e:cat(re)
        end

        digest.new_entry(dt, digest.SHA1, nil, e2lib.join("files", f), nil)
    end

    rc, re = digest.checksum(dt, resdir)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = digest.write(dt, e2lib.join(resdir, "checksums"))
    if not rc then
        return false, e:cat(re)
    end

    -- include compressed build logfile into the result tarball
    rc, re = e2lib.cp(bc.buildlog, e2lib.join(resdir, "build.log"))
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.gzip({ e2lib.join(resdir, "build.log") })
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2lib.tar({
        "-cf",  e2lib.join(tmpdir, "result.tar"),
        "-C", resdir, "." })
    if not rc then
        return false, e:cat(re)
    end
    local server, location = res:get_build_mode().storage(info.project_location,
        project.release_id())

    local buildid, re = e2tool.buildid(info, resultname)
    if not buildid then
        return false, re
    end

    local sourcefile = e2lib.join(tmpdir, "result.tar")
    local location1 = e2lib.join(location, resultname, buildid, "result.tar")
    local cache_flags = {
        try_hardlink = true,
    }
    rc, re = cache.push_file(info.cache, sourcefile, server,
        location1, cache_flags)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = deploy(info, resultname, tmpdir)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.rmtempdir(tmpdir)
    return true, nil
end

--- build a result
-- @param info
-- @param resultname string: result name
-- @param return_flags
-- @return bool
-- @return an error object on failure
local function build_result(info, resultname, return_flags)
    e2lib.logf(3, "building result: %s", resultname)
    local res = result.results[resultname]
    for _,f in ipairs(build_process) do
        local t1 = os.time()
        local flags = {}
        local rc, re = f.func(info, resultname, flags)
        local t2 = os.time()
        local deltat = os.difftime(t2, t1)
        e2lib.logf(3, "timing: step: %s [%s] %d", f.name, resultname, deltat)
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

--- Build a set of results.
-- @param info Info table.
-- @param results List of results, sorted by dependencies.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_results(info, results)
    e2lib.logf(3, "building results")

    for _, resultname in ipairs(results) do
        local e = err.new("building result failed: %s", resultname)
        local flags = {}
        local t1 = os.time()
        local rc, re = build_result(info, resultname, flags)
        if not rc then
            return false, e:cat(re)
        end
        local t2 = os.time()
        local deltat = os.difftime(t2, t1)
        e2lib.logf(3, "timing: result [%s] %d", resultname, deltat)
        if flags.stop then
            return true, nil
        end
    end

    return true, nil
end

--- Array of tables containing functions to drive the build process.
-- @table build_process
-- @see build_process_step
-- @see register_build_function

--- Table containing the function and name of a step in the build process.
-- @table build_process_step
-- @field name Name of build step (informative, string).
-- @field func Function to be called for each build step. The function
--             signature is function (info, result_name, return_flags).
-- @see build_process

--- Register a function to extend the build process.
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

--- TODO
build_process = {
    { name="build_config", func=e2build.build_config },
    { name="result_available", func=result_available },
    { name="chroot_lock", func=chroot_lock },
    { name="chroot_cleanup_if_exists", func=chroot_cleanup_if_exists },
    { name="setup_chroot", func=setup_chroot },
    { name="sources", func=sources },
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
