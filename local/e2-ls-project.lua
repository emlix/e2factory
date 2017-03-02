--- e2-ls-project command
-- @module local.e2-ls-project

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
local console = require("console")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local err = require("err")
local licence = require("licence")
local policy = require("policy")
local project = require("project")
local result = require("result")
local source = require("source")

--- e2 ls-project entry point.
-- @param arg Arguments.
-- @return Always true.
-- @raise error, assert
local function e2_ls_project(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local info, re = e2tool.local_init(nil, "ls-project")
    if not info then
        error(re)
    end

    policy.register_commandline_options()
    e2option.flag("dot", "generate dot(1) graph")
    e2option.flag("dot-sources", "generate dot(1) graph with sources included")
    e2option.flag("swap", "swap arrow directions in dot graph")
    e2option.flag("all", "show unused results and sources, too")
    e2option.flag("chroot", "show chroot groups as well")
    e2option.flag("env", "show environment vars as well")

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    -- get build mode from the command line
    local build_mode, re = policy.handle_commandline_options(opts, true)
    if not build_mode then
        error(re)
    end

    info, re = e2tool.collect_project_info(info)
    if not info then
        error(re)
    end

    local results = {}
    if opts.all then
        for resultname, _ in pairs(result.results) do
            table.insert(results, resultname)
        end
    elseif #arguments > 0 then
        for _, resultname in ipairs(arguments) do
            if result.results[resultname] then
                table.insert(results, resultname)
            else
                error(err.new("not a result: %s", resultname))
            end
        end
    end
    if #results > 0 then
        results, re = e2tool.dlist_recursive(results)
        if not results then
            error(re)
        end
    else
        results, re = e2tool.dsort()
        if not results then
            error(re)
        end
    end
    table.sort(results)

    local chrootgroups = {}
    if opts.all then
        for chrootgroup,_ in pairs(chroot.groups_byname) do
            table.insert(chrootgroups, chrootgroup)
        end
    else
        local seen = {}
        for _,resultname in ipairs(results) do
            local res = result.results[resultname]

            for chrootgroup in res:chroot_list():iter() do
                if not seen[chrootgroup] then
                    table.insert(chrootgroups, chrootgroup)
                    seen[chrootgroup] = true
                end
            end
        end
    end
    table.sort(chrootgroups)

    local sources = {}
    if opts.all then
        for sourcename, _ in pairs(source.sources) do
            table.insert(sources, sourcename)
        end
    else
        local yet = {}
        for _, resultname in pairs(results) do
            local res = result.results[resultname]

            for sourcename in res:sources_list():iter() do
                if not yet[sourcename] then
                    table.insert(sources, sourcename)
                    yet[sourcename] = true
                end
            end
        end
    end
    table.sort(sources)

    local licences = {}
    if opts.all then
        for licencename,_ in pairs(licence.licences) do
            table.insert(licences, licencename)
        end
    else
        local seen = {}
        for _,sourcename in ipairs(sources) do
            local src = source.sources[sourcename]

            for licencename in src:get_licences():iter() do
                if not seen[licencename] then
                    table.insert(licences, licencename)
                    seen[licencename] = true
                end
            end
        end
    end
    table.sort(licences)

    local function pempty(s1, s2, s3)
        console.infof("   %s  %s  %s\n", s1, s2, s3)
    end
    local function p0(s1, s2, v)
        console.infonl(v)
    end
    local function p1(s1, s2, v)
        console.infof("   o--%s\n", v)
    end
    local function p2(s1, s2, v)
        console.infof("   %s  o--%s\n", s1, v)
    end
    local function p3(s1, s2, k, ...)
        local t = {...}

        if #t == 0 then
            console.infof("   %s  %s  o--%s\n", s1, s2, k)
        elseif #t == 1 then
            local v = t[1]
            -- remove leading spaces, that allows easier string
            -- append code below, where collecting multiple items
            while v:sub(1,1) == " " do

                v = v:sub(2)
            end
            console.infof("   %s  %s  o--%-10s = %s\n", s1, s2, k, v)
        else
            local col = tonumber(e2lib.globals.osenv["COLUMNS"])
            local header1 = string.format("   %s  %s  o--%-10s =", s1, s2, k)
            local header2 = string.format("   %s  %s     %-10s  ", s1, s2, "")
            local header = header1
            local l = nil
            local i = 0
            for _,v in ipairs(t) do
                i = i + 1
                if l then
                    if (l:len() + v:len() + 1) > col then
                        console.infonl(l)
                        l = nil
                    end
                end
                if not l then
                    l = string.format("%s %s", header, v)
                else
                    l = string.format("%s %s", l, v)
                end
                header = header2
            end
            if l then
                console.infonl(l)
            end
        end
    end

    if opts.dot or opts["dot-sources"] then
        local arrow = "->"
        console.infof("digraph \"%s\" {\n", project.name())
        for _, r in pairs(results) do
            local res = result.results[r]
            local deps, re = res:depends_list():totable()
            if not deps then
                error(re)
            end
            if #deps > 0 then
                for _, dep in pairs(deps) do
                    if opts.swap then
                        console.infof("  \"%s\" %s \"%s\"\n", dep, arrow, r)
                    else
                        console.infof("  \"%s\" %s \"%s\"\n", r, arrow, dep)
                    end
                end
            else
                console.infof("  \"%s\"\n", r)
            end
            if opts["dot-sources"] then
                for src in res:sources_list():iter() do
                    if opts.swap then
                        console.infof("  \"%s-src\" %s \"%s\"\n", src, arrow, r)
                    else
                        console.infof("  \"%s\" %s \"%s-src\"\n", r, arrow, src)
                    end
                end
            end
        end
        if opts["dot-sources"] then
            for _, s in pairs(sources) do
                console.infof("  \"%s-src\" [label=\"%s\", shape=box]\n", s, s)
            end
        end
        console.infonl("}")
        e2lib.finish(0)
    end

    -- project name
    local s1 = "|"
    local s2 = "|"
    p0(s1, s2, project.name())

    -- servers
    local s1 = "|"
    local s2 = "|"
    p1(s1, s2, "servers")
    local servers_sorted = cache.servers(cache.cache())
    for i = 1, #servers_sorted, 1 do
        local ce = cache.ce_by_server(cache.cache(), servers_sorted[i])
        if i < #servers_sorted then
            s2 = "|"
        else
            s2 = " "
        end
        p2(s1, s2, ce.server)
        p3(s1, s2, "url", ce.remote_url)
        local flags = {}
        for k,v in pairs(ce.flags) do
            table.insert(flags, k)
        end
        table.sort(flags)
        for _,k in ipairs(flags) do
            p3(s1, s2, k, tostring(ce.flags[k]))
        end
    end
    console.infonl("   |")

    -- sources
    local s1 = "|"
    local s2 = " "
    p1(s1, s2, "src")
    local len = #sources
    for _, sourcename in pairs(sources) do
        len = len - 1
        if len == 0 then
            s2 = " "
        else
            s2 = "|"
        end
        p2(s1, s2, sourcename)
        local t, re = source.sources[sourcename]:display(build_mode.source_set())
        if not t then
            error(re)
        end
        for _,line in pairs(t) do
            p3(s1, s2, line)
        end
    end

    -- results
    local s1 = "|"
    local s2 = " "
    local s3 = " "
    pempty(s1, s2, s3)
    s2 = " "
    p1(s1, s2, "res")

    local len = #results
    for _, resultname in pairs(results) do
        local res = result.results[resultname]
        p2(s1, s2, res:get_name())

        len = len - 1
        if len == 0 then
            s2 = " "
        else
            s2 = "|"
        end

        local flagt = { env = opts.env, chroot = opts.chroot }
        for _,at in ipairs(res:attribute_table(flagt)) do
            p3(s1, s2, unpack(at))
        end
    end

    -- licences
    local s1 = "|"
    local s2 = " "
    local s3 = " "
    pempty(s1, s2, s3)
    s2 = "|"
    p1(s1, s2, "licences")

    local len = #licences
    for _,licencename in ipairs(licences) do
        local lic = licence.licences[licencename]
        len = len - 1
        if len == 0 then
            s2 = " "
        end
        p2(s1, s2, lic:get_name())
        for file in lic:file_iter() do
            p3(s1, s2, "file", file:servloc())
        end
    end

    -- chroot
    local s1 = "|"
    local s2 = " "
    local s3 = " "
    pempty(s1, s2, s3)
    p1(s1, s2, "chroot groups")
    local s1 = " "
    local s2 = "|"
    local len = #chrootgroups
    for _,chrootgroup in ipairs(chrootgroups) do
        local grp = chroot.groups_byname[chrootgroup]
        len = len - 1
        if len == 0 then
            s2 = " "
        end
        p2(s1, s2, grp:get_name(), grp:get_name())
        for file in grp:file_iter() do
            p3(s1, s2, "file", file:servloc())
        end
    end

    return true
end

local pc, re = e2lib.trycall(e2_ls_project, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
