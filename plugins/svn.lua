--- Subversion Plugin
-- @module plugins.svn

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

local svn = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local result = require("result")
local source = require("source")
local strict = require("strict")
local tools = require("tools")
local url = require("url")

svn.svn_source = class("svn_source", source.basic_source)

function svn.svn_source.static:is_scm_source_class()
    return true
end

function svn.svn_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)

    if e2tool.current_tool() == "fetch-sources" and opts["svn"] then
        return true
    end
    return false
end

--- translate url into subversion url
-- @param u table: url table
-- @return string: subversion style url
-- @return an error object on failure
local function mksvnurl(surl)
    local rc, re
    local e = err.new("cannot translate url into subversion url:")
    e:append("%s", surl)

    local u, re = url.parse(surl)
    if not u then
        return nil, e:cat(re)
    end

    local transport
    if u.transport == "ssh" or u.transport == "scp" or
        u.transport == "rsync+ssh" then
        transport = "svn+ssh"
    elseif u.transport == "http" or u.transport == "https"
        or u.transport == "svn" or u.transport == "file" then
        transport = u.transport
    else
        return nil,
            e:append("unsupported subversion transport: %s", u.transport)
    end

    return string.format("%s://%s/%s", transport, u.server, u.path)
end

--- Call the svn command.
-- @param argv table: vector with arguments for svn
-- @param workdir Directory where svn command starts executing (optional).
-- @return True on success, false on error or when svn returned with exit
--         status other than 0.
-- @return Error object on failure.
local function svn_tool(argv, workdir)
    assert(type(argv) == "table")
    assert(workdir == nil or type(workdir) == "string")

    local rc, re
    local svncmd, out, fifo

    out = {}
    fifo = {}

    svncmd, re = tools.get_tool_flags_argv("svn")
    if not svncmd then
        return false, re
    end

    for _,arg in ipairs(argv) do
        table.insert(svncmd, arg)
    end

    local function capture(msg)
        if msg == "" then
            return
        end

        if #fifo > 4 then
            table.remove(fifo, 1)
        end

        e2lib.log(3, msg)
        table.insert(fifo, msg)
        table.insert(out, msg)
    end

    rc, re = e2lib.callcmd_capture(svncmd, capture, workdir)
    if not rc then
        return false, err.new("svn command %q failed to execute",
            table.concat(svncmd, " ")):cat(re)

    elseif rc ~= 0 then
        local e = err.new("svn command %q failed with exit status %d",
            table.concat(svncmd, " "), rc)
        for _,v in ipairs(fifo) do
            e:append("%s", v)
        end
        return false, e
    end

    return true, nil, table.concat(out)
end

function svn.svn_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and #rawsrc.name > 0)
    assert(type(rawsrc.type) == "string" and rawsrc.type == "svn")

    local rc, re

    source.basic_source.initialize(self, rawsrc)

    self._server = false
    self._location = false
    self._tag = false
    self._branch = false
    self._working = false
    self._workingcopy_subdir = false
    self._sourceids = {
        ["working-copy"] = "working-copy"
    }

    rc, re = e2lib.vrfy_dict_exp_keys(rawsrc, "e2source", {
        "branch",
        "env",
        "licences",
        "location",
        "name",
        "server",
        "tag",
        "type",
        "working",
        "workingcopy_subdir",
    })

    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_licences(rawsrc, self)
    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_env(rawsrc, self)
    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_server(rawsrc, true)
    if not rc then
        error(re)
    end
    self._server = rawsrc.server

    rc, re = source.generic_source_validate_working(rawsrc)
    if not rc then
        error(re)
    end
    self._working = rawsrc.working

    -- workingcopy_subdir is optional and defaults to the branch
    -- make sure branch is checked first to avoid confusing error
    if rawsrc.workingcopy_subdir == nil then
        rawsrc.workingcopy_subdir = rawsrc.branch
    end

    for _,attr in ipairs({"branch", "location", "tag", "workingcopy_subdir"}) do
        if rawsrc[attr] == nil then
            error(err.new("source has no `%s' attribute", attr))
        elseif type(rawsrc[attr]) ~= "string" then
            error(err.new("'%s' must be a string", attr))
        elseif rawsrc[attr] == "" then
            error(err.new("'%s' may not be empty", attr))
        end
    end

    self._branch = rawsrc.branch
    self._location = rawsrc.location
    self._tag = rawsrc.tag
    self._workingcopy_subdir = rawsrc.workingcopy_subdir
end

function svn.svn_source:get_working()
    assert(type(self._working) == "string")
    return self._working
end

function svn.svn_source:get_workingcopy_subdir()
    assert(type(self._workingcopy_subdir) == "string")
    return self._workingcopy_subdir
end

function svn.svn_source:get_server()
    assert(type(self._server) == "string")
    return self._server
end

function svn.svn_source:get_location()
    assert(type(self._location) == "string")
    return self._location
end

function svn.svn_source:get_branch()
    assert(type(self._branch) == "string")
    return self._branch
end

function svn.svn_source:get_tag()
    assert(type(self._tag) == "string")
    return self._tag
end

function svn.svn_source:sourceid(sourceset)
    assert(type(sourceset) == "string" and #sourceset > 0)

    local rc, re
    local hc, surl, svnurl, argv, out, svnrev, lid, svnrev, licences

    if self._sourceids[sourceset] then
        return self._sourceids[sourceset]
    end

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)
    hash.hash_append(hc, self._env:envid())

    licences = self:get_licences()
    for licencename in licences:iter() do
        lid, re = licence.licences[licencename]:licenceid()
        if not lid then
            return false, re
        end
        hash.hash_append(hc, lid)
    end

    surl, re = cache.remote_url(cache.cache(), self._server, self._location)
    if not surl then
        return false, re
    end

    svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, re
    end

    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._location)

    if sourceset == "tag" then
        hash.hash_append(hc, self._tag)
        argv = { "info", svnurl.."/"..self._tag }
    elseif sourceset == "branch" then
        hash.hash_append(hc, self._branch)
        argv = { "info", svnurl.."/"..self._branch }
    else
        return false,
            err.new("svn sourceid can't handle sourceset %q", sourceset)
    end

    rc, re, out = svn_tool(argv)
    if not rc then
        return false,
            err.new("retrieving revision for tag or branch failed"):cat(re)
    end

    svnrev = string.match(out, "Last Changed Rev: (%d+)")
    if not svnrev or string.len(svnrev) == 0 then
        return false, err.new("could not find SVN revision")
    end
    hash.hash_append(hc, svnrev)

    self._sourceids[sourceset] = hash.hash_finish(hc)

    return self._sourceids[sourceset]
end

function svn.svn_source:display()
    local d, licences

    -- try to calculte the sourceid, but do not care if it fails.
    -- working copy might be unavailable
    self:sourceid("tag")
    self:sourceid("branch")

    d = {}
    table.insert(d, string.format("type       = %s", self:get_type()))
    table.insert(d, string.format("server     = %s", self._server))
    table.insert(d, string.format("remote     = %s", self._location))
    table.insert(d, string.format("branch     = %s", self._branch))
    table.insert(d, string.format("tag        = %s", self._tag))
    table.insert(d, string.format("working    = %s", self:get_working()))

    licences = self:get_licences()
    for licencename in licences:iter() do
        table.insert(d, string.format("licence    = %s", licencename))
    end

    for sourceset, sid in pairs(self._sourceids) do
        if sid then
            table.insert(d, string.format("sourceid [%s] = %s", sourceset, sid))
        end
    end

    return d
end

function svn.svn_source:working_copy_available()
    if not e2lib.isdir(e2lib.join(e2tool.root(), self._working)) then
        return false, err.new("working copy for %s is not available", self._name)
    end
    return true
end

function svn.svn_source:check_workingcopy()
    local rc, re
    local e = err.new("checking working copy failed")
    e:append("in source %s (svn configuration):", self._name)
    e:setcount(0)
    if e:getcount() > 0 then
        return false, e
    end
    -- check if the configured branch and tag exist
    local d
    d = e2lib.join(e2tool.root(), self:get_working(), self._branch)
    if not e2lib.isdir(d) then
        e:append("branch does not exist: %s", self._branch)
    end
    d = e2lib.join(e2tool.root(), self:get_working(), self._tag)
    if not e2lib.isdir(d) then
        e:append("tag does not exist: %s", self._tag)
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true
end

function svn.svn_source:fetch_source()
    local rc, re
    local e = err.new("fetching source failed: %s", self._name)
    local surl, re = cache.remote_url(cache.cache(), self._server, self._location)
    if not surl then
        return false, e:cat(re)
    end
    local svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, e:cat(re)
    end

    if self:working_copy_available() then
        return true
    end

    local argv = { "checkout", svnurl, e2tool.root() .. "/" .. self:get_working() }

    rc, re = svn_tool(argv)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

function svn.svn_source:update_source()
    local rc, re
    local e = err.new("updating source '%s' failed", self._name)
    local workdir = e2lib.join(e2tool.root(), self:get_working())
    rc, re = svn_tool({ "update" }, workdir)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

function svn.svn_source:prepare_source(sourceset, buildpath)
    local rc, re
    local e = err.new("preparing source for build failed: %s", self._name)
    local surl, re = cache.remote_url(cache.cache(), self._server, self._location)
    if not surl then
        return false, e:cat(re)
    end
    local svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, e:cat(re)
    end
    if sourceset == "tag" or sourceset == "branch" then
        local rev
        if sourceset == "tag" then
            rev = self._tag
        else -- sourceset == "branch"
            rev = self._branch
        end
        local argv = { "export", svnurl .. "/" .. rev,
            buildpath .. "/" .. self._name }
        rc, re = svn_tool(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        local s = e2lib.join(e2tool.root(), self:get_working(),
            self:get_workingcopy_subdir())
        local d = e2lib.join(buildpath, self._name)
        rc, re = e2lib.cp(s, d, true)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:cat("invalid source set")
    end
    return true
end

--------------------------------------------------------------------------------

local function svn_to_result(src, sourceset, directory)
    -- <directory>/source/<sourcename>.tar.gz
    -- <directory>/makefile
    -- <directory>/licences
    local rc, re
    local e = err.new("converting %s to result", src:get_name())
    local src = source.sources[src:get_name()]

    rc, re = src:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = src:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    -- write makefile
    local makefile = "Makefile"
    local source = "source"
    local sourcedir = e2lib.join(directory, source)
    local archive = string.format("%s.tar.gz", src:get_name())
    local fname  = e2lib.join(directory, makefile)
    rc, re = e2lib.mkdir_recursive(sourcedir)
    if not rc then
        return false, e:cat(re)
    end
    local out = string.format(
        ".PHONY:\tplace\n\n"..
        "place:\n"..
        "\ttar xzf \"%s/%s\" -C \"$(BUILD)\"\n", source, archive)
    rc, re = eio.file_write(fname, out)
    -- export the source tree to a temporary directory
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, e:cat(re)
    end

    rc, re = src:prepare_source(sourceset, tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    -- create a tarball in the final location
    local archive = string.format("%s.tar.gz", src:get_name())
    rc, re = e2lib.tar({ "-C", tmpdir ,"-czf", sourcedir .. "/" .. archive,
        src:get_name() })
    if not rc then
        return false, e:cat(re)
    end
    -- write licences
    local destdir = e2lib.join(directory, "licences")
    local fname = string.format("%s/%s.licences", destdir, archive)
    local licences = src:get_licences()
    local licence_list = licences:concat("\n") .. "\n"
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = eio.file_write(fname, licence_list)
    if not rc then
        return false, e:cat(re)
    end
    e2lib.rmtempdir(tmpdir)
    return true, nil
end

--------------------------------------------------------------------------------

plugin_descriptor = {
    description = "SVN SCM Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("svn", svn.svn_source)
        if not rc then
            return false, re
        end

        for typ, theclass in result.iterate_result_classes() do
            if typ == "collect_project" then
                theclass:add_source_to_result_fn("svn", svn_to_result)
                break
            end
        end

        if e2tool.current_tool() == "fetch-sources" then
            e2option.flag("svn", "select svn sources")
        end

        return true
    end,
    exit = function (ctx) return true end,
    depends = {
        "collect_project.lua"
    }
}


strict.lock(svn)

-- vim:sw=4:sts=4:et:
