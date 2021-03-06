--- e2-build command
-- @module local.e2-build

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
local console = require("console")
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local err = require("err")
local policy = require("policy")
local project = require("project")
local result = require("result")

local function e2_build(arg)
    local e2project
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    e2project = e2tool.e2project()
    e2project:init_project("build")

    -- list of results with a specific build mode
    local wc_mode_results = {}
    local branch_mode_results =  {}
    local tag_mode_results = {}
    local specific_result_count = 0

    -- insert results into their respective tables above.
    local function option_insert_results(the_result_table, table_name)

        return function(resultnames)
            -- closure: the_result_table table_name
            e2lib.logf(4, "option_insert_results func(%s) on %s",
                tostring(resultnames), table_name)
            if type(resultnames) == "string" then
                for resultname in string.gmatch(resultnames, "[^,%s]+") do
                    table.insert(the_result_table, resultname)
                    specific_result_count = specific_result_count + 1
                end
            end
            return true
        end
    end

    -- list of results specified on the command line or with --all
    local selected_results = {}

    -- list of unsorted results we want to build, no matter the build mode.
    local build_results = {}

    -- list of results and their depends in build order
    local ordered_results


    e2option.flag("all", "build all results (default unless for working copy)")
    policy.register_commandline_options()
    e2option.option("tag-mode", "build selected results in tag mode",
        true, option_insert_results(tag_mode_results, "tag_mode_results"))
    e2option.option("branch-mode", "build selected results in branch mode",
        true, option_insert_results(branch_mode_results, "branch_mode_results"))
    e2option.option("wc-mode", "build selected results in working-copy mode",
        true, option_insert_results(wc_mode_results, "wc_mode_results"))
    e2option.flag("force-rebuild", "force rebuilding even if a result exists")
    e2option.flag("playground", "prepare environment but do not build")
    e2option.flag("keep", "do not remove chroot environment after build")
    e2option.flag("buildid", "display buildids and exit")

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    for _,resultname in ipairs(arguments) do
        table.insert(selected_results, resultname)
    end

    -- get build mode from the command line
    local build_mode, re = policy.handle_commandline_options(opts, true)
    if not build_mode then
        error(re)
    end

    rc, re = e2project:load_project()
    if not rc then
        error(re)
    end

    if opts["all"] and (#selected_results > 0 or specific_result_count > 0) then
        error(err.new("--all with additional results does not make sense"))
    elseif opts["all"] then
        for resultname,_ in pairs(result.results) do
            table.insert(selected_results, resultname)
        end
    end

    --
    local build_mode_count = 0
    for _,option_name in ipairs({"tag-mode", "branch-mode", "wc-mode"}) do
        if opts[option_name] then
            build_mode_count = build_mode_count + 1
        end
    end

    if build_mode_count > 1 and #selected_results > 0 then
        e2lib.warnf("WOTHER", "building package %s in default mode",
            table.concat(selected_results, ", "))
    end

    local function check_mode(option_name, cnt, opts, results, selected_results)
        if opts[option_name] then

            -- consume all selected results if only one build mode
            if cnt == 1 then
                for k,resultname in ipairs(selected_results) do
                    table.insert(results, resultname)
                    selected_results[k] = nil
                end
            end

            if #results == 0 then
                local e
                e = err.new("--%s requires one or more results", option_name)
                error(e)
            end
        end
    end

    check_mode("tag-mode", build_mode_count, opts, tag_mode_results, selected_results)
    check_mode("branch-mode", build_mode_count, opts, branch_mode_results, selected_results)
    check_mode("wc-mode", build_mode_count, opts, wc_mode_results, selected_results)

    -- check for duplicate results
    local duplicates = {}
    for _,t in ipairs({selected_results, tag_mode_results, branch_mode_results, wc_mode_results}) do
        for _,resultname in ipairs(t) do
            if not duplicates[resultname] then
                duplicates[resultname] = true
            else
                error(err.new("result specified more than once: %s", resultname))
            end
        end
    end
    duplicates = nil

    if opts["release"] and build_mode_count > 0 then
        error(err.new("--release mode and other build modes can't be mixed"))
    end

    local playground = opts["playground"]
    if playground then
        if opts["release"] then
            error(err.new("--release and --playground are mutually exclusive"))
        end
        if opts["all"] then
            error(err.new("--all and --playground are mutually exclusive"))
        end
        if #selected_results ~= 1 then
            error(err.new("please specify a single result for the playground"))
        end
    end
    local force_rebuild = opts["force-rebuild"]
    local keep_chroot = opts["keep"]

    -- processing options is over, lets sort this out

    for _,t in ipairs({selected_results, tag_mode_results, branch_mode_results, wc_mode_results}) do
        for _,resultname in ipairs(t) do
            table.insert(build_results, resultname)
        end
    end

    if #build_results == 0 then
        for resultname in project.default_results_iter() do
            table.insert(build_results, resultname)
        end
    end

    local set = e2build.build_set:new()

    -- a list of results to build, topologically sorted
    ordered_results, re = e2tool.dlist_recursive(build_results)
    if not ordered_results then
        error(re)
    end

    -- in --release mode, warn about builds not including the
    -- configured deploy results
    if opts["release"] then
        for deployresname in project.deploy_results_iter() do
            local included = false

            for _, resultname in ipairs(ordered_results) do
                if deployresname == resultname then
                    included = true
                    break
                end
            end

            if not included then
                e2lib.warnf("WOTHER",
                    "release build does not include deploy result: %s",
                    deployresname)
            end
        end
    end

    -- apply build modes and settings
    -- first, standard build mode and settings for all
    for _,resultname in ipairs(ordered_results) do
        set:add(resultname, "build", build_mode)
   end

    -- selected results
    e2lib.logf(4, "selected_results=%s", table.concat(selected_results, " "))
    for _,resultname in ipairs(selected_results) do
        local rbs = set:result_build_set(resultname)
        rbs:build_settings():force_rebuild(force_rebuild)
        rbs:build_settings():keep_chroot(keep_chroot)
        rbs:build_settings():prep_playground(playground)
    end

    -- specific build modi
    e2lib.logf(4, "tag_mode_results=%s", table.concat(tag_mode_results, " "))
    for _,resultname in ipairs(tag_mode_results) do
        local rbs = set:result_build_set(resultname)
        rbs:build_settings():force_rebuild(force_rebuild)
        rbs:build_settings():keep_chroot(keep_chroot)
        rbs:build_settings():prep_playground(playground)
        rbs:build_mode(policy.default_build_mode("tag"))
    end

    e2lib.logf(4, "branch_mode_results=%s", table.concat(branch_mode_results, " "))
    for _,resultname in ipairs(branch_mode_results) do
        local rbs = set:result_build_set(resultname)
        rbs:build_settings():force_rebuild(force_rebuild)
        rbs:build_settings():keep_chroot(keep_chroot)
        rbs:build_settings():prep_playground(playground)
        rbs:build_mode(policy.default_build_mode("branch"))
    end

    e2lib.logf(4, "wc_mode_results=%s", table.concat(wc_mode_results, " "))
    for _,resultname in ipairs(wc_mode_results) do
        local rbs = set:result_build_set(resultname)
        rbs:build_settings():force_rebuild(force_rebuild)
        rbs:build_settings():keep_chroot(keep_chroot)
        rbs:build_settings():prep_playground(playground)
        rbs:build_mode(policy.default_build_mode("working-copy"))
    end

    -- calculate buildids for selected results
    for _,resultname in ipairs(ordered_results) do
        local rbs = set:result_build_set(resultname)
        local bid, re = result.results[resultname]:buildid(rbs)
        if not bid then
            error(re)
        end

        if opts.buildid then
            console.infof("%-20s [%s]\n", resultname, bid)
        end
    end

    if not opts.buildid then
        local rc, re = set:build()
        if not rc then
            error(re)
        end
    end
end

local pc, re = e2lib.trycall(e2_build, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
