--- Licence provider plugin
-- @module plugins.licencesrc

-- Copyright (C) 2017 emlix GmbH, see file AUTHORS
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

local licencesrc = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local environment = require("environment")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local result = require("result")
local sl = require("sl")
local source = require("source")
local strict = require("strict")

--------------------------------------------------------------------------------

local licence_source = class("licence_source", source.basic_source)

function licence_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and #rawsrc.name > 0)
    assert(type(rawsrc.type) == "string" and rawsrc.type == "licence")

    local rc, re, e

    source.basic_source.initialize(self, rawsrc)

    self._results = {}
    self._sources = {}
    self._results_list = false
    self._initialized = false
    self._sourceid = false

    -- required but unused.
    self:set_env(environment.new())
    self:licences(sl.sl:new())

    rc, re = e2lib.vrfy_dict_exp_keys(rawsrc, "e2source config", {
        "name",
        "results",
        "sources",
        "type",
    })
    if not rc then
        error(re)
    end

    if rawsrc.results == nil then
        rawsrc.results = {}
    end

    rc, re = e2lib.vrfy_listofstrings(rawsrc.results, "results", false, true)
    if not rc then
        error(re)
    end

    for _,resultname in ipairs(rawsrc.results) do
        table.insert(self._results, resultname)
    end

    ---

    if rawsrc.sources == nil then
        rawsrc.sources = {}
    end

    rc, re = e2lib.vrfy_listofstrings(rawsrc.sources, "sources", false, true)
    if not rc then
        error(re)
    end

    for _,sourcename in ipairs(rawsrc.sources) do
        table.insert(self._sources, sourcename)
    end
end

function licence_source:_post_initialize()
    if self._initialized then
        return true
    end

    local rc, re

    for _,resultname in ipairs(self._results) do
        if not result.results[resultname] then
            return false, err.new("result does not exist: %s", resultname)
        end
    end

    for _,sourcename in ipairs(self._sources) do
        if not source.sources[sourcename] then
            return false, err.new("source does not exist: %s", sourcename)
        end
    end

    self._results_list, re = e2tool.dlist_recursive(self._results)
    if not self._results_list then
        return false, re
    end

    self._initialized = true
    return true
end

function licence_source:sourceid(sourceset)
    assertIsStringN(sourceset)

    local rc, re, e
    local hc, id

    e = err.new("calculating SourceID for %q failed", self._name)

    rc, re = self:_post_initialize()
    if not rc then
        return false, e:cat(re)
    end

    if self._sourceid then
        return self._sourceid
    end

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)

    for _,resultname in ipairs(self._results_list) do
        local res = result.results[resultname]

        hash.hash_append(hc, resultname)

        for sourcename in res:sources_list():iter() do
            if sourcename ~= self._name then
                local src = source.sources[sourcename]

                id, re = src:sourceid(sourceset)
                if not id then
                    return false, e:cat(re)
                end

                hash.hash_append(hc, id)
            end
        end
    end

    for _,sourcename in ipairs(self._sources) do
        if sourcename ~= self._name then
            id, re = source.sources[sourcename]:sourceid(sourceset)
            if not id then
                return false, e:cat(re)
            end
            hash.hash_append(hc, id)
        end
    end

    self._sourceid = hash.hash_finish(hc)

    e2lib.logf(4, "BUILDID: source=%s sourceid=%s", self._name, self._sourceid)

    return self._sourceid
end

function licence_source:prepare_source(sourceset, buildpath)
    assertIsStringN(sourceset)
    assertIsStringN(buildpath)

    local rc, re, e
    local destdir, sdir, rdir, ldir, source_list, licence_list

    e = err.new("preparing source %q failed", self._name)

    rc, re = self:_post_initialize()
    if not rc then
        return false, e:cat(re)
    end

    destdir = e2lib.join(buildpath, self._name)

    sdir = e2lib.join(destdir, "src")
    rdir = e2lib.join(destdir, "res")
    ldir = e2lib.join(destdir, "licences")

    rc, re = e2lib.mkdir_recursive(sdir)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2lib.mkdir_recursive(rdir)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2lib.mkdir_recursive(ldir)
    if not rc then
        return false, e:cat(re)
    end

    source_list = sl.sl:new()
    licence_list = sl.sl:new()

    for _,resultname in ipairs(self._results_list) do
        local res = result.results[resultname]
        local resdir = e2lib.join(rdir, res:get_name())
        local t = {}

        rc, re = e2lib.mkdir(resdir)
        if not rc then
            return false, e:cat(re)
        end

        for sourcename in res:sources_list():iter() do
            if sourcename ~= self._name then
                table.insert(t, sourcename)
                source_list:insert(sourcename) -- collect to process later
            end
        end

        t = table.concat(t, "\n").."\n"

        rc, re = eio.file_write(e2lib.join(resdir, "sources"), t)
        if not rc then
            return false, e:cat(re)
        end
    end

    for _,sourcename in ipairs(self._sources) do
        if sourcename ~= self.name then
            source_list:insert(sourcename)
        end
    end

    for sourcename in source_list:iter() do
        local src = source.sources[sourcename]
        local srcdir = e2lib.join(sdir, src:get_name())

        rc, re = e2lib.mkdir(srcdir)
        if not rc then
            return false, e:cat(re)
        end

        -- collect all licences for later processing
        licence_list:insert_sl(src:licences())

        -- write licences
        local l = src:licences():concat("\n").."\n"

        rc, re = eio.file_write(e2lib.join(srcdir, "licences"), l)
        if not rc then
            return false, e:cat(re)
        end
    end

    for licencename in licence_list:iter() do
        local lic = licence.licences[licencename]

        rc, re = e2lib.mkdir(e2lib.join(ldir, lic:get_name()))
        if not rc then
            return false, e:cat(re)
        end

        for file in lic:file_iter() do
            rc, re = file:checksum_verify()
            if not rc then
                return false, e:cat(re)
            end
            rc, re = cache.fetch_file(cache.cache(), file:server(),
                file:location(), e2lib.join(ldir, lic:get_name()))
            if not rc then
                return false, e:cat(re)
            end
        end
    end

    return true
end

function licence_source:display(sourceset)
    assertIsStringN(sourceset)

    local rc, re, e
    local t = {}

    e = err.new("showing attributes of source %q failed", self._name)

    rc, re = self:_post_initialize()
    if not rc then
        return false, e:cat(re)
    end


    table.insert(t, string.format("%-10s = %s", "type", self:get_type()))
    if #self._results > 0 then
        table.insert(t, string.format("%-10s = %s", "results",
            table.concat(self._results, " ")))
    end
    if #self._sources > 0 then
        table.insert(t, string.format("%-10s = %s", "sources",
            table.concat(self._sources, " ")))
    end

    if self._sourceid then
        table.insert(d, string.format("%-10s = %s", "sourceid", self._sourceid))
    end

    return t
end

function licence_source:fetch_source()
    local rc, re = self:_post_initialize()
    if not rc then
        return false, re
    end
    return true
end

function licence_source:update_source()
    local rc, re = self:_post_initialize()
    if not rc then
        return false, re
    end
    return true
end

function licence_source:working_copy_available()
    return false, err.new("source %q doesn't require a working copy", self._name)
end

function licence_source:check_workingcopy()
    local rc, re = self:_post_initialize()
    if not rc then
        return false, re
    end
    return true
end

--------------------------------------------------------------------------------

local function licences_to_result(src, sourceset, directory)
    assertIsTable(src)
    assertIsStringN(sourceset)
    assertIsStringN(directory)

    local rc, re, e
    local out, tmpdir, adir, archive

    e = err.new("converting %q to result failed", src:get_name())

    tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, e:cat(re)
    end

    rc, re = src:prepare_source(sourceset, tmpdir)
    if not rc then
        return false, e:cat(re)
    end

    adir = e2lib.join(directory, "source")
    rc, re = e2lib.mkdir_recursive(adir)
    if not rc then
        return false, e:cat(re)
    end

    archive = string.format("%s.tar.gz", src:get_name())

    rc, re = e2lib.tar({ "-C", tmpdir ,"-czf",
        e2lib.join(adir, archive), src:get_name()})
    if not rc then
        return false, e:cat(re)
    end

    out = {
        ".PHONY: place",
        "",
        "place:",
        string.format("\ttar xzf \"source/%s\" -C \"$(BUILD)\"", archive),
    }

    out = table.concat(out, "\n").."\n"

    rc, re = eio.file_write(e2lib.join(directory, "Makefile"), out)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.rmtempdir(tmpdir)

    return true
end

--------------------------------------------------------------------------------

plugin_descriptor = {
    description = "Licence Provider Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("licence", licence_source)
        if not rc then
            return false, re
        end

        for typ, theclass in result.iterate_result_classes() do
            if typ == "collect_project" then
                theclass:add_source_to_result_fn("licence", licences_to_result)
                break
            end
        end

        return true
    end,
    exit = function (ctx)
        local rc, re

        for typ, theclass in result.iterate_result_classes() do
            if typ == "collect_project" then
                theclass:remove_source_to_result_fn("licence",
                    licences_to_result)
                break
            end
        end

        rc, re = source.deregister_source_class("licence", licence_source)
        if not rc then
            return false, re
        end

        return true
    end,
    depends = {
        "collect_project.lua"
    }
}

strict.lock(licencesrc)

-- vim:sw=4:sts=4:et:
