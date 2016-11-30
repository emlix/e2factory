--- Subversion Plugin
-- @module plugins.svn

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

local svn = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local scm = require("scm")
local strict = require("strict")
local tools = require("tools")
local url = require("url")
local source = require("source")

plugin_descriptor = {
    description = "SVN SCM Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("svn", svn.svn_source)
        if not rc then
            return false, re
        end

        rc, re = scm.register("svn", svn)
        if not rc then
            return false, re
        end

        return true
    end,
    exit = function (ctx) return true end,
}

svn.svn_source = class("svn_source", source.basic_source)

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
    local svn, flags, svncmd, out, fifo

    svncmd = {}
    out = {}
    fifo = {}

    svn, re = tools.get_tool("svn")
    if not svn then
        return false, re
    end

    table.insert(svncmd, svn)

    flags, re = tools.get_tool_flags("svn")
    if not flags then
        return false, re
    end

    for _,flag in ipairs(flags) do
        table.insert(svncmd, flag)
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
    local hc, surl, svnurl, argv, out, svnrev, lid, svnrev, info, licences

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

    info = e2tool.info()
    assert(type(info) == "table")

    surl, re = cache.remote_url(info.cache, self._server, self._location)
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
    elseif sourceset == "lazytag" then
        return false, err.new("svn source does not support lazytag mode")
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

function svn.fetch_source(info, sourcename)
    local rc, re
    local e = err.new("fetching source failed: %s", sourcename)
    local src = source.sources[sourcename]
    local location = src:get_location()
    local server = src:get_server()
    local surl, re = cache.remote_url(info.cache, server, location)
    if not surl then
        return false, e:cat(re)
    end
    local svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, e:cat(re)
    end

    local argv = { "checkout", svnurl, info.root .. "/" .. src:get_working() }

    rc, re = svn_tool(argv)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

function svn.prepare_source(info, sourcename, sourceset, build_path)
    local rc, re
    local e = err.new("svn.prepare_source failed")
    local src = source.sources[sourcename]
    local location = src:get_location()
    local server = src:get_server()
    local surl, re = cache.remote_url(info.cache, server, location)
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
            rev = src:get_tag()
        else -- sourceset == "branch"
            rev = src:get_branch()
        end
        local argv = { "export", svnurl .. "/" .. rev,
        build_path .. "/" .. sourcename }
        rc, re = svn_tool(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        -- cp -R info.root/src.working/src.workingcopy_subdir build_path
        local s = e2lib.join(info.root, src:get_working(),
            src:get_workingcopy_subdir())
        local d = e2lib.join(build_path, src:get_name())
        rc, re = e2lib.cp(s, d, true)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:cat("invalid source set")
    end
    return true, nil
end

function svn.working_copy_available(info, sourcename)
    local rc, re
    local src = source.sources[sourcename]

    local dir = e2lib.join(info.root, src:get_working())
    return e2lib.isdir(dir)
end

function svn.check_workingcopy(info, sourcename)
    local rc, re
    local e = err.new("checking working copy failed")
    e:append("in source %s (svn configuration):", sourcename)
    e:setcount(0)
    local src = source.sources[sourcename]
    if e:getcount() > 0 then
        return false, e
    end
    -- check if the configured branch and tag exist
    local d
    d = e2lib.join(info.root, src:get_working(), src:get_branch())
    if not e2lib.isdir(d) then
        e:append("branch does not exist: %s", src:get_branch())
    end
    d = e2lib.join(info.root, src:get_working(), src:get_tag())
    if not e2lib.isdir(d) then
        e:append("tag does not exist: %s", src:get_tag())
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true
end

function svn.has_working_copy(info, sname)
    return true
end

function svn.toresult(info, sourcename, sourceset, directory)
    -- <directory>/source/<sourcename>.tar.gz
    -- <directory>/makefile
    -- <directory>/licences
    local rc, re
    local e = err.new("converting result")
    rc, re = scm.generic_source_check(info, sourcename, true)
    if not rc then
        return false, e:cat(re)
    end
    local src = source.sources[sourcename]
    -- write makefile
    local makefile = "Makefile"
    local source = "source"
    local sourcedir = e2lib.join(directory, source)
    local archive = string.format("%s.tar.gz", sourcename)
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

    rc, re = svn.prepare_source(info, sourcename, sourceset, tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    -- create a tarball in the final location
    local archive = string.format("%s.tar.gz", src:get_name())
    rc, re = e2lib.tar({ "-C", tmpdir ,"-czf", sourcedir .. "/" .. archive,
    sourcename })
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

function svn.update(info, sourcename)
    local rc, re
    local e = err.new("updating source '%s' failed", sourcename)
    local src = source.sources[sourcename]
    local workdir = e2lib.join(info.root, src:get_working())
    rc, re = svn_tool({ "update" }, workdir)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

strict.lock(svn)

-- vim:sw=4:sts=4:et:
