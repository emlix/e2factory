--- Collect_project Plugin. Turns a e2factory project into a make
-- based project tar archive.
-- @module plugins.collect_project

-- Copyright (C) 2007-2014 emlix GmbH, see file AUTHORS
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
local chroot = require("chroot")
local class = require("class")
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local project = require("project")
local projenv = require("projenv")
local result = require("result")
local scm = require("scm")
local sl = require("sl")
local source = require("source")
local strict = require("strict")

local cp_build_process_class = class("cp_build_process_class",
    e2build.build_process_class)

local collect_project_class = class("collect_project_class",
    result.basic_result)

function collect_project_class:initialize(rawres)
    assertIsTable(rawres)
    assertNotNil(rawres.collect_project)
    assertStrMatches(rawres.type, "collect_project")

    result.basic_result.initialize(self, rawres)

    self._buildid = false
    self._default_result = false
    self._chroot_list = sl.sl:new(false, true)
    self._env = environment.new()

    local rc, re, e

    e = err.new("in result %s:", self:get_name())
    if type(rawres.collect_project) ~= "boolean"
        or rawres.collect_project ~= true then
        error(e:append("collect_project must be true"))
    end

    rc, re = e2lib.vrfy_dict_exp_keys(rawres, "e2result config", {
        "chroot",
        "collect_project",
        "collect_project_default_result",
        "env",
        "name",
        "type",
    })
    if not rc then
        error(e:cat(re))
    end

    if type(rawres.collect_project) ~= "boolean" then
        e:append("collect_project is not a boolean")
    elseif rawres.collect_project == false then
        e:append("'collect_project' cannot be false")
    end

    if rawres.collect_project_default_result == nil then
        e:append("collect_project_default_result is not set")
    elseif type(rawres.collect_project_default_result) ~= "string" then
        e:append("collect_project_default_result is not a string")
    else
        self._default_result = rawres.collect_project_default_result
    end

    -- Logic stolen from result_class
    if rawres.chroot == nil then
        e2lib.warnf("WDEFAULT", "in result %s:", self._name)
        e2lib.warnf("WDEFAULT", " chroot groups not configured. " ..
            "Defaulting to empty list")
        rawres.chroot = {}
    elseif type(rawres.chroot) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", self._name)
        e2lib.warnf("WDEPRECATED", " chroot attribute is string. "..
            "Converting to list")
        rawres.chroot = { rawres.chroot }
    end
    rc, re = e2lib.vrfy_listofstrings(rawres.chroot, "chroot", true, false)
    if not rc then
        e:append("chroot attribute:")
        e:cat(re)
    else
        -- apply default chroot groups
        for _,g in ipairs(chroot.groups_default) do
            table.insert(rawres.chroot, g)
        end
        -- The list may have duplicates now. Unify.
        rc, re = e2lib.vrfy_listofstrings(rawres.chroot, "chroot", false, true)
        if not rc then
            e:append("chroot attribute:")
            e:cat(re)
        end
        for _,g in ipairs(rawres.chroot) do
            if not chroot.groups_byname[g] then
                e:append("chroot group does not exist: %s", g)
            end

            self:my_chroot_list():insert(g)
        end
    end

    if rawres.env and type(rawres.env) ~= "table" then
        e:append("result has invalid `env' attribute")
    else
        if not rawres.env then
            e2lib.warnf("WDEFAULT", "result has no `env' attribute. "..
                "Defaulting to empty dictionary")
            rawres.env = {}
        end

        for k,v in pairs(rawres.env) do
            if type(k) ~= "string" then
                e:append("in `env' dictionary: "..
                "key is not a string: %s", tostring(k))
            elseif type(v) ~= "string" then
                e:append("in `env' dictionary: "..
                "value is not a string: %s", tostring(v))
            else
                self._env:set(k, v)
            end
        end
    end

    local info = e2tool.info()
    local build_script =
        e2tool.resultbuildscript(self:get_name_as_path(), info.root)
    if not e2lib.isfile(build_script) then
        e:append("build-script does not exist: %s", build_script)
    end

    if e:getcount() > 1 then
        error(e)
    end
end

function collect_project_class:post_initialize()
    assertIsString(self:default_result())
    local e, re, rc, dependsvec

    e = err.new("in result %s:", self:get_name())

    if not result.results[self:default_result()] then
        e:append("collect_project_default_result is set to "..
            "an invalid result: %s", self:default_result())
        return false, e
    end

    return true
end

function collect_project_class:default_result()
    return self._default_result
end

function collect_project_class:my_chroot_list()
    return self._chroot_list
end

function collect_project_class:dlist()
    return { self:default_result() }
end

function collect_project_class:my_sources_list()
    return sl.sl:new(true, false)
end

function collect_project_class:merged_env()
    local e = environment.new()

    -- Global env
    e:merge(projenv.get_global_env(), false)

    -- Global result specific env
    e:merge(projenv.get_result_env(self._name), true)

    -- Result specific env
    e:merge(self._env, true)

    return e
end

function collect_project_class:buildid()
    local e, re, hc, id

    if self._buildid then
        return self._buildid
    end

    e = err.new("error calculating BuildID for result: %s", self:get_name())
    hc = hash.hash_start()

    -- basic_result
    hash.hash_append(hc, self:get_name())
    hash.hash_append(hc, self:get_type())

    -- chroot
    local info = e2tool.info()
    for groupname in self:my_chroot_list():iter_sorted() do

        id, re = chroot.groups_byname[groupname]:chrootgroupid(info)
        if not id then
            return false, e:cat(re)
        end
        hash.hash_append(hc, id)
    end

    -- buildscript
    local file = {
        server = cache.server_names().dot,
        location = e2tool.resultbuildscript(self:get_name_as_path()),
    }

    id, re = e2tool.fileid(info, file)
    if not id then
        return false, re
    end
    hash.hash_append(hc, id)

    -- env
    hash.hash_append(hc, self:merged_env():id())

    -- default_result
    id, re = result.results[self:default_result()]:buildid()
    if not id then
        return false, e:cat(re)
    end
    hash.hash_append(hc, id)

    -- projectid
    id, re = project.projid(info)
    if not id then
        return false, e:cat(re)
    end
    hash.hash_append(hc, id)

    self._buildid = hash.hash_finish(hc)

    return self._buildid
end

function collect_project_class:build_process()
    assertIsTable(self._build_mode)
    assertIsTable(self._build_settings)
    return cp_build_process_class:new()
end

function collect_project_class:attribute_table(flagt)
    local t = {}
    flagt = flagt or {}
    table.insert(t, {"type", self:get_type()})
    table.insert(t, {"collect_project_default_result", self._default_result})
    if flagt.chroot then
        table.insert(t, {"chroot", self:my_chroot_list():unpack()})
    end
    if flagt.env then
        local tenv = { "env" }
        for k, v in self:merged_env():iter() do
            table.insert(tenv, string.format("%s=%s", k, v))
        end
        table.insert(t, tenv)
    end
    return t
end

function cp_build_process_class:initialize()
    e2build.build_process_class.initialize(self)

    self:add_step_before("build", "fix_permissions", "build_collect_project",
        self._build_collect_project)
end

--- Create Makefile based structure required to build the project
-- without e2factory
-- @param res Result object
-- @param return_flags
-- @return bool
-- @return an error object on failure
function cp_build_process_class:_build_collect_project(res, return_flags)

    local function write_build_driver(info, resultname, destdir)
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

    local out, rc, re, info
    local bc = res:buildconfig()
    local e = err.new("providing project data to this build failed")
    local cp_sources = sl.sl:new(true, false)
    local cp_depends = sl.sl:new(true, false)
    local cp_chroot = sl.sl:new(true, false)
    local cp_licences = sl.sl:new(true, false)

    info = e2tool.info()

    -- calculate depends, sources, licences and chroot
    rc, re = e2tool.dlist_recursive({res:default_result()})
    if not rc then
        return false, e:cat(re)
    end
    cp_depends:insert_table(rc)

    for depname in cp_depends:iter_sorted() do
        local dep = result.results[depname]

        if not dep:isInstanceOf(result.result_class) then
            return false,
                e:append("collect_project cannot work with this result type: %q",
                    dep:get_name())
        end
        cp_chroot:insert_sl(dep:my_chroot_list())
        cp_sources:insert_sl(dep:my_sources_list())
    end

    for sourcename in cp_sources:iter_sorted() do
        local src = source.sources[sourcename]
        cp_licences:insert_sl(src:get_licences())
    end

    -- project/proj/init/<files>
    local destdir = e2lib.join(bc.T, "project/proj/init")

    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    for f, re in e2lib.directory(e2lib.join(info.root, "proj/init"), false) do
        if not f then
            return false, e:cat(re)
        end

        e2lib.logf(3, "init file: %s", f)
        local server = cache.server_names().dot
        local location = e2lib.join("proj/init", f)
        local cache_flags = {}
        rc, re = cache.fetch_file(info.cache, server, location,
            destdir, nil, cache_flags)
        if not rc then
            return false, e:cat(re)
        end
    end

    -- write project configuration
    out = {
        string.format("name='%s'\n", project.name()),
        string.format("release_id='%s'\n", project.release_id()),
        string.format("default_results='%s'\n", res:default_result()),
        string.format("chroot_arch='%s'\n", project.chroot_arch())
    }

    local file, destdir
    destdir = e2lib.join(bc.T, "project/proj")
    file = e2lib.join(destdir, "config")
    rc, re = eio.file_write(file, table.concat(out))
    if not rc then
        return false, e:cat(re)
    end

    -- generate build driver file for each result
    -- project/chroot/<group>/<files>
    for g in cp_chroot:iter_sorted() do
        e2lib.logf(3, "chroot group: %s", g)
        local grp = chroot.groups_byname[g]
        local destdir = e2lib.join(bc.T, "project/chroot", g)
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        out = { "place:\n" }

        for file in grp:file_iter() do
            local cache_flags = {}
            rc, re = cache.fetch_file(info.cache, file.server,
                file.location, destdir, nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
            if file.sha1 then
                local checksum_file = string.format(
                    "%s/%s.sha1", destdir, e2lib.basename(file.location))
                local filename = e2lib.basename(file.location)
                rc, re = eio.file_write(checksum_file,
                    string.format("%s  %s", file.sha1, filename))
                if not rc then
                    return false, e:cat(re)
                end
                table.insert(out, string.format("\tsha1sum -c '%s'\n",
                    e2lib.basename(checksum_file)))
            end
            local tartype
            tartype, re = e2lib.tartype_by_suffix(file.location)
            if not tartype then
                return false, e:cat(re)
            end
            table.insert(out, string.format(
                "\te2-su-2.2 extract_tar_2_3 $(chroot_base) \"%s\" '%s'\n",
                tartype, e2lib.basename(file.location)))
        end

        local makefile = e2lib.join(destdir, "Makefile")
        rc, re = eio.file_write(makefile, table.concat(out))
        if not rc then
            return false, e:cat(re)
        end
    end

    -- project/licences/<licence>/<files>
    for licname in cp_licences:iter_sorted() do
        local lic = licence.licences[licname]
        e2lib.logf(3, "licence: %s", lic:get_name())
        local destdir =
            e2lib.join(bc.T, "project/licences", lic:get_name())
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        for file in lic:file_iter() do
            local cache_flags = {}
            if file.sha1 then
                rc, re = e2tool.verify_hash(info, file)
                if not rc then
                    return false, e:cat(re)
                end
            end
            rc, re = cache.fetch_file(info.cache, file.server, file.location,
                destdir, nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
    end

    -- project/results/<res>/<files>
    for depname in cp_depends:iter_sorted() do
        e2lib.logf(3, "result: %s", depname)
        local dep = result.results[depname]
        local depbc = dep:buildconfig()

        local destdir =
            e2lib.join(bc.T, "project", e2tool.resultdir(depname))
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        -- copy files
        local files = {
            e2tool.resultbuildscript(dep:get_name_as_path())
        }
        for _,file in pairs(files) do
            local server = cache.server_names().dot
            local cache_flags = {}
            rc, re = cache.fetch_file(info.cache, server, file, destdir,
                nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
        local file, line
        -- generate environment script
        file = e2lib.join(destdir, "env")
        rc, re = environment.tofile(dep:merged_env(), file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate builtin environment script
        local file = e2lib.join(destdir, "builtin")
        rc, re = environment.tofile(depbc.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate build driver
        rc, re = write_build_driver(info, depname, destdir)
        if not rc then
            return false, e:cat(re)
        end
        -- generate config
        out = {
            string.format("### generated by e2factory for result %s ###\n", depname),
            string.format("CHROOT='%s'\n", dep:my_chroot_list():concat_sorted(" ")),
            string.format("DEPEND='%s'\n", dep.XXXdepends:concat_sorted(" ")),
            string.format("SOURCE='%s'\n", dep:my_sources_list():concat_sorted(" ")),
        }

        local config = e2lib.join(destdir, "config")
        rc, re = eio.file_write(config, table.concat(out))
        if not rc then
            return false, e:cat(re)
        end
    end

    for sourcename in cp_sources:iter_sorted() do
        e2lib.logf(3, "source: %s", sourcename)
        local destdir = e2lib.join(bc.T, "project",
            e2tool.sourcedir(sourcename))
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        local source_set = res:build_mode().source_set()
        local files, re = scm.toresult(info, sourcename, source_set, destdir)
        if not files then
            return false, e:cat(re)
        end
    end

    -- write topologically sorted list of result
    local destdir = e2lib.join(bc.T, "project")
    local tsorted_results, re =
        e2tool.dlist_recursive(cp_depends:totable_sorted())
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
    local server = cache.server_names().dot
    local destdir = e2lib.join(bc.T, "project")
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
        rc, re = cache.fetch_file(info.cache, server, location,
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
    return true
end

local function detect_cp_result(rawres)
    assertIsTable(rawres)

    if rawres.collect_project ~= nil then
        rawres.type = "collect_project"
        return true
    end

    return false
end

local function collect_project_init(ctx)
    local rc, re

    rc, re = result.register_type_detection(detect_cp_result)
    if not rc then
        return false, re
    end

    rc, re = result.register_result_class("collect_project",
        collect_project_class)
    if not rc then
        return false, re
    end

    return true
end

local function collect_project_exit(ctx)
    return true
end

plugin_descriptor = {
    description = "collect_project Plugin",
    init = collect_project_init,
    exit = collect_project_exit,
}

-- vim:sw=4:sts=4:et:
