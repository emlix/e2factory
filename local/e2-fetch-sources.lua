--- e2-fetch-source command
-- @module local.e2-fetch-source

-- Copyright (C) 2007-2017 emlix GmbH, see file AUTHORS
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
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local err = require("err")
local result = require("result")
local source = require("source")

local function e2_fetch_source(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local info, re = e2tool.local_init(nil, "fetch-sources")
    if not info then
        error(re)
    end

    local e = err.new()

    e2option.flag("all", "select all sources, even files sources")
    e2option.flag("chroot", "select chroot files")
    e2option.flag("scm", "select all scm sources")
    e2option.flag("fetch", "fetch selected sources (default)")
    e2option.flag("update", "update selected source")
    e2option.flag("source", "select sources by source names (default)")
    e2option.flag("result", "select sources by result names")

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    info, re = e2tool.collect_project_info(info)
    if not info then
        error(re)
    end

    if not (opts.fetch or opts.update) then
        opts.fetch = true
    end

    local select_type = {}

    for typ, theclass in source.iterate_source_classes() do
        if theclass:is_selected_source_class(opts) then
            select_type[typ] = true
        end
    end

    if not (opts.all or opts.scm or opts.files or opts.chroot or #arguments > 0
        or next(select_type) ~= nil) then
        e2lib.warn("WDEFAULT", "Selecting scm sources by default")
        opts.scm = true
    end

    if opts.scm then
        for typ, theclass in source.iterate_source_classes() do
            if theclass:is_scm_source_class() then
                select_type[typ] = true
            end
        end
    end

    --- cache chroot files
    -- @return bool
    -- @return nil, an error string on error
    local function cache_chroot()
        local grp, rc, re
        for _,g in ipairs(chroot.groups_sorted) do
            grp = chroot.groups_byname[g]
            for file in grp:file_iter() do
                if cache.cache_enabled(cache.cache(), file:server()) then
                    rc, re = cache.fetch_file_path(cache.cache(), file:server(),
                        file:location())
                    if not rc then
                        return false, re
                    end
                end
            end
        end
        return true
    end

    --- fetch and upgrade sources
    -- @param info the info table
    -- @param opts the option table
    -- @param sel table of selected results
    -- @return bool
    -- @return nil, an error string on error
    local function fetch_sources(info, opts, sel)
        local rc, re
        local nfail
        local e = err.new()  -- no message yet, append the summary later on

        -- fetch
        for sourcename, src in pairs(source.sources) do
            if opts.fetch and sel[sourcename] then
                e2lib.logf(1, "fetching working copy for source %s", sourcename)
                rc, re = src:fetch_source()
                if not rc then
                    e:cat(re)
                end
            end
        end

        -- update
        for sourcename, src in pairs(source.sources) do
            if opts.update and sel[sourcename] then
                e2lib.logf(1, "updating working copy for %s", sourcename)
                rc, re = src:update_source()
                if not rc then
                    e:cat(re)
                end
            end
        end

        nfail = e:getcount()
        if nfail > 0 then
            e:append("There were errors fetching %d sources", nfail)
            return false, e
        end
        return true
    end

    local sel = {} -- selected sources

    if #arguments > 0 then
        for _, srcresname in pairs(arguments) do
            if source.sources[srcresname] and not opts.result then
                e2lib.logf(3, "is regarded as source: %s", srcresname)
                sel[srcresname] = true
            elseif result.results[srcresname] and opts.result then
                e2lib.logf(3, "is regarded as result: %s", srcresname)
                local res = result.results[srcresname]

                for sourcename in res:sources_list():iter() do
                    sel[sourcename] = true
                end
            elseif opts.result then
                error(err.new("is not a result: %s", srcresname))
            else
                error(err.new("is not a source: %s", srcresname))
            end
        end
    elseif opts["all"] then
        -- select all sources
        for sourcename, _ in pairs(source.sources) do
            sel[sourcename] = true
        end
    end

    -- select all sources by scm type
    for sourcename, src in pairs(source.sources) do
        if select_type[src:get_type()] then
            sel[sourcename] = true
        end
    end


    for sourcename, _ in pairs(sel) do
        e2lib.logf(2, "selecting source: %s" , sourcename)
        local src = source.sources[sourcename]
        if not src then
            e:append("selecting invalid source: %s", sourcename)
        end
    end
    if e:getcount() > 0 then
        error(e)
    end

    if opts.chroot then
        e2lib.log(2, "caching chroot files")
        local rc, re = cache_chroot()
        if not rc then
            e:append("Error: Caching chroot files failed")
            e:cat(re)
        end
    end

    if next(sel) ~= nil then
        e2lib.log(2, "fetching sources...")
        local rc, re = fetch_sources(info, opts, sel)
        if not rc then
            e:cat(re)
        end
    end

    if e:getcount() > 0 then
        error(e)
    end
end

local pc, re = e2lib.trycall(e2_fetch_source, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
