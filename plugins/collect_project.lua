--- Collect_project Plugin. Turns a e2factory project into a make
-- based project tar archive.
-- @module plugins.collect_project

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

--------------------------------------------------------------------------------
-- collect project build process step first because real forward declarations
-- aren't a thing in Lua.

--- Create Makefile based structure required to build the project
-- without e2factory
-- @param self A build_process_class instance
-- @param res Result object to build
-- @param return_flags
-- @return bool
-- @return an error object on failure
local function _build_collect_project(self, res, return_flags)

    local function write_build_driver(info, resultname, destdir)
        local rc, re, e, res, bd, buildrc_noinit_file, buildrc_file, bc
        local build_driver_file

        e = err.new("generating build driver script failed")

        res = result.results[resultname]
        bc = res:build_config()

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
    local bc = res:build_config()
    local e = err.new("providing project data to this build failed")
    local cp_sources = sl.sl:new(true, false)
    local cp_depends = sl.sl:new(true, false)
    local cp_chroot = sl.sl:new(true, false)
    local cp_licences = sl.sl:new(true, false)

    info = e2tool.info()

    -- calculate depends, sources, licences and chroot
    rc, re = e2tool.dlist_recursive({res:cp_default_result()})
    if not rc then
        return false, e:cat(re)
    end
    cp_depends:insert_table(rc)

    for depname in cp_depends:iter_sorted() do
        local dep = result.results[depname]

        if dep:get_type() ~= "result" then
            return false,
                err.new("can not convert result %q, type %q is unsupported",
                    dep:get_name(), dep:get_type())
        end
        cp_chroot:insert_sl(dep:chroot_list())
        cp_sources:insert_sl(dep:sources_list())
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
        string.format("default_results='%s'\n", res:cp_default_result()),
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
        local depbc = dep:build_config()

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
            string.format("CHROOT='%s'\n", dep:chroot_list():concat_sorted(" ")),
            string.format("DEPEND='%s'\n", dep:depends_list():concat_sorted(" ")),
            string.format("SOURCE='%s'\n", dep:sources_list():concat_sorted(" ")),
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

--------------------------------------------------------------------------------

local collect_project_class = class("collect_project_class",
    result.basic_result)

function collect_project_class:initialize(rawres)
    assertIsTable(rawres)
    assertNotNil(rawres.collect_project)
    assertStrMatches(rawres.type, "collect_project")

    result.basic_result.initialize(self, rawres)

    self._default_result = false
    self._stdresult = false

    local rc, re, e

    e = err.new("in result %s:", self:get_name())
    if type(rawres.collect_project) ~= "boolean"
        or rawres.collect_project ~= true then
        error(e:append("collect_project must be true"))
    end

    if rawres.collect_project_default_result == nil then
        e:append("collect_project_default_result is not set")
    elseif type(rawres.collect_project_default_result) ~= "string" then
        e:append("collect_project_default_result is not a string")
    else
        self._default_result = rawres.collect_project_default_result
    end

    -- we're done, remove everything collect project from the result
    rawres.type = nil
    rawres.collect_project = nil
    rawres.collect_project_default_result = nil

    rc, re = result.instantiate_object(rawres)
    if not rc then
        e:cat(re)
    end

    if e:getcount() > 1 then
        error(e)
    end

    self._stdresult = rc
    assertIsTable(self._stdresult)
end

function collect_project_class:post_initialize()
    assertIsString(self:cp_default_result())
    local e, re, rc, dependsvec

    e = err.new("in result %s:", self:get_name())

    if not result.results[self:cp_default_result()] then
        e:append("collect_project_default_result is set to "..
            "an invalid result: %s", self:cp_default_result())
        return false, e
    end

    return true
end

function collect_project_class:cp_default_result()
    assertIsStringN(self._default_result)
    return self._default_result
end

function collect_project_class:depends_list()
    local deps = self._stdresult:depends_list()
    deps:insert(self:cp_default_result())

    return deps
end

function collect_project_class:buildid()
    local rc, re, bid, hc

    bid, re = self._stdresult:buildid()
    if not bid then
        return false, re
    end

    hc = hash.hash_start()
    hash.hash_append(hc, bid)
    hash.hash_append(hc, self:cp_default_result())
    bid = hash.hash_finish(hc)

    assertIsStringN(bid)

    return bid
end

function collect_project_class:build_config()
    return self._stdresult:build_config()
end

function collect_project_class:build_mode(bm)
    return self._stdresult:build_mode(bm)
end

function collect_project_class:build_settings(bs)
    return self._stdresult:build_settings(bs)
end

function collect_project_class:build_process()
    local bp = self._stdresult:build_process()

    bp:add_step_before("build", "fix_permissions", "build_collect_project",
        _build_collect_project)

    return bp
end

function collect_project_class:chroot_list()
    return self._stdresult:chroot_list()
end

function collect_project_class:merged_env()
    return self._stdresult:merged_env()
end

function collect_project_class:sources_list()
    return self._stdresult:sources_list()
end

function collect_project_class:attribute_table(flagt)
    local t

    t = self._stdresult:attribute_table(flagt)
    assertIsTable(t)
    table.insert(t, { "collect_project_default_result", self:cp_default_result()})

    return t
end

--------------------------------------------------------------------------------


local function detect_cp_result(rawres)
    assertIsTable(rawres)

    if not rawres.type and rawres.collect_project ~= nil then
        rawres.type = "collect_project"
    end
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
    description = "collect_project plugin",
    init = collect_project_init,
    exit = collect_project_exit,
}

-- vim:sw=4:sts=4:et:
