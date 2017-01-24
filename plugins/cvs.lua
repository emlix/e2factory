--- CVS Plugin
-- @module plugins.cvs

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

local cvs = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local scm = require("scm")
local source = require("source")
local strict = require("strict")
local tools = require("tools")
local url = require("url")

plugin_descriptor = {
    description = "CVS SCM Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("cvs", cvs.cvs_source)
        if not rc then
            return false, re
        end

        rc, re = scm.register("cvs", cvs)
        if not rc then
            return false, re
        end

        if e2tool.current_tool() == "fetch-sources" then
            e2option.flag("cvs", "select cvs sources")
        end

        return true
    end,
    exit = function (ctx) return true end,
}

--------------------------------------------------------------------------------

--- Build the cvsroot string.
-- @param src Source object.
-- @return CVSROOT string or false on error.
-- @return Error object on failure.
local function mkcvsroot(src)
    local cvsroot, surl, u, re

    surl, re = cache.remote_url(cache.cache(), src:get_server(), src:get_cvsroot())
    if not surl then
        return false, e:cat(re)
    end

    u, re = url.parse(surl)
    if not u then
        return false, e:cat(re)
    end

    if u.transport == "file" then
        cvsroot = string.format("/%s", u.path)
    elseif (u.transport == "ssh") or (u.transport == "rsync+ssh") or
        u.transport == "scp" then
        cvsroot = string.format("%s:/%s", u.server, u.path)
    elseif u.transport == "cvspserver" then
        cvsroot = string.format(":pserver:%s:/%s", u.server, u.path)
    else
        return false, err.new("cvs: unhandled transport: %s", u.transport)
    end

    return cvsroot
end

local function cvs_tool(argv, workdir)
    local rc, re, cvscmd, cvsflags, rsh

    cvscmd, re = tools.get_tool_flags_argv("cvs")
    if not cvscmd then
        return false, re
    end

    for _,arg in ipairs(argv) do
        table.insert(cvscmd, arg)
    end

    rsh, re = tools.get_tool("ssh")
    if not rsh then
        return false, re
    end

    return e2lib.callcmd_log(cvscmd, workdir, { CVS_RSH=rsh })
end

--------------------------------------------------------------------------------

cvs.cvs_source = class("cvs_source", source.basic_source)

function cvs.cvs_source.static:is_scm_source_class()
    return true
end

function cvs.cvs_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)

    if e2tool.current_tool() == "fetch-sources" and opts["cvs"] then
        return true
    end
    return false
end

function cvs.cvs_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and #rawsrc.name > 0)
    assert(type(rawsrc.type) == "string" and rawsrc.type == "cvs")

    local rc, re

    source.basic_source.initialize(self, rawsrc)

    self._branch = false
    self._cvsroot = false
    self._module = false
    self._server = false
    self._tag = false
    self._working = false
    self._sourceids = {
        ["working-copy"] = "working-copy",
    }

    rc, re = e2lib.vrfy_dict_exp_keys(rawsrc, "e2source", {
        "branch",
        "cvsroot",
        "env",
        "licences",
        "module",
        "name",
        "server",
        "tag",
        "type",
        "working",
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

    if rawsrc.cvsroot == nil then
        e2lib.warnf("WDEFAULT", "in source %s:", self._name)
        e2lib.warnf("WDEFAULT",
        " source has no `cvsroot' attribute, defaulting to the server path")
        self._cvsroot = "."
    elseif type(rawsrc.cvsroot) == "string" then
        self._cvsroot = rawsrc.cvsroot
    else
        error(err.new("'cvsroot' must be a string"))
    end

    for _,attr in ipairs({ "branch", "module", "tag" }) do
        if rawsrc[attr] == nil then
            error(err.new("source has no `%s' attribute", attr))
        elseif type(rawsrc[attr]) ~= "string" then
            error(err.new("'%s' must be a string", attr))
        elseif rawsrc[attr] == "" then
            error(err.new("'%s' may not be empty", attr))
        end
    end
    self._branch = rawsrc.branch
    self._module = rawsrc.module
    self._tag = rawsrc.tag
end

function cvs.cvs_source:get_working()
    assert(type(self._working) == "string")

    return self._working
end

function cvs.cvs_source:get_module()
    assert(type(self._module) == "string")

    return self._module
end

function cvs.cvs_source:get_branch()
    assert(type(self._branch) == "string")

    return self._branch
end

function cvs.cvs_source:get_tag()
    assert(type(self._tag) == "string")

    return self._tag
end

function cvs.cvs_source:get_server()
    assert(type(self._server) == "string")

    return self._server
end

function cvs.cvs_source:get_cvsroot()
    assert(type(self._cvsroot) == "string")

    return self._cvsroot
end

function cvs.cvs_source:sourceid(sourceset)
    assert(type(sourceset) == "string" and #sourceset > 0)

    local rc, re, hc, lid, licences

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
    -- cvs specific
    if sourceset == "tag" and self._tag ~= "^" then
        -- we rely on tags being unique with cvs
        hash.hash_append(hc, self._tag)
    else
        -- the old function took a hash of the CVS/Entries file, but
        -- forgot the subdirecties' CVS/Entries files. We might
        -- reimplement that once...
        return false, err.new("cannot calculate sourceid for source set %s",
            sourceset)
    end
    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._cvsroot)
    hash.hash_append(hc, self._module)

    self._sourceids[sourceset] = hash.hash_finish(hc)

    return self._sourceids[sourceset]
end

function cvs.cvs_source:display()
    local licences
    local d = {}

    self:sourceid("tag")
    self:sourceid("branch")

    table.insert(d, string.format("type       = %s", self:get_type()))
    table.insert(d, string.format("branch     = %s", self._branch))
    table.insert(d, string.format("tag        = %s", self._tag))
    table.insert(d, string.format("server     = %s", self._server))
    table.insert(d, string.format("cvsroot    = %s", self._cvsroot))
    table.insert(d, string.format("module     = %s", self._module))
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

function cvs.cvs_source:working_copy_available()
    if not e2lib.isdir(e2lib.join(e2tool.root(), self._working)) then
        return false, err.new("working copy for %s is not available", self._name)
    end
    return true
end

function cvs.cvs_source:check_workingcopy()
    return true
end

function cvs.cvs_source:fetch_source()
    local rc, re, e, cvsroot, workdir, argv

    e = err.new("fetching source failed: %s", self._name)

    if self:working_copy_available() then
        return true
    end

    cvsroot, re = mkcvsroot(self)
    if not cvsroot then
        return false, e:cat(re)
    end

    -- split the working directory into dirname and basename as some cvs clients
    -- don't like slashes (e.g. in/foo) in their checkout -d<path> argument
    workdir = e2lib.dirname(e2lib.join(e2tool.root(), self:get_working()))

    argv = {
        "-d", cvsroot,
        "checkout",
        "-R",
        "-d", e2lib.basename(self:get_working()),
    }

    -- always fetch the configured branch, as we don't know the build mode here.
    -- HEAD has special meaning to cvs
    if self:get_branch() ~= "HEAD" then
        table.insert(argv, "-r")
        table.insert(argv, self:get_branch())
    end

    table.insert(argv, self:get_module())

    rc, re = cvs_tool(argv, workdir)
    if not rc or rc ~= 0 then
        return false, e:cat(re)
    end
    return true
end

function cvs.cvs_source:prepare_source(sourceset, buildpath)
    local rc, re, e, cvsroot, argv

    e = err.new("cvs.prepare_source failed")

    cvsroot, re = mkcvsroot(self)
    if not cvsroot then
        return false, re
    end

    if sourceset == "tag" or sourceset == "branch" then
        argv = {
            "-d", cvsroot,
            "export", "-R",
            "-d", self:get_name(),
            "-r",
        }

        if sourceset == "branch" or
            (sourceset == "lazytag" and self:get_tag() == "^") then
            table.insert(argv, self:get_branch())
        elseif (sourceset == "tag" or sourceset == "lazytag") and
            self:get_tag() ~= "^" then
            table.insert(argv, self:get_tag())
        else
            return false, e:cat(err.new("source set not allowed"))
        end

        table.insert(argv, self:get_module())

        rc, re = cvs_tool(argv, buildpath)
        if not rc or rc ~= 0 then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        rc, re = e2lib.cp(e2lib.join(e2tool.root(), self:get_working()),
            e2lib.join(buildpath, self:get_name()), true)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, err.new("invalid build mode")
    end
    return true, nil
end

function cvs.cvs_source:update_source()
    local rc, re, e, workdir, argv

    e = err.new("updating source '%s' failed", self._name)

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    workdir = e2lib.join(e2tool.root(), self:get_working())

    argv = { "update", "-R" }
    rc, re = cvs_tool(argv, workdir)
    if not rc or rc ~= 0 then
        return false, e:cat(re)
    end

    return true
end

--------------------------------------------------------------------------------

function cvs.toresult(info, sourcename, sourceset, directory)
    -- <directory>/source/<sourcename>.tar.gz
    -- <directory>/makefile
    -- <directory>/licences
    local rc, re, out
    local e = err.new("converting result")
    local src = source.sources[sourcename]

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
    local sourcedir = string.format("%s/%s", directory, source)
    local archive = string.format("%s.tar.gz", sourcename)
    local fname  = string.format("%s/%s", directory, makefile)
    rc, re = e2lib.mkdir_recursive(sourcedir)
    if not rc then
        return false, e:cat(re)
    end

    out = string.format(
        ".PHONY:\tplace\n\n"..
        "place:\n"..
        "\ttar xzf \"%s/%s\" -C \"$(BUILD)\"\n", source, archive)

    rc, re = eio.file_write(fname, out)
    if not rc then
        return false, e:cat(re)
    end
    -- export the source tree to a temporary directory
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
    end

    rc, re = src:prepare_source(sourceset, tmpdir)
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
    local destdir = string.format("%s/licences", directory)
    local fname = string.format("%s/%s.licences", destdir, archive)
    local licenses = src:get_licences()
    local licence_list = licenses:concat("\n").."\n"

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

strict.lock(cvs)

-- vim:sw=4:sts=4:et:
