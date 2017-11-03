--- Core build logic
-- @module local.e2build

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

local e2build = {}
package.loaded["e2build"] = e2build

local cache = require("cache")
local chroot = require("chroot")
local class = require("class")
local digest = require("digest")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local project = require("project")
local result = require("result")
local source = require("source")
local strict = require("strict")
local tools = require("tools")

--- Return_flags table. Provide build status info back to the caller.
-- @table return_flags
-- @field stop boolean: stop the build process
-- @field message false or string with a message

--- Build process class. Every result is given to an instance of this class.
-- @type build_process_class
e2build.build_process_class = class("build_process_class")

---
function e2build.build_process_class:initialize()
    self._modes = {}

    self:add_step("build", "result_available", self._result_available)
    self:add_step("build", "chroot_lock", self._chroot_lock)
    self:add_step("build", "chroot_cleanup_if_exists",
        self._chroot_cleanup_if_exists)
    self:add_step("build", "setup_chroot", self._setup_chroot)
    self:add_step("build", "install_directory_structure",
        self._install_directory_structure)
    self:add_step("build", "install_build_script", self._install_build_script)
    self:add_step("build", "install_env", self._install_env)
    self:add_step("build", "install_init_files", self._install_init_files)
    self:add_step("build", "install_build_driver", self._install_build_driver)
    self:add_step("build", "install_build_time_dependencies",
        self._install_build_time_dependencies)
    self:add_step("build", "install_sources", self._install_sources)
    self:add_step("build", "fix_permissions", self._fix_permissions)
    self:add_step("build", "build_playground", self._build_playground)
    self:add_step("build", "runbuild", self._runbuild)
    self:add_step("build", "store_result", self._store_result)
    self:add_step("build", "linklast", self._linklast)
    self:add_step("build", "chroot_cleanup", self._chroot_cleanup)
    self:add_step("build", "chroot_unlock", self._chroot_unlock)

    self:add_step("playground", "chroot_exists", self._chroot_exists)
    self:add_step("playground", "enter_playground", self._enter_playground)
end

--- Build one result.
-- @param res Result object
-- @param process_mode Build process mode.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_process_class:build(res, process_mode)
    assert(res:isInstanceOf(result.basic_result))
    e2lib.logf(3, "building result: %s", res:get_name())


    for step in self:_next_step(process_mode) do
        local rc, re
        local t1, t2, deltat
        local return_flags = strict.lock({
            stop = false,
            message = false
        })

        t1 = os.time()
        rc, re = step.func(self, res, return_flags)
        t2 = os.time()
        deltat = os.difftime(t2, t1)

        e2lib.logf(3, "timing: step: %s [%s] %d", step.name, res:get_name(), deltat)

        if not rc then
            -- do not insert an error message from this layer.
            return false, re
        end
        if return_flags.message then
            e2lib.log(2, return_flags.message)
        end
        if return_flags.stop then
            -- stop the build process for this result
            return true
        end
    end

    return true
end

--- Add a build step
-- @param process_mode Build process mode
-- @param name Name of build step
-- @param func Method of build_process_class implementing the build step.
function e2build.build_process_class:add_step(process_mode, name, func)
    assertIsStringN(process_mode)
    assertIsStringN(name)
    assertIsFunction(func)

    self._modes = self._modes or {}
    self._modes[process_mode] = self._modes[process_mode] or {}
    table.insert(self._modes[process_mode], { name = name, func = func })
end

--- Add build step before specified.
-- @param process_mode Build process mode
-- @param before Add build step before this one
-- @param name Name of build step
-- @param func Method of build_process_class implementing the build step.
function e2build.build_process_class:add_step_before(process_mode, before, name, func)
    assertIsStringN(process_mode)
    assertIsStringN(before)
    assertIsStringN(name)
    assertIsFunction(func)
    assertIsTable(self._modes)
    assertIsTable(self._modes[process_mode])

    local pos = false

    for i = 1, #self._modes[process_mode] do
        local step = self._modes[process_mode][i]
        if step.name == before then
            pos = i
            break
        end
    end

    if not pos then
        error(err.new("add_step_before: no step called %s in mode %s", after, process_mode))
    end

    table.insert(self._modes[process_mode], pos, { name = name, func = func })
end

--- Add build step after specified.
-- @param process_mode Build process mode
-- @param after Add build step after this one
-- @param name Name of build step
-- @param func Method of build_process_class implementing the build step.
function e2build.build_process_class:add_step_after(process_mode, after, name, func)
    assertIsStringN(process_mode)
    assertIsStringN(after)
    assertIsStringN(name)
    assertIsFunction(func)
    assertIsTable(self._modes)
    assertIsTable(self._modes[process_mode])

    local pos = false

    for i = 1, #self._modes[process_mode] do
        local step = self._modes[process_mode][i]
        if step.name == after then
            pos = i
            break
        end
    end

    if not pos then
        error(err.new("add_step_after: no step called %s in mode %s", after, process_mode))
    end

    table.insert(self._modes[process_mode], pos + 1, { name = name, func = func })
end

--- Create new build settings instance for the desired process mode.
-- @param process_mode A process mode like "build" or "playground".
-- @return Build settings instance
-- @error Throws assertion/error on invalid process_mode.
function e2build.build_process_class:build_settings_new(process_mode)
    assertIsStringN(process_mode)

    if process_mode == "build" then
        return e2build.build_settings_class:new()
    elseif process_mode == "playground" then
        return e2build.playground_settings_class:new()
    end

    error("build_process_class:build_settings_new(): unknown process_mode")
end

--- Get/set the build process settings.
-- @param bs Build settings instance to set (optional).
-- @return Build settings instance.
-- @error Throws assertion if unset and on invalid input.
function e2build.build_process_class:build_settings(bs)
    if bs then
        assertIsTable(bs)
        self._build_settings = bs
    else
        assertIsTable(self._build_settings)
    end

    return self._build_settings
end

-- Get/set the build mode.
-- @param bm Build mode table to set (optional)
-- @return Build mode table.
-- @error Throws assertion if unset and on invalid input.
function e2build.build_process_class:build_mode(bm)
    if bm then
        assertIsTable(bm)
        self._build_mode = bm
    else
        assertIsTable(self._build_mode)
    end

    return self._build_mode
end

--- Iterator returns the next step in the chosen build process mode
-- @param process_mode Build process mode
-- @return Iterator function
function e2build.build_process_class:_next_step(process_mode)
    assertIsStringN(process_mode)
    assertIsTable(self._modes[process_mode])
    local i = 0

    return function()
        i = i + 1
        return self._modes[process_mode][i]
    end
end

--- check if a chroot exists for this result
-- @param res Result object
-- @param return_flags return_flags
-- @return True if chroot for result could be found, false otherwise.
function e2build.build_process_class:_chroot_exists(res, return_flags)
    local bc = res:build_config()
    if not e2lib.isfile(bc.chroot_marker) then
        return false, err.new("playground does not exist")
    end
    return true
end

--- Enter playground.
-- @param res Result object
-- @param return_flags return_flags
-- @return True on success, false on error.
-- @return Error object on failure.
function e2build.build_process_class:_enter_playground(res, return_flags)
    local rc, re, e, cmd, bc

    bc = res:build_config()
    e = err.new("entering playground")

    rc, re = eio.file_write(e2lib.join(bc.c, bc.profile),
        self:build_settings():profile())
    if not rc then
        error(e:cat(re))
    end

    cmd, re = tools.get_tool_flags_argv("e2-su-2.2")
    if not cmd then
        return false, e:cat(re)
    end

    table.insert(cmd, "chroot_2_3")
    table.insert(cmd, bc.base)

    if #bc.chroot_call_prefix > 0 then
        table.insert(cmd, 1, bc.chroot_call_prefix)
    end

    table.insert(cmd, "/bin/sh")
    table.insert(cmd, "-c")
    table.insert(cmd, self:build_settings():command())

    e2tool.set_umask()
    rc, re = e2lib.callcmd(cmd, {})
    if not rc then
        e2tool.reset_umask()
        return false, e:cat(re)
    end
    -- return code depends on user commands. Ignore.

    e2tool.reset_umask()

    return true
end

--- Return true if the result given in c is already available, false otherwise
-- return the path to the result
-- check if a result is already available
-- @param res Result object
-- @param return_flags return_flags
-- @return bool
-- @return an error object on failure
function e2build.build_process_class:_result_available(res, return_flags)
    local rc, re
    local buildid, sbid
    local e = err.new("error while checking if result is available: %s", res:get_name())
    local columns = tonumber(e2lib.globals.osenv["COLUMNS"])
    local e2project = e2tool.e2project()

    buildid, re = res:buildid()
    if not buildid then
        return false, e:cat(re)
    end

    sbid = string.format("%s...", string.sub(buildid, 1, 8))

    if self:build_settings():prep_playground() then
        return_flags.message = e2lib.align(columns,
            0, string.format("building %-20s", res:get_name()),
            columns, string.format("[%s] [playground]", sbid))
        return_flags.stop = false
        return true
    end
    if self:build_mode().source_set() == "working-copy" or
        self:build_settings():force_rebuild() then
        return_flags.message = e2lib.align(columns,
            0, string.format("building %-20s", res:get_name()),
            columns, string.format("[%s]", sbid))
        return_flags.stop = false
        return true
    end

    local server, location =
        self:build_mode().storage(
            e2project:project_location(), project.release_id())
    local result_location = e2lib.join(location, res:get_name(),
        buildid, "result.tar")

    rc, re = cache.file_exists(cache.cache(), server, result_location)
    if re then
        return false, e:cat(re)
    end

    if not rc then
        -- result is not available. Build.
        return_flags.message = e2lib.align(columns,
            0, string.format("building %-20s", res:get_name()),
            columns, string.format("[%s]", sbid))
        return_flags.stop = false

        return true
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

    rc, re = self:_linklast(res, return_flags)
    if not rc then
        return false, e:cat(re)
    end

    return_flags.message = e2lib.align(columns,
        0, string.format("skipping %-20s", res:get_name()),
        columns, string.format("[%s]", sbid))
    return_flags.stop = true

    return true
end

---
function e2build.build_process_class:_chroot_lock(res, return_flags)
    local rc, re, bc
    local e = err.new("error locking chroot")

    bc = res:build_config()
    rc, re = e2lib.mkdir_recursive(bc.c)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = e2lib.globals.lock:lock(bc.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

---
function e2build.build_process_class:helper_chroot_remove(res)
    local e = err.new("removing chroot failed")
    local rc, re, bc
    bc = res:build_config()
    e2tool.set_umask()
    rc, re = e2lib.e2_su_2_2({"remove_chroot_2_3", bc.base})
    e2tool.reset_umask()
    if not rc then
        return e:cat(re)
    end
    rc, re = e2lib.unlink(bc.chroot_marker)
    if not rc then
        return false, e:cat(re)
    end
    local f = e2lib.join(e2tool.root(), "playground")
    local s = e2lib.lstat(f)
    if s and s.type == "symbolic-link" then
        rc, re = e2lib.unlink(f)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true
end

---
function e2build.build_process_class:_chroot_cleanup_if_exists(res, return_flags)
    local rc, re

    rc, re = self:helper_chroot_remove(res)
    if not rc then
        return false, re
    end
    return true
end

---
function e2build.build_process_class:_setup_chroot(res, return_flags)
    local rc, re, bc
    local e = err.new("error setting up chroot")
    -- create the chroot path and create the chroot marker file without root
    -- permissions. That makes sure we have write permissions here.
    bc = res:build_config()
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

    e2tool.set_umask()
    rc, re = e2lib.e2_su_2_2({"set_permissions_2_3", bc.base})
    e2tool.reset_umask()
    if not rc then
        return false, e:cat(re)
    end

    local grp, path
    for cgrpnm in res:chroot_list():iter() do
        grp = chroot.groups_byname[cgrpnm]

        for file in grp:file_iter() do
            rc, re = file:checksum_verify()
            if not rc then
                return false, e:cat(re)
            end

            path, re = cache.fetch_file_path(cache.cache(), file:server(), file:location())
            if not path then
                return false, e:cat(re)
            end

            local tartype
            tartype, re = e2lib.tartype_by_suffix(path)
            if not tartype then
                return false, e:cat(re)
            end

            e2tool.set_umask()
            local argv = { "extract_tar_2_3", bc.base, tartype, path }
            rc, re = e2lib.e2_su_2_2(argv)
            e2tool.reset_umask()
            if not rc then
                return false, e:cat(re)
            end
        end
    end
    return true
end

---
function e2build.build_process_class:_install_directory_structure(res, return_flags)
    local rc, re, e, bc, dirs
    bc = res:build_config()
    dirs = {"out", "init", "script", "build", "root", "env", "dep"}
    for _, v in pairs(dirs) do
        rc, re = e2lib.mkdir_recursive(e2lib.join(bc.T, v))
        if not rc then
            e = err.new("installing directory structure")
            return false, e:cat(re)
        end
    end
    return true
end

---
function e2build.build_process_class:_install_build_script(res, return_flags)
    local rc, re, e, bc, location, destdir
    bc = res:build_config()
    location = e2tool.resultbuildscript(res:get_name_as_path())
    destdir = e2lib.join(bc.T, "script")

    rc, re = cache.fetch_file(cache.cache(), cache.server_names().dot,
        location, destdir)
    if not rc then
        e = err.new("installing build script")
        return false, e:cat(re)
    end
    return true
end

---
function e2build.build_process_class:_install_env(res, return_flags)
    local rc, re, e, bc
    e = err.new("installing environment files failed")
    bc = res:build_config()

    -- install builtin environment variables
    rc, re = bc.builtin_env:tofile(e2lib.join(bc.T, "env/builtin"))
    if not rc then
        return false, e:cat(re)
    end
    -- install project specific environment variables
    rc, re = res:merged_env():tofile(e2lib.join(bc.T, "env/env"))
    if not rc then
        return false, e:cat(re)
    end
    return true
end

---
function e2build.build_process_class:_install_init_files(res, return_flags)
    local rc, re
    local bc = res:build_config()
    local e = err.new("installing init files")

    for x, re in e2lib.directory(e2tool.root() .. "/proj/init") do
        if not x then
            return false, e:cat(re)
        end

        if not e2lib.is_backup_file(x) then
            local location = e2lib.join("proj/init", x)
            local abslocation = e2lib.join(e2tool.root(), location)
            local destdir = e2lib.join(bc.T, "init")

            if not e2lib.isfile(abslocation) then
                return false, e:append("'%s' is not a regular file",
                abslocation)
            end

            rc, re = cache.fetch_file(cache.cache(),
                cache.server_names().dot, location, destdir)
            if not rc then
                return false, e:cat(re)
            end
        end
    end
    return true
end

---
function e2build.build_process_class:_install_build_driver(res, return_flags)
    local e, rc, re
    local bc, bd, destdir, buildrc_noinit_file, buildrc_file
    local build_driver_file
    e = err.new("generating build driver script failed")

    bc = res:build_config()

    destdir = e2lib.join(bc.T, bc.scriptdir)

    bd = {
        string.format("source %s/env/builtin\n", bc.Tc),
        string.format("source %s/env/env\n", bc.Tc)
    }


    -- write buildrc file (for interactive use, without sourcing init files)
    buildrc_noinit_file = e2lib.join(destdir, bc.buildrc_noinit_file)
    rc, re = eio.file_write(buildrc_noinit_file, table.concat(bd))
    if not rc then
        return false, e:cat(re)
    end

    -- init files
    for fn, re in e2lib.directory(e2lib.join(e2tool.root(), "proj/init")) do
        if not fn then
            return false, e:cat(re)
        end

        if not e2lib.is_backup_file(fn) then
            table.insert(bd, string.format("source %s/init/%s\n", bc.Tc, fn))
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
    table.insert(bd, string.format("source %s/script/build-script\n", bc.Tc))

    -- write the build driver
    build_driver_file = e2lib.join(destdir, bc.build_driver_file)
    rc, re = eio.file_write(build_driver_file, table.concat(bd))
    if not rc then
        return false, e:cat(re)
    end

    return true
end

---
function e2build.build_process_class:helper_unpack_result(res, dep, destdir)
    local rc, re, e
    local buildid, server, location, resulttarpath, tmpdir
    local path, resdir, dt, filesdir, e2project, dep_bp

    e = err.new("unpacking result failed: %s", dep:get_name())

    e2project = e2tool.e2project()

    buildid, re = dep:buildid()
    if not buildid then
        return false, e:cat(re)
    end

    dep_bp = dep:build_process()
    server, location =
        dep_bp:build_mode().storage(e2project:project_location(), project.release_id())

    e2lib.logf(3, "searching for dependency %s in %s:%s",
        dep:get_name(), server, location)

    resulttarpath = e2lib.join(location, dep:get_name(), buildid, "result.tar")
    path, re = cache.fetch_file_path(cache.cache(), server, resulttarpath)
    if not path then
        return false, e:cat(re)
    end

    tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, e:cat(re)
    end

    resdir = e2lib.join(tmpdir, "result")
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
        e:append("checksum mismatch in dependency: %s", dep:get_name())
        return false, e:cat(re)
    end

    -- bc = dep:build_config()
    -- destdir = e2lib.join(bc.T, "dep", dep:get_name())

    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end
    filesdir = e2lib.join(resdir, "files")
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

    return true
end

---
function e2build.build_process_class:_install_build_time_dependencies(res, return_flags)
    local e, rc, re
    local dependslist, dep, destdir

    dependslist = res:depends_list()

    for dependsname in dependslist:iter() do
        dep = result.results[dependsname]
        destdir = e2lib.join(res:build_config().T, "dep", dep:get_name())

        rc, re = self:helper_unpack_result(res, dep, destdir)
        if not rc then
            return false, re
        end
    end

    return true
end

---
function e2build.build_process_class:_install_sources(res, return_flags)
    local rc, re, e, bc, destdir, source_set, src

    bc = res:build_config()
    destdir = e2lib.join(bc.T, "build")
    source_set = self:build_mode().source_set()

    for sourcename in res:sources_list():iter() do
        e = err.new("installing source failed: %s", sourcename)
        src = source.sources[sourcename]

        rc, re = src:prepare_source(source_set, destdir)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true
end

---
function e2build.build_process_class:_fix_permissions(res, return_flags)
    local rc, re, bc
    local e = err.new("fixing permissions failed")

    e2tool.set_umask()
    bc = res:build_config()
    local argv = { "chroot_2_3", bc.base, "chown", "-R", "root:root", bc.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask()
    if not rc then
        return false, e:cat(re)
    end
    e2tool.set_umask()
    argv = { "chroot_2_3", bc.base, "chmod", "-R", "u=rwX,go=rX", bc.Tc }
    rc, re = e2lib.e2_su_2_2(argv)
    e2tool.reset_umask()
    if not rc then
        return false, e:cat(re)
    end
    return true
end

---
function e2build.build_process_class:_build_playground(res, return_flags)

    if self:build_settings():prep_playground()  then
        return_flags.message = string.format("playground done for: %-20s", res:get_name())
        return_flags.stop = true
        return true
    end
    return true
end

---
function e2build.build_process_class:_runbuild(res, return_flags)
    local rc, re, out, bc, cmd
    local e = err.new("build failed")

    e2lib.logf(3, "building %s ...", res:get_name())

    bc = res:build_config()
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
        if e2lib.getlog(3) then
            -- no need to spam debug.log unless requested,
            -- we're already writing the same output to build.log
            e2lib.log(3, output)
        end
        eio.fwrite(out, output)
    end

    e2tool.set_umask()

    cmd, re = tools.get_tool_flags_argv("e2-su-2.2")
    if not cmd then
        return false, e:cat(re)
    end

    table.insert(cmd, "chroot_2_3")
    table.insert(cmd, bc.base)
    table.insert(cmd, "/bin/bash")
    table.insert(cmd, "-e")
    table.insert(cmd, "-x")
    table.insert(cmd, e2lib.join(bc.Tc, bc.scriptdir, bc.build_driver_file))

    if #bc.chroot_call_prefix > 0 then
        table.insert(cmd, 1, bc.chroot_call_prefix)
    end

    rc, re = e2lib.callcmd_capture(cmd, logto)
    if not rc then
        eio.fclose(out)
        return false, e:cat(re)
    end
    e2tool.reset_umask()
    if rc ~= 0 then
        eio.fclose(out)
        e = err.new("build script for %s failed with exit status %d", res:get_name(), rc)
        e:append("see %s for more information", bc.buildlog)
        return false, e
    end

    rc, re = eio.fclose(out)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- deploy a result to the archive
-- @param res
-- @param tmpdir Directory containing the result etc.
-- @return bool
-- @return an error object on failure
function e2build.build_process_class:helper_deploy(res, tmpdir)
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
    local e2project = e2tool.e2project()
    if not self:build_mode().deploy then
        e2lib.log(4, "deployment disabled for this build mode")
        return true
    end
    if not project.deploy_results_lookup(res:get_name()) then
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
    local server, location = self:build_mode().deploy_storage(
        e2project:project_location(), project.release_id())

    -- do not re-deploy if this release was already done earlier
    local location1 = e2lib.join(location, res:get_name(), "checksums")
    local cache_flags = {
        cache = false,
    }
    local rc, re = cache.fetch_file(cache.cache(), server, location1, tmpdir,
        nil, cache_flags)
    if rc then
        e2lib.warnf("WOTHER",
            "Skipping deployment. This release was already deployed.")
        return true
    end


    e2lib.logf(1, "deploying %s to %s:%s", res:get_name(), server, location)
    local cache_flags = {}

    for _,f in ipairs(files) do
        local sourcefile, location1

        sourcefile = e2lib.join(resdir, f)
        location1 = e2lib.join(location, res:get_name(), f)
        rc, re = cache.push_file(cache.cache(), sourcefile, server, location1,
            cache_flags)
        if not rc then
            return false, re
        end
    end
    if cache.writeback_enabled(cache.cache(), server, cache_flags) == false then
        e2lib.warnf("WOTHER",
            "Writeback is disabled for server %q. Release not deployed!", server)
    end

    return true
end

--- store the result
-- @param res
-- @param return_flags table
-- @return bool
-- @return an error object on failure
function e2build.build_process_class:_store_result(res, return_flags)
    local bc = res:build_config()
    local rc, re
    local e = err.new("fetching build results from chroot")
    local dt
    local e2project

    e2project = e2tool.e2project()

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

        -- Change owner and group of output files to match destination
        -- directory and make hardlink() happy on security sensitive kernels.
        local sb, re = e2lib.stat(filesdir)
        if not sb then
            return false, e:cat(re)
        end

        local argv = { "chroot_2_3", bc.base, "chown", "--",
            string.format("%s:%s", sb.uid, sb.gid),
            e2lib.join(bc.Tc, "out", f)
        }

        rc, re = e2lib.e2_su_2_2(argv)
        if not rc then
            return false, e:cat(re)
        end

        rc, re = e2lib.hardlink(s, d)
        if not rc then
            -- Hardlink may fail for two reasons:
            -- a) Legitimate IO etc. errors.
            -- b) Source and destination are not on the same filesystem.
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

    -- do not include the "." directory in result.tar
    local argv = { "-cf",  e2lib.join(tmpdir, "result.tar"), "-C", resdir, "--" }

    for entry, re in e2lib.directory(resdir, true) do
        if not entry then
            return false, e:cat(re)
        end
        table.insert(argv, entry)
    end
    rc, re = e2lib.tar(argv)
    if not rc then
        return false, e:cat(re)
    end

    local server, location = self:build_mode().storage(
        e2project:project_location(), project.release_id())

    local buildid, re = res:buildid()
    if not buildid then
        return false, re
    end

    local sourcefile = e2lib.join(tmpdir, "result.tar")
    local location1 = e2lib.join(location, res:get_name(), buildid, "result.tar")
    local cache_flags = {
        try_hardlink = true,
    }
    rc, re = cache.push_file(cache.cache(), sourcefile, server,
        location1, cache_flags)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = self:helper_deploy(res, tmpdir)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.rmtempdir(tmpdir)
    return true
end

---
function e2build.build_process_class:_linklast(res, return_flags)
    local rc, re, e
    local server, location, buildid, dst, lnk, e2project

    e = err.new("creating link to last results")
    e2project = e2tool.e2project()
    -- calculate the path to the result
    server, location = self:build_mode().storage(
        e2project:project_location(), project.release_id())

    -- compute the "last" link/directory
    buildid, re = res:buildid()
    if not buildid then
        return false, e:cat(re)
    end
    lnk = e2lib.join(e2tool.root(),  "out", res:get_name(), "last")
    location = e2lib.join(location, res:get_name(), buildid, "result.tar")

    -- if we don't have cache or server on local fs, fetch a copy into "out"
    if not cache.cache_enabled(cache.cache(), server) and not
        cache.islocal_enabled(cache.cache(), server) then
        e2lib.logf(3, "%s: copy to out/%s/last, server %q has no cache/not local",
            res:get_name(), res:get_name(), server)

        if e2lib.lstat(lnk) then
            e2lib.unlink_recursive(lnk) -- ignore errors
        end

        rc, re = e2lib.mkdir_recursive(lnk)
        if not rc then
            return e:cat(re)
        end

        rc, re = cache.fetch_file(cache.cache(), server, location, lnk, nil)
        if not rc then
            return false, e:cat(re)
        end

        return true
    else -- otherwise create a symlink
        dst, re = cache.fetch_file_path(cache.cache(), server, location)
        if not dst then
            return false, e:cat(re)
        end

        dst = e2lib.dirname(dst) -- we only care about the directory

        -- create the last link
        rc, re = e2lib.mkdir_recursive(e2lib.dirname(lnk))
        if not rc then
            return false, e:cat(re)
        end

        if e2lib.lstat(lnk) then
            e2lib.unlink_recursive(lnk) -- ignore errors, symlink will catch it
        end

        rc, re = e2lib.symlink(dst, lnk)
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

---
function e2build.build_process_class:_chroot_cleanup(res, return_flags)
    local rc, re
    -- do not remove chroot if the user requests to keep it
    if not self:build_settings():keep_chroot() then
        rc, re = self:helper_chroot_remove(res)
        if not rc then
            return false, re
        end
    end
    return true
end

---
function e2build.build_process_class:_chroot_unlock(res, return_flags)
    local rc, re, bc
    local e = err.new("error unlocking chroot")
    bc = res:build_config()
    rc, re = e2lib.globals.lock:unlock(bc.chroot_lock)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

--------------------------------------------------------------------------------
--- Base class for settings provided to the build process
-- @type settings_class
e2build.settings_class = class("settings")

--------------------------------------------------------------------------------
--- Build Settings class.
-- @type build_settings_class
e2build.build_settings_class = class("build_settings", e2build.settings_class)

---
function e2build.build_settings_class:initialize()
        self._selected = false
        self._force_rebuild = false
        self._keep_chroot = false
        self._prep_playground = false
end

---
function e2build.build_settings_class:force_rebuild(value)
    if value ~= nil then
        assertIsBoolean(value)
        self._force_rebuild = value
    end
    return self._force_rebuild
end

---
function e2build.build_settings_class:keep_chroot(value)
    if value ~= nil then
        assertIsBoolean(value)
        self._keep_chroot = value
    end
    return self._keep_chroot
end

---
function e2build.build_settings_class:prep_playground(value)
    if value ~= nil then
        assertIsBoolean(value)
        self._prep_playground = value
    end
    return self._prep_playground
end

--------------------------------------------------------------------------------
--- Playground Settings class.
-- @type playground_settings_class
e2build.playground_settings_class = class("playground_settings", e2build.settings_class)

---
function e2build.playground_settings_class:initialize()
    self._profile = false
    self._command = false
end

---
function e2build.playground_settings_class:profile(value)
    if value ~= nil then
        assertIsString(value)
        self._profile = value
    end
    assertIsString(self._profile)
    return self._profile
end

---
function e2build.playground_settings_class:command(value)
    if value ~= nil then
        assertIsString(value)
        self._command = value
    end
    assertIsString(self._command)
    return self._command
end

return strict.lock(e2build)

-- vim:sw=4:sts=4:et:
