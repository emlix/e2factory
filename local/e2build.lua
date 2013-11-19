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
local digest = require("digest")
local transport = require("transport")
local tools = require("tools")
local err = require("err")
local e2lib = require("e2lib")
local scm = require("scm")
local environment = require("environment")
local e2tool = require("e2tool")
local strict = require("strict")
local buildconfig = require("buildconfig")
local eio = require("eio")

-- Table driving the build process, see documentation at the bottom.
local build_process = {}

local function linklast(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("creating link to last results")
    -- calculate the path to the result
    local server, location = res.build_mode.storage(info.project_location,
        info.project.release_id)

    local buildid, re = e2tool.buildid(info, r)
    if not buildid then
        return false, e:cat(re)
    end
    local location1 = e2lib.join(location, r, buildid)
    local cache_flags = {
        check_only = true
    }
    local dst, re = info.cache:file_path(server, location1, cache_flags)
    if not dst then
        return false, e:cat(re)
    end
    -- create the last link
    local lnk_location = e2lib.join("out", r, "last")
    local lnk, re = info.cache:file_path(info.root_server_name, lnk_location)
    if not lnk then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir_recursive(e2lib.dirname(lnk))
    if not rc then
        return false, e:cat(re)
    end

    if e2lib.exists(lnk) then
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
-- @param r string: result name
-- @param return_flags table: return values through this table
-- @return bool
-- @return an error object on failure
local function result_available(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local buildid, sbid
    local e = err.new("error while checking if result is available: %s", r)
    local columns = tonumber(e2lib.globals.osenv["COLUMNS"])

    buildid, re = e2tool.buildid(info, r)
    if not buildid then
        return false, e:cat(re)
    end

    sbid = e2tool.bid_display(buildid)

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
    local server, location =
        res.build_mode.storage(info.project_location, info.project.release_id)
    local dep_set = res.build_mode.dep_set(buildid)

    -- cache the result
    local result_location = e2lib.join(location, r, dep_set, "result.tar")
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

--- Build config per result. This table is locked.
-- @table build_config
-- @field base       string: path to the build directory
-- @field c	     string: path to the chroot
-- @field chroot_marker string: path to chroot marker file
-- @field chroot_lock Path to chroot lock file (string).
-- @field T          string: absolute path to the temporary build directory
--                           inside chroot
-- @field Tc         string: same as c.T but relative to c
-- @field r          string: result name
-- @field chroot_call_prefix XXX
-- @field buildlog   string: build log file
-- @field scriptdir XXX
-- @field build_driver XXX
-- @field build_driver_file XXX
-- @field buildrc_file XXX
-- @field buildrc_noinit_file XXX
-- @field profile Configuration file passed to the shell (string).
-- @field groups     table of strings: chroot groups
-- @field builtin_env Environment that's built in like E2_TMPDIR.

--- Generate build_config and store in res.build_config.
-- @param info Info table.
-- @param r Result name (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_config(info, r)
    local e = err.new("setting up build configuration for result `%s' failed", r)
    local res = info.results[r]
    if not res then
        return false, e:append("no such result: %s", r)
    end

    local buildid, re = e2tool.buildid(info, r)
    if not buildid then
        return false, e:cat(re)
    end

    local bc = {}

    local tmpdir = string.format("%s/e2factory-%s.%s.%s-build/%s",
        e2lib.globals.tmpdir, buildconfig.MAJOR, buildconfig.MINOR,
        buildconfig.PATCHLEVEL, e2lib.globals.username)
    local builddir = "tmp/e2"

    bc.base = e2lib.join(tmpdir, info.project.name, r)
    bc.c = e2lib.join(bc.base, "chroot")
    bc.chroot_marker = e2lib.join(bc.base, "e2factory-chroot")
    bc.chroot_lock = e2lib.join(bc.base, "e2factory-chroot-lock")
    bc.T = e2lib.join(tmpdir, info.project.name, r, "chroot", builddir)
    bc.Tc = e2lib.join("/", builddir)
    bc.r = r
    if info.chroot_call_prefix[info.project.chroot_arch] == "" then
        -- escape only if non-empty, otherwise we fail to start "''"
        tab.chroot_call_prefix = ""
    else
        tab.chroot_call_prefix =
            e2lib.shquote(info.chroot_call_prefix[info.project.chroot_arch])
    end
    bc.buildlog = string.format("%s/log/build.%s.log", info.root, r)
    bc.scriptdir = "script"
    bc.build_driver = ""
    bc.build_driver_file = "build-driver"
    bc.buildrc_file = "buildrc"
    bc.buildrc_noinit_file = "buildrc-noinit"
    bc.profile = "/tmp/bashrc"

    bc.groups = {}
    for _,g in ipairs(res.chroot) do
        bc.groups[g] = true
    end

    bc.builtin_env = environment.new()
    bc.builtin_env:set("E2_TMPDIR", bc.Tc)
    bc.builtin_env:set("E2_RESULT", r)
    bc.builtin_env:set("E2_RELEASE_ID", info.project.release_id)
    bc.builtin_env:set("E2_PROJECT_NAME", info.project.name)
    bc.builtin_env:set("E2_BUILDID", buildid)
    bc.builtin_env:set("T", bc.Tc)
    bc.builtin_env:set("r", r)
    bc.builtin_env:set("R", r)

    res.build_config = strict.lock(bc)

    return true
end

local function chroot_lock(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("error locking chroot")
    rc, re = e2lib.mkdir_recursive(res.build_config.c)
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
    rc, re = e2lib.mkdir_recursive(res.build_config.c)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = eio.fopen(res.build_config.chroot_marker, "w")
    if not rc then
        return false, e:cat(re)
    end

    local cm = rc

    rc, re = eio.fclose(cm)
    if not rc then
        return false, e:cat(re)
    end

    e2tool.set_umask(info)
    rc, re = e2lib.e2_su_2_2({"set_permissions_2_3", res.build_config.base})
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

--- Enter playground.
-- @param info
-- @param r
-- @param chroot_command (optional)
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.enter_playground(info, r, chroot_command)
    local rc, re, e, res, e2_su, cmd

    if not chroot_command then
        chroot_command = "/bin/bash"
    end

    res = info.results[r]
    e = err.new("entering playground")

    e2_su = tools.get_tool("e2-su-2.2")
    if not e2_su then
        return false, e:cat(re)
    end

    cmd = string.format("%s %s chroot_2_3 '%s' %s",
        res.build_config.chroot_call_prefix, e2_su,
        res.build_config.base, chroot_command)
    e2tool.set_umask(info)
    -- return code depends on user commands. Ignore.
    os.execute(cmd)
    e2tool.reset_umask(info)

    return true
end

local function fix_permissions(info, r, return_flags)
    local res = info.results[r]
    local rc, re
    local e = err.new("fixing permissions failed")
    e2lib.log(3, "fix permissions")
    e2tool.set_umask(info)
    local argv = { "chroot_2_3", res.build_config.base, "chown", "-R",
    "root:root", res.build_config.Tc }
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
    e2lib.logf(3, "building %s ...", r)
    local runbuild = string.format("/bin/bash -e -x %s/%s/%s",
        e2lib.shquote(res.build_config.Tc),
        e2lib.shquote(res.build_config.scriptdir),
        e2lib.shquote(res.build_config.build_driver_file))
    local e2_su, re = tools.get_tool("e2-su-2.2")
    if not e2_su then
        return false, e:cat(re)
    end
    local cmd = string.format("%s %s chroot_2_3 %s %s",
        res.build_config.chroot_call_prefix,
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
    rc, re = e2lib.callcmd_capture(cmd, logto)
    if not rc then
        return false, e:cat(re)
    end
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
    rc, re = e2lib.unlink(res.build_config.chroot_marker)
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
    local e = err.new("unpacking result failed: %s", dep)
    local d = info.results[dep]
    local dt

    local buildid, re = e2tool.buildid(info, dep)
    if not buildid then
        return false, re
    end

    local dep_set = d.build_mode.dep_set(buildid)
    local server, location =
        d.build_mode.storage(info.project_location, info.project.release_id)
    e2lib.logf(3, "searching for dependency %s in %s:%s", dep, server, location)
    local location1 = e2lib.join(location, dep, dep_set, "result.tar")
    local cache_flags = {}
    local path, re = info.cache:file_path(server, location1, cache_flags)
    if not path then
        return false, e:cat(re)
    end
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
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

    dt, re = digest.parse("checksums")
    if not dt then
        return false, e:cat(re)
    end

    rc, re = digest.verify(dt, e2lib.cwd())
    if not rc then
        e:append("checksum mismatch in dependency: %s", dep)
        return false, e:cat(re)
    end

    rc, re = e2lib.chdir("files")
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end
    for f, re in e2lib.directory(".") do
        if not f then
            return false, e:cat(re)
        end

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
    local res = info.results[r]
    local rc, re
    local e = err.new("generating build driver script failed")
    local buildrc_file = e2lib.join(destdir, res.build_config.buildrc_file)
    local buildrc_noinit_file =
        e2lib.join(destdir, res.build_config.buildrc_noinit_file)
    local build_driver_file =
        e2lib.join(destdir, res.build_config.build_driver_file)
    local bd = ""
    bd=bd..string.format("source %s/env/builtin\n", res.build_config.Tc)
    bd=bd..string.format("source %s/env/env\n", res.build_config.Tc)
    local brc_noinit = bd
    for x, re in e2lib.directory(e2lib.join(info.root, "proj/init")) do
        if not x then
            return false, e:cat(re)
        end

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
            local d = e2lib.join(res.build_config.T, v)
            local rc, re = e2lib.mkdir_recursive(d)
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
        local destdir = e2lib.join(res.build_config.T, "script")
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
        local file = e2lib.join(res.build_config.T, "env/builtin")
        rc, re = write_environment_script(res.build_config.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        append_to_build_driver(info, r, string.format("source %s/env/builtin",
        res.build_config.Tc))
        -- install project specific environment variables
        local file = e2lib.join(res.build_config.T, "env/env")
        rc, re = write_environment_script(e2tool.env_by_result(info, r), file)
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
        for x, re in e2lib.directory(info.root .. "/proj/init") do
            if not x then
                return false, e:cat(re)
            end

            if not e2lib.is_backup_file(x) then
                local location = e2lib.join("proj/init", x)
                local abslocation = e2lib.join(info.root, location)
                local destdir = e2lib.join(res.build_config.T, "init")

                if not e2lib.isfile(abslocation) then
                    return false, e:append("'%s' is not a regular file",
                        abslocation)
                end

                rc, re = transport.fetch_file(info.root_server, location, destdir)
                if not rc then
                    return false, e:cat(re)
                end
                append_to_build_driver(info, r,
                    string.format("source %s/init/%s", res.build_config.Tc, x))
            end
        end
        return true, nil
    end

    local function install_build_driver(info, r, return_flags)
        local res = info.results[r]
        local rc, re
        local e = err.new("writing build driver script failed")
        local bc = res.build_config
        local destdir = e2lib.join(bc.T, bc.scriptdir)
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
        local deps
        deps = e2tool.get_depends(info, r)
        for i, dep in pairs(deps) do
            local destdir = e2lib.join(res.build_config.T, "dep", dep)
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
            local destdir = e2lib.join(res.build_config.T, "build")
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
        e2lib.log(4, "deployment disabled for this build mode")
        return true
    end
    if not res._deploy then
        e2lib.log(4, "deployment disabled for this result")
        return true
    end
    local files = {}
    local re
    for f, re in e2lib.directory("result/files") do
        if not f then
            return false, re
        end

        table.insert(files, e2lib.join("files", f))
    end
    table.insert(files, "checksums")
    local server, location = res.build_mode.deploy_storage(
        info.project_location, info.project.release_id)

    -- do not re-deploy if this release was already done earlier
    local location1 = e2lib.join(location, r, "checksums")
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
        local sourcefile = e2lib.join("result", f)
        local location1 = e2lib.join(location, r, f)
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
    local res = info.results[r]
    local rc, re
    local e = err.new("fetching build results from chroot")
    local dt

    -- create a temporary directory to build up the result
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
    end

    -- build a stored result structure and store
    local rfilesdir = e2lib.join(res.build_config.T, "out")
    rc, re = e2lib.chdir(tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.mkdir_recursive("result/files")
    if not rc then
        return false, e:cat(re)
    end
    local nfiles = 0
    for f in e2lib.directory(rfilesdir, false, true) do
        e2lib.logf(3, "result file: %s", f)
        local s = e2lib.join(rfilesdir, f)
        local d = "result/files"
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
    rc, re = e2lib.chdir("result")
    if not rc then
        return false, e:cat(re)
    end

    dt = digest.new()
    for f,re in e2lib.directory("files", false, true) do
        if not f then
            return false, e:cat(re)
        end

        digest.new_entry(dt, digest.SHA1, nil, e2lib.join("files", f), nil)
    end

    rc, re = digest.checksum(dt, e2lib.cwd())
    if not rc then
        return false, e:cat(re)
    end

    rc, re = digest.write(dt, "checksums")
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
        info.project.release_id)

    local buildid, re = e2tool.buildid(info, r)
    if not buildid then
        return false, re
    end

    local sourcefile = e2lib.join(tmpdir, "result.tar")
    local location1 = e2lib.join(location, r, buildid, "result.tar")
    local cache_flags = {
        try_hardlink = true,
    }
    rc, re = info.cache:push_file(sourcefile, server, location1, cache_flags)
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
-- @param return_flags
-- @return bool
-- @return an error object on failure
local function build_result(info, result, return_flags)
    e2lib.logf(3, "building result: %s", result)
    local res = info.results[result]
    for _,f in ipairs(build_process) do
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

--- Build a set of results.
-- @param info Info table.
-- @param results List of results, sorted by dependencies.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_results(info, results)
    e2lib.logf(3, "building results")

    for _, r in ipairs(results) do
        local e = err.new("building result failed: %s", r)
        local flags = {}
        local t1 = os.time()
        local rc, re = build_result(info, r, flags)
        if not rc then
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

--- collect all data required to build the project.
-- skip results that depend on this result
-- example: toolchain, busybox, sources, iso,
-- sources being the result collecting the project:
-- the results sources and iso won't be included, as that would lead to
-- an impossibility to calculate buildids (infinite recursion)
-- @param info info table
-- @param r
-- @param return_flags
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
    local destdir = e2lib.join(res.build_config.T, "project/proj/init")
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    for f, re in e2lib.directory(e2lib.join(info.root, "proj/init"), false) do
        if not f then
            return false, e:cat(re)
        end

        e2lib.logf(3, "init file: %s", f)
        local server = "."
        local location = e2lib.join("proj/init", f)
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
    destdir = e2lib.join(res.build_config.T, "project/proj")
    file = e2lib.join(destdir, "config")
    local f, msg = io.open(file, "w")
    if not f then
        return false, e:cat(re)
    end
    f:write(string.format("name='%s'\n", info.project.name))
    f:write(string.format("release_id='%s'\n", info.project.release_id))
    f:write(string.format("default_results='%s'\n",
    res.collect_project_default_result))
    f:write(string.format("chroot_arch='%s'\n",
    info.project.chroot_arch))
    f:close()
    -- files from the project
    local destdir = e2lib.join(res.build_config.T, "project/.e2/bin")
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    -- generate build driver file for each result
    -- project/chroot/<group>/<files>
    for _,g in pairs(res.collect_project_chroot_groups) do
        e2lib.logf(3, "chroot group: %s", g)
        local grp = info.chroot.groups_byname[g]
        local destdir = e2lib.join( res.build_config.T, "project/chroot", g)
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        local makefile, msg = io.open(e2lib.join(destdir, "Makefile"), "w")
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
                rc, re = eio.file_write(checksum_file,
                    string.format("%s  %s", file.sha1, filename))
                if not rc then
                    return false, e:cat(re)
                end
                makefile:write(string.format("\tsha1sum -c '%s'\n",
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
        local destdir = e2lib.join(res.build_config.T, "project/licences", l)
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

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
        e2lib.logf(3, "result: %s", n)
        local rn = info.results[n]
        rc, re = e2build.build_config(info, n)
        if not rc then
            return false, e:cat(re)
        end
        local destdir =
            e2lib.join(res.build_config.T, "project", e2tool.resultdir(n))
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

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
        file = e2lib.join(destdir, "env")
        rc, re = write_environment_script(e2tool.env_by_result(info, n), file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate builtin environment script
        local file = e2lib.join(destdir, "builtin")
        rc, re = write_environment_script(rn.build_config.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate build driver
        rc, re = write_build_driver(info, n, destdir)
        if not rc then
            return false, e:cat(re)
        end
        -- generate config
        local config = e2lib.join(destdir, "config")
        local f, msg = io.open(config, "w")
        if not f then
            e:cat(err.new("%s: %s", config, msg))
            return false, e
        end
        f:write(string.format("### generated by e2 for result %s ###\n", n))
        f:write(string.format("CHROOT='%s'\n", table.concat(rn.chroot, " ")))
        f:write(string.format("DEPEND='%s'\n", table.concat(rn.depends, " ")))
        f:write(string.format("SOURCE='%s'\n", table.concat(rn.sources, " ")))
        f:close()
    end
    for _,s in ipairs(info.results[r].collect_project_sources) do
        local src = info.sources[s]
        e2lib.logf(3, "source: %s", s)
        local destdir =
            e2lib.join(res.build_config.T, "project", e2tool.sourcedir(s))
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        local source_set = res.build_mode.source_set()
        local files, re = scm.toresult(info, src.name, source_set,
        destdir)
        if not files then
            return false, e:cat(re)
        end
    end
    -- write topologically sorted list of result
    local destdir = e2lib.join(res.build_config.T, "project")
    local tsorted_results, re = e2tool.dlist_recursive(info,
    res.collect_project_results)
    if not tsorted_results then
        return false, e:cat(re)
    end
    local tsorted_results_string = table.concat(tsorted_results, "\n")
    local resultlist = e2lib.join(destdir, "resultlist")
    rc, re = eio.file_write(resultlist, tsorted_results_string .. "\n")
    if not rc then
        return false, e:cat(re)
    end
    -- install the global Makefiles
    local server = "."
    local destdir = e2lib.join(res.build_config.T, "project")
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
        rc, re = e2lib.chmod(e2lib.join(destdir, f), "755")
        if not rc then
            return false, e:cat(re)
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

build_process = {
    { name="build_config", func=e2build.build_config },
    { name="result_available", func=result_available },
    { name="chroot_lock", func=chroot_lock },
    { name="chroot_cleanup_if_exists", func=chroot_cleanup_if_exists },
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
