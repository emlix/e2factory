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

--- check collect_project configuration
-- This function depends on sane result and source configurations.
-- @param info table: the info table
-- @param resultname string: the result to check
local function check_collect_project(info, resultname)
    local res = info.results[resultname]
    local e = err.new("in result %s:", resultname)
    local rc, re
    if not res.collect_project then
        -- insert empty tables, to avoid some conditionals in the code
        res.collect_project_results = {}
        res.collect_project_sources = {}
        res.collect_project_chroot_groups = {}
        res.collect_project_licences = {}
        -- XXX store list of used chroot groups here, too, and use.
        return true, nil
    end
    local d = res.collect_project_default_result
    if not d then
        e:append("collect_project_default_result is not set")
    elseif type(d) ~= "string" then
        e:append(
        "collect_project_default_result is non-string")
    elseif not info.results[d] then
        e:append("collect_project_default_result is set to "..
        "an invalid result: %s", d)
    end
    -- catch errors upon this point before starting additional checks.
    if e:getcount() > 1 then
        return false, e
    end
    res.collect_project_results, re = e2tool.dlist_recursive(info,
        res.collect_project_default_result)
    if not res.collect_project_results then
        return false, e:cat(re)
    end
    -- store a sorted list of required results
    table.insert(res.collect_project_results,
        res.collect_project_default_result)
    table.sort(res.collect_project_results)
    e2lib.warnf("WDEFAULT", "in result %s:", resultname)
    e2lib.warnf("WDEFAULT", " collect_project takes these results: %s",
    table.concat(res.collect_project_results, ","))
    -- store a sorted list of required sources, chroot groups and licences
    local tmp_grp = {}
    local tmp_src = {}
    for _,r in ipairs(res.collect_project_results) do
        local res = info.results[r]
        for _,s in ipairs(res.sources) do
            tmp_src[s] = true
        end
        for _,g in ipairs(res.chroot) do
            -- use the name as key here, to hide duplicates...
            tmp_grp[g] = true
        end
    end
    res.collect_project_sources = {}
    for s,_ in pairs(tmp_src) do
        -- and build the desired array
        table.insert(res.collect_project_sources, s)
    end
    table.sort(res.collect_project_sources)
    res.collect_project_chroot_groups = {}
    for g,_ in pairs(tmp_grp) do
        table.insert(res.collect_project_chroot_groups, g)
    end
    table.sort(res.collect_project_chroot_groups)
    res.collect_project_licences = {}
    for _,l in ipairs(info.licences_sorted) do
        table.insert(res.collect_project_licences, l)
    end
    table.sort(res.collect_project_licences)
    if e:getcount() > 1 then
        return false, e
    end
    return true, nil
end

--- Calculate part of the resultid for collect_project results.
-- @param info Info table.
-- @param resultname Result name.
-- @return ResultID string, false to skip, nil on error.
-- @return Error object on failure.
local function collect_project_resultid(info, resultname)
    local rc, re, res, hc, id

    res = info.results[resultname]

    if not res.collect_project then
        return false
    end

    -- Warning: nil is used to signal error to the caller.

    hc, re = hash.hash_start()
    if not hc then return nil, re end


    for _,c in ipairs(res.collect_project_results) do
        rc, re = hash.hash_line(hc, c)
        if not rc then return nil, re end
    end
    for _,s in ipairs(res.collect_project_sources) do
        rc, re = hash.hash_line(hc, s)
        if not rc then return nil, re end
    end
    for _,g in ipairs(res.collect_project_chroot_groups) do
        rc, re = hash.hash_line(hc, g)
        if not rc then return nil, re end
    end
    for _,l in ipairs(res.collect_project_licences) do
        rc, re = hash.hash_line(hc, l)
        if not rc then return nil, re end

        -- We collect all licences. So we cannot be sure to catch
        -- them via results/sources. Include them explicitly here.
        local lid, re = e2tool.licenceid(info, l)
        if not lid then
            return nil, e:cat(re)
        end

        rc, re = hash.hash_line(hc, lid)
        if not rc then return nil, re end
    end

    id, re = hash.hash_finish(hc)
    if not id then return nil, re end

    return id
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
local function build_collect_project(info, r, return_flags)
    local out
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
        string.format("name='%s'\n", info.project.name),
        string.format("release_id='%s'\n", info.project.release_id),
        string.format("default_results='%s'\n",
            res.collect_project_default_result),
        string.format("chroot_arch='%s'\n", info.project.chroot_arch)
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
    for _,g in pairs(res.collect_project_chroot_groups) do
        e2lib.logf(3, "chroot group: %s", g)
        local grp = info.chroot.groups_byname[g]
        local destdir = e2lib.join( res.build_config.T, "project/chroot", g)
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        out = { "place:\n" }

        for _,file in pairs(grp.files) do
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
            rc, re = cache.fetch_file(info.cache, file.server, file.location,
                destdir, nil, cache_flags)
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
