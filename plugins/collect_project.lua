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
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local hash = require("hash")
local scm = require("scm")
local strict = require("strict")
local licence = require("licence")
local chroot = require("chroot")
local project = require("project")

--- Collect_project result config. This result config table lives in
-- info.results[resultname]. The fields are merged with e2tool.result
-- @table collect_project_result
-- @field collect_project bool: collect the project structure into this result?
-- @field collect_project_default_result string: which result shall be
--                                 collected, including recursive dependencies?
-- @see local.e2tool.result

--- Local dict indexed by result names for which collect_project is enabled.
local cpresults = {}

--- Per collect_project result table containing data local to the plugin.
-- @table cpresults.resultname
-- @field results table: sorted list of results to be collected
-- @field sources table: sorted list of sources to be collected
-- @field chroot_groups table: sorted list of chroot groups to be collected
-- @see cpresults

--- check collect_project configuration
-- This function depends on sane result and source configurations.
-- @param info table: the info table
-- @param resultname string: the result to check
local function check_collect_project(info, resultname)
    local res = info.results[resultname]
    if not res.collect_project then
        return true
    end

    local e = err.new("in result %s:", resultname)
    local rc, re, cpres, default_result

    cpresults[resultname] = {}
    cpres = cpresults[resultname]

    cpres.results = {}
    cpres.sources = {}
    cpres.chroot_groups = {}

    strict.lock(cpres)

    default_result = res.collect_project_default_result
    if not default_result then
        e:append("collect_project_default_result is not set")
    elseif type(default_result) ~= "string" then
        e:append( "collect_project_default_result is not a string")
    elseif not info.results[default_result] then
        e:append("collect_project_default_result is set to "..
            "an invalid result: %s", default_result)
    end
    -- catch errors upon this point before starting additional checks.
    if e:getcount() > 1 then
        return false, e
    end

    cpres.results, re = e2tool.dlist_recursive(info, { default_result })
    if not cpres.results then
        return false, e:cat(re)
    end

    e2lib.warnf("WDEFAULT", "in result %s:", resultname)
    e2lib.warnf("WDEFAULT", " collect_project takes these results: %s",
        table.concat(cpres.results, ","))

    -- store a sorted list of required sources and chroot groups
    local tmp_grp = {}
    local tmp_src = {}
    for _,r in ipairs(cpres.results) do
        local res = info.results[r]
        for _,s in ipairs(res.sources) do
            tmp_src[s] = true
        end
        for _,g in ipairs(res.chroot) do
            -- use the name as key here, to hide duplicates...
            tmp_grp[g] = true
        end
    end
    for s,_ in pairs(tmp_src) do
        -- and build the desired array
        table.insert(cpres.sources, s)
    end
    table.sort(cpres.sources)
    for g,_ in pairs(tmp_grp) do
        table.insert(cpres.chroot_groups, g)
    end
    table.sort(cpres.chroot_groups)

    if e:getcount() > 1 then
        return false, e
    end
    return true, nil
end

--- Calculate part of the resultid for collect_project results.
-- @param info Info table.
-- @param resultname Result name.
-- @return ResultID string, true to skip, false on error.
-- @return Error object on failure.
local function collect_project_resultid(info, resultname)
    local rc, re, res, cpres, hc, id

    res = info.results[resultname]

    if not res.collect_project then
        return true
    end

    cpres = cpresults[resultname]
    hc, re = hash.hash_start()
    if not hc then return false, re end

    for _,c in ipairs(cpres.results) do
        rc, re = hash.hash_line(hc, c)
        if not rc then return false, re end
    end
    for _,s in ipairs(cpres.sources) do
        rc, re = hash.hash_line(hc, s)
        if not rc then return false, re end
    end
    for _,g in ipairs(cpres.chroot_groups) do
        rc, re = hash.hash_line(hc, g)
        if not rc then return false, re end
    end
    for _,l in ipairs(licence.licences_sorted) do
        -- We collect all licences. So we cannot be sure to catch
        -- them via results/sources. Include them explicitly here.
        local lid, re = l:licenceid(info)
        if not lid then
            return false, e:cat(re)
        end

        rc, re = hash.hash_line(hc, lid)
        if not rc then return false, re end
    end

    id, re = hash.hash_finish(hc)
    if not id then return false, re end

    return id
end

--- Calculate part of the (recursive) pbuildid for collect_project results.
-- @param info Info table.
-- @param resultname Result name.
-- @return PbuildID string, true to skip, false on error.
-- @return Error object on failure.
local function collect_project_pbuildid(info, resultname)
    local rc, re, res, cpres, hc, pbid

    res = info.results[resultname]

    if not res.collect_project then
        return true
    end

    cpres = cpresults[resultname]
    hc, re = hash.hash_start()
    if not hc then return false, re end

    for _,rn in ipairs(cpres.results) do
        pbid, re = e2tool.pbuildid(info, rn)
        if not pbid then
            return false, re
        end

        rc, re = hash.hash_line(hc, pbid)
        if not rc then return false, re end
    end

    pbid, re = hash.hash_finish(hc)
    if not pbid then return false, re end

    return pbid
end

--- collect all data required to build the project.
-- skip results that depend on this result
-- example: toolchain, busybox, sources, iso,
-- sources being the result collecting the project:
-- the results sources and iso won't be included, as that would lead to
-- an impossibility to calculate buildids (infinite recursion)
-- @param info info table
-- @param resultname Result name.
-- @param return_flags
-- @return bool
-- @return an error object on failure
local function build_collect_project(info, resultname, return_flags)
    local out
    local res = info.results[resultname]
    if not res.collect_project then
        -- nothing to be done here...
        return true, nil
    end

    local cpres = cpresults[resultname]

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
        local server = info.root_server_name
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
        string.format("default_results='%s'\n",
            res.collect_project_default_result),
        string.format("chroot_arch='%s'\n", project.chroot_arch())
    }

    local file, destdir
    destdir = e2lib.join(res.build_config.T, "project/proj")
    file = e2lib.join(destdir, "config")
    rc, re = eio.file_write(file, table.concat(out))
    if not rc then
        return false, e:cat(re)
    end

    -- files from the project
    destdir = e2lib.join(res.build_config.T, "project/.e2/bin")
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    -- generate build driver file for each result
    -- project/chroot/<group>/<files>
    for _,g in ipairs(cpres.chroot_groups) do
        e2lib.logf(3, "chroot group: %s", g)
        local grp = chroot.groups_byname[g]
        local destdir = e2lib.join( res.build_config.T, "project/chroot", g)
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
                    "%s/%s.sha1", destdir,
                    e2lib.basename(file.location))
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
    for _,l in ipairs(licence.licences_sorted) do
        e2lib.logf(3, "licence: %s", l:get_name())
        local destdir =
            e2lib.join(res.build_config.T, "project/licences", l:get_name())
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        for file in l:file_iter() do
            local cache_flags = {}
            if file.sha1 then
                rc, re = e2tool.verify_hash(info, file.server,
                file.location, file.sha1)
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
    for _,n in ipairs(cpres.results) do
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
            rc, re = cache.fetch_file(info.cache, server, file, destdir,
                nil, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
        local file, line
        -- generate environment script
        file = e2lib.join(destdir, "env")
        rc, re = environment.tofile(e2tool.env_by_result(info, n), file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate builtin environment script
        local file = e2lib.join(destdir, "builtin")
        rc, re = environment.tofile(rn.build_config.builtin_env, file)
        if not rc then
            return false, e:cat(re)
        end
        -- generate build driver
        rc, re = e2build.write_build_driver(info, n, destdir)
        if not rc then
            return false, e:cat(re)
        end
        -- generate config
        out = {
            string.format("### generated by e2factory for result %s ###\n", n),
            string.format("CHROOT='%s'\n", table.concat(rn.chroot, " ")),
            string.format("DEPEND='%s'\n", table.concat(rn.depends, " ")),
            string.format("SOURCE='%s'\n", table.concat(rn.sources, " ")),
        }

        local config = e2lib.join(destdir, "config")
        rc, re = eio.file_write(config, table.concat(out))
        if not rc then
            return false, e:cat(re)
        end
    end
    for _,s in ipairs(cpres.sources) do
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
        cpres.results)
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
    local server = info.root_server_name
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
    return true, nil
end

local function collect_project_init(ctx)
    local rc, re

    rc, re = e2tool.register_check_result(ctx.info, check_collect_project)
    if not rc then
        return false, re
    end

    rc, re = e2tool.register_resultid(ctx.info, collect_project_resultid)
    if not rc then
        return false, re
    end

    rc, re = e2tool.register_pbuildid(ctx.info, collect_project_pbuildid)
    if not rc then
        return false, re
    end

    rc, re = e2build.register_build_function(ctx.info, "collect_project",
        build_collect_project, "fix_permissions")
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
