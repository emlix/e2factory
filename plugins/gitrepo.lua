--- Gitrepo Plugin
-- @module plugins.gitrepo

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

local gitrepo = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local generic_git = require("generic_git")
local hash = require("hash")
local licence = require("licence")
local result = require("result")
local source = require("source")
local strict = require("strict")
local url = require("url")

local gitrepo_source = class("gitrepo_source", source.basic_source)

function gitrepo_source.static:is_scm_source_class()
    return true
end

function gitrepo_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)

    if e2tool.current_tool() == "fetch-sources" and opts["gitrepo"] then
        return true
    end
    return false
end

function gitrepo_source:initialize(rawsrc)
    assertIsTable(rawsrc)
    assertIsStringN(rawsrc.name)
    assertIsStringN(rawsrc.type)

    local rc, re

    source.basic_source.initialize(self, rawsrc)

    self._server = false
    self._working = false
    self._branch = false
    self._location = false
    self._tag = false
    self._sourceids = { ["working-copy"] = "working-copy", }

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

    for _,attr in ipairs({ "branch", "location", "tag" }) do
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
end

function gitrepo_source:get_working()
    assertIsString(self._working)
    return self._working
end

function gitrepo_source:get_server()
    assertIsString(self._server)
    return self._server
end

function gitrepo_source:get_location()
    assertIsString(self._location)
    return self._location
end

function gitrepo_source:get_branch()
    assertIsString(self._branch)
    return self._branch
end

function gitrepo_source:get_tag()
    assertIsString(self._tag)
    return self._tag
end

function gitrepo_source:sourceid(sourceset)
    assertIsStringN(sourceset)

    local rc, re, e, hc, gitdir, argv, out

    if self._sourceids[sourceset] then
        return self._sourceids[sourceset]
    end

    e = err.new("calculating SourceID for %s failed", self._name)

    assert(sourceset == "tag" or sourceset == "branch")

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)
    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._location)
    hash.hash_append(hc, sourceset) -- otherwise tag and branch id identical
    hash.hash_append(hc, self._tag)
    hash.hash_append(hc, self._branch)
    hash.hash_append(hc, self._env:envid())

    for licencename in self:licences():iter() do
        local lid, re = licence.licences[licencename]:licenceid()
        if not lid then
            return false, e:cat(re)
        end
        hash.hash_append(hc, lid)
    end

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = self:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    argv = generic_git.git_new_argv(nil,
        e2lib.join(e2tool.root(), self:get_working()), "show-ref")
    rc, re, out = generic_git.git(argv)
    if not rc then
        return false, e:cat(re)
    end
    hash.hash_append(hc, out)

    self._sourceids[sourceset] = hash.hash_finish(hc)

    e2lib.logf(4, "BUILDID: source=%s sourceset=%s sourceid=%s",
        self._name, sourceset, self._sourceids[sourceset])

    return self._sourceids[sourceset]
end

function gitrepo_source:display()
    -- try to calculate the sourceid, but do not care if it fails.
    -- working copy might be unavailable
    self:sourceid("tag")
    self:sourceid("branch")

    local d = {}
    table.insert(d, string.format("type       = %s", self:get_type()))
    table.insert(d, string.format("branch     = %s", self._branch))
    table.insert(d, string.format("tag        = %s", self._tag))
    table.insert(d, string.format("server     = %s", self._server))
    table.insert(d, string.format("location   = %s", self._location))
    table.insert(d, string.format("working    = %s", self._working))

    for licencename in self:licences():iter() do
        table.insert(d, string.format("licence    = %s", licencename))
    end

    for sourceset, sid in pairs(self._sourceids) do
        if sid then
            table.insert(d, string.format("sourceid [%s] = %s", sourceset, sid))
        end
    end

    return d
end

--- Check if a working copy for a git repository is available
-- @return True if available, false otherwise.
-- @return Error object if no directory.
function gitrepo_source:working_copy_available()
    if not e2lib.isdir(e2lib.join(e2tool.root(), self._working)) then
        return false, err.new("working copy for %s is not available", self._name)
    end
    return true
end

function gitrepo_source:check_workingcopy()

    --- turn server:location into a git-style url
    -- @param c table: a cache
    -- @param server string: server name
    -- @param location string: location
    -- @return string: the git url, or nil
    -- @return an error object on failure
    local function git_url(c, server, location)
        local e = err.new("translating server:location to git url")
        local rurl, re = cache.remote_url(c, server, location)
        if not rurl then
            return nil, e:cat(re)
        end
        local u, re = url.parse(rurl)
        if not u then
            return nil, e:cat(re)
        end
        local g, re = generic_git.git_url1(u)
        if not g then
            return nil, e:cat(re)
        end
        return g, nil
    end

    local rc, re
    local e = err.new("checking working copy of source %s failed", self._name)

    -- check if branch exists
    local gitdir = e2lib.join(e2tool.root(), self:get_working(), ".git")
    local ref = string.format("refs/heads/%s", self._branch)
    local id

    rc = self:working_copy_available()
    if not rc then
        e2lib.warnf("WOTHER", "in source %s: ", self._name)
        e2lib.warnf("WOTHER", " working copy is not available")
        return true, nil
    end

    rc, re, id = generic_git.lookup_id(gitdir, false, ref)
    if not rc then
        return false, e:cat(re)
    elseif not id then
        return false, e:cat(err.new("branch %q does not exist", self._branch))
    end

    -- git config branch.<branch>.remote == "origin"
    local query, expect, res
    query = string.format("branch.%s.remote", self._branch)
    res, re = generic_git.git_config(gitdir, query)
    if not res then
        e:append("remote is not configured for branch \"%s\"", self._branch)
        return false, e
    elseif res ~= "origin" then
        e:append("%s is not \"origin\"", query)
        return false, e
    end

    -- git config remote.origin.url == server:location
    query = string.format("remote.origin.url")
    expect, re = git_url(cache.cache(), self._server, self._location)
    if not expect then
        return false, e:cat(re)
    end
    res, re = generic_git.git_config(gitdir, query)
    if not res then
        return false, e:cat(re)
    end

    local function remove_trailing_slashes(s)
        while s:sub(#s) == "/" do
            s = s:sub(1, #s-1)
        end
        return s
    end

    res = remove_trailing_slashes(res)
    expect = remove_trailing_slashes(expect)
    if res ~= expect then
        e:append('git variable "%s" does not match e2 source configuration.',
            query)
        e:append('expected "%s" but got "%s" instead.', expect, res)
        return false, e
    end

    return true
end

function gitrepo_source:fetch_source()
    local e, rc, re, git_dir, work_tree, id

    e = err.new("fetching source failed: %s", self._name)

    if self:working_copy_available() then
        return true
    end

    work_tree = e2lib.join(e2tool.root(), self:get_working())
    git_dir = e2lib.join(work_tree, ".git")

    e2lib.logf(2, "cloning %s:%s [%s]", self:get_server(), self:get_location(),
        self:get_branch())

    rc, re = generic_git.git_clone_from_server(cache.cache(), self:get_server(),
        self:get_location(), work_tree, false --[[always checkout]])
    if not rc then
        return false, e:cat(re)
    end

    rc, re, id = generic_git.lookup_id(git_dir, false,
        "refs/heads/" .. self:get_branch())
    if not rc then
        return false, e:cat(re)
    elseif not id then
        rc, re = generic_git.git_branch_new1(work_tree, true, self:get_branch(),
            "origin/" .. self:get_branch())
        if not rc then
            return false, e:cat(re)
        end

        rc, re = generic_git.git_checkout1(work_tree,
            "refs/heads/" .. self:get_branch())
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- update a working copy
-- @return bool
-- @return an error object
function gitrepo_source:update_source()
    local e, rc, re, gitwc, gitdir, argv, id, branch, remote

    e = err.new("updating source '%s' failed", self._name)

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = self:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    e2lib.logf(2, "updating %s [%s]", self:get_working(), self:get_branch())

    gitwc  = e2lib.join(e2tool.root(), self:get_working())
    gitdir = e2lib.join(gitwc, ".git")

    argv = generic_git.git_new_argv(gitdir, gitwc, "fetch")
    rc, re = generic_git.git(argv)
    if not rc then
        return false, e:cat(re)
    end

    argv = generic_git.git_new_argv(gitdir, gitwc, "fetch", "--tags")
    rc, re = generic_git.git(argv)
    if not rc then
        return false, e:cat(re)
    end

    -- Use HEAD commit ID to find the branch we're on
    rc, re, id = generic_git.lookup_id(gitdir, false, "HEAD")
    if not rc then
        return false, e:cat(re)
    elseif not id then
        return false, e:cat(err.new("can not find commit ID for HEAD"))
    end

    rc, re, branch = generic_git.lookup_ref(gitdir, false, id, "refs/heads/")
    if not rc then
        return false, e:cat(re)
    elseif not branch then
        e2lib.warnf("WOTHER", "HEAD is not on a branch (detached?). Skipping")
        return true
    end

    if branch ~= "refs/heads/" .. self:get_branch() then
        e2lib.warnf("WOTHER", "not on configured branch. Skipping.")
        return true
    end

    remote, re = generic_git.git_config(
        gitdir, "branch."..self:get_branch()..".remote")
    if not remote or string.len(remote) == 0  then
        e2lib.warnf("WOTHER", "no remote configured for branch %q. Skipping.",
            self:get_branch())
        return true
    end

    branch = remote .. "/" .. self:get_branch()
    argv = generic_git.git_new_argv(gitdir, gitwc, "merge", "--ff-only", branch)
    rc, re = generic_git.git(argv)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- prepare source for building.
-- @param sourceset can be either:
-- "tag": the git repository will be checked out to the tag
-- "branch": the git repository will be checked out to the branch
-- "working-copy": a exact working copy of the repository will be created
-- @param buildpath the path where the source will be created
-- @return True on success, false on failure.
-- @return Error object on failure.
function gitrepo_source:prepare_source(sourceset, buildpath)
    assertIsStringN(sourceset)
    assertIsStringN(buildpath)

    local rc, re, e
    local argv, destdir, worktree, ref

    e = err.new("preparing source failed: %s", self._name)

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = self:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    if sourceset == "tag" or sourceset == "branch" then
        destdir = e2lib.join(buildpath, self._name, ".git")
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        worktree = e2lib.join(e2tool.root(), self:get_working())
        argv = generic_git.git_new_argv(false, false, "clone",
            "--mirror", worktree, destdir)
        rc, re = generic_git.git(argv)
        if not rc then
            return false, e:cat(re)
        end

        rc, re = generic_git.git_config(destdir, "core.bare", "false")
        if not rc then
            return false, e:cat(re)
        end

        if sourceset == "tag" then
            ref = string.format("refs/tags/%s", self:get_tag())
        else
            ref = string.format("refs/heads/%s", self:get_branch())
        end

        rc, re = generic_git.git_checkout1(e2lib.join(destdir, ".."), ref)
	if not rc then
    	    return false, e:cat(re)
	end
    elseif sourceset == "working-copy" then
        local argv = {
            "-a",
            e2lib.join(e2tool.root(), self:get_working(), ""),
            e2lib.join(buildpath, self._name),
        }
        rc, re = e2lib.rsync(argv)
	if not rc then
	    return false, e:cat(re)
	end
    else
        return false, err.new("preparing source failed, not a valid type: %s, %s",
            self._name, sourceset)
    end

    return true
end

--------------------------------------------------------------------------------

--- Archives the source and prepares the necessary files outside the archive
-- @param src source object
-- @param sourceset string, should be "tag" "branch" or "working copy", in order for it to work
-- @param directory the directory where the sources are and where the archive is to be created
-- @return True on success, false on error.
-- @return Error object on failure
local function gitrepo_to_result(src, sourceset, directory)
    assertIsTable(src)
    assertIsStringN(sourceset)
    assertIsStringN(directory)

    local rc, re, e
    local srcdir, sourcedir, archive
    local argv

    e = err.new("converting source %q failed", src:get_name())

    rc, re = src:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = src:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    srcdir = "source"
    sourcedir = e2lib.join(directory, srcdir)
    archive = string.format("%s.tar.gz", src:get_name())

    rc, re = e2lib.mkdir(sourcedir)
    if not rc then
        return false, e:cat(re)
    end

    if sourceset == "tag" or sourceset == "branch" then
        local tmpdir = e2lib.mktempdir()
        local worktree = e2lib.join(e2tool.root(), src:get_working())
        local destdir = e2lib.join(tmpdir, src:get_name(), ".git")

        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        argv = generic_git.git_new_argv(false, false, "clone",
            "--mirror", worktree, destdir)
        rc, re = generic_git.git(argv)
        if not rc then
            return false, e:cat(re)
        end

        rc, rc = e2lib.tar({"-czf", e2lib.join(sourcedir, archive),
            "-C", tmpdir, src:get_name()})
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        rc, rc = e2lib.tar({"-czf", e2lib.join(sourcedir, archive),
            "-C", e2lib.join(e2tool.root(), src:get_working(), ".."),
            src:get_name()})
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:cat("build mode %s not supported", source_set)
    end

    local builddir = e2lib.join("$(BUILD)", src:get_name())
    local makefile = e2lib.join(directory, "Makefile")
    if sourceset == "tag" then
        rc, re = eio.file_write(makefile, string.format(
            ".PHONY: place\n\n"..
            "place:\n"..
            "\ttar -xzf %s -C '$(BUILD)'\n"..
            "\tcd %s && git config core.bare false\n"..
            "\tcd %s && git checkout %s\n",
            e2lib.shquote(e2lib.join(srcdir, archive)),
            e2lib.shquote(builddir), e2lib.shquote(builddir),
            e2lib.shquote("refs/tags/"..src:get_tag())))
        if not rc then
            return false, e:cat(re)
        end
    elseif  sourceset == "branch" then
        rc, re = eio.file_write(makefile, string.format(
            ".PHONY: place\n\n"..
            "place:\n"..
            "\ttar -xzf %s -C '$(BUILD)'\n"..
            "\tcd %s && git config core.bare false\n"..
            "\tcd %s && git checkout %s\n",
            e2lib.shquote(e2lib.join(srcdir, archive)),
            e2lib.shquote(builddir), e2lib.shquote(builddir),
            e2lib.shquote("refs/heads/"..src:get_branch())))
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        rc, re = eio.file_write(makefile, string.format(
            ".PHONY: place\n\n"..
            "place:\n"..
            "\ttar -xzf %s -C '$(BUILD)'\n",
            e2lib.shquote(e2lib.join(srcdir, archive))))
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:cat("build mode %s not supported", source_set)
    end

    -- write licences
    local destdir = e2lib.join(directory, "licences")
    local fname = string.format("%s/%s.licences", destdir, archive)
    local licence_list = src:licences():concat("\n") .. "\n"
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = eio.file_write(fname, licence_list)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

--------------------------------------------------------------------------------

local function gitrepo_plugin_init()
    local rc, re

    rc, re = source.register_source_class("gitrepo", gitrepo_source)
    if not rc then
        return false, re
    end

    for typ, theclass in result.iterate_result_classes() do
        if typ == "collect_project" then
            theclass:add_source_to_result_fn("gitrepo", gitrepo_to_result)
            break
        end
    end

    if e2tool.current_tool() == "fetch-sources" then
        e2option.flag("gitrepo", "select gitrepo sources")
    end

    return true
end

plugin_descriptor = {
    description = "Provides Git repository as source",
    init = gitrepo_plugin_init,
    exit = function(ctx) return true end,
    depends = {
        "collect_project.lua"
    }
}

--------------------------------------------------------------------------------

return strict.lock(gitrepo)

-- vim:sw=4:sts=4:et:
