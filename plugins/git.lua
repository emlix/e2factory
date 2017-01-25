--- Git Plugin
-- @module plugins.git

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

local git = {}
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
local tools = require("tools")
local url = require("url")

git.git_source = class("git_source", source.basic_source)

function git.git_source.static:is_scm_source_class()
    return true
end

function git.git_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)

    if e2tool.current_tool() == "fetch-sources" and opts["git"] then
        return true
    end
    return false
end

function git.git_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and rawsrc.name ~= "")
    assert(type(rawsrc.type) == "string" and rawsrc.type ~= "")

    local rc, re

    source.basic_source.initialize(self, rawsrc)

    self._server = false
    self._location = false
    self._tag = false
    self._branch = false
    self._working = false
    self._sourceids = {
        ["working-copy"] = "working-copy",
    }
    self._commitids = {}

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

function git.git_source:get_server()
    assert(type(self._server) == "string")

    return self._server
end

function git.git_source:get_location()
    assert(type(self._location) == "string")

    return self._location
end

function git.git_source:get_working()
    assert(type(self._working) == "string")

    return self._working
end

function git.git_source:get_branch()
    assert(type(self._branch) == "string")

    return self._branch
end


function git.git_source:get_tag()
    assert(type(self._tag) == "string")

    return self._tag
end

--- Return the git commit ID of the specified source configuration. Specific to
-- sources of type git, useful for writing plugins.
-- @param sourceset string: the sourceset
-- @param check_remote bool: in tag mode: make sure the tag is available remote
-- @return True on success, false on error.
-- @return Error object on failure.
-- @return Commit ID (string) on success.
function git.git_source:git_commit_id(sourceset, check_remote)
    local rc, re, e, id, fr, gitdir, ref

    e = err.new("getting commit ID failed for source: %s", self._name)

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = self:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    gitdir = e2lib.join(e2tool.root(), self:get_working(), ".git")

    if sourceset == "branch" then
        ref = string.format("refs/heads/%s", self:get_branch())

        rc, re, id = generic_git.lookup_id(gitdir, false, ref)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "tag" then
        ref = string.format("refs/tags/%s", self:get_tag())

        rc, re, id = generic_git.lookup_id(gitdir, false, ref)
        if not rc then
            return false, e:cat(re)
        end

        if id and check_remote then
            rc, re = generic_git.verify_remote_tag(gitdir, self:get_tag())
            if not rc then
                return false, e:cat(re)
            end
        end
    else
        return false, err.new("not an scm sourceset: %s", sourceset)
    end

    if not id then
        re = err.new("can't get git commit ID for ref %q from repository %q",
            ref, self:get_working())
        return false, e:cat(re)
    end

    return true, nil, id
end

function git.git_source:sourceid(sourceset)
    assert(type(sourceset) == "string" and #sourceset > 0,
        "sourceset arg invalid")

    local rc, re, id, hc, licences

    if self._sourceids[sourceset] then
        return self._sourceids[sourceset]
    end

    rc, re, id = self:git_commit_id(sourceset, e2option.opts["check-remote"])
    if not rc then
        return false, re
    end

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)
    hash.hash_append(hc, self._env:envid())

    licences = self:get_licences()
    for licencename in licences:iter() do
        local lid, re = licence.licences[licencename]:licenceid()
        if not lid then
            return false, re
        end
        hash.hash_append(hc, lid)
    end

    hash.hash_append(hc, self._server)
    hash.hash_append(hc, self._location)
    hash.hash_append(hc, id)
    self._commitids[sourceset] = id
    self._sourceids[sourceset] = hash.hash_finish(hc)

    return self._sourceids[sourceset]
end

function git.git_source:display()
    local rev_tag, rev_branch, licences

    -- try to calculate the sourceid, but do not care if it fails.
    -- working copy might be unavailable
    self:sourceid("tag")
    self:sourceid("branch")

    rev_tag = ""
    rev_branch = ""
    if self._commitids["tag"] then
        rev_tag = string.format("[%s...]", self._commitids["tag"]:sub(1,8))
    end
    if self._commitids["branch"] then
        rev_branch = string.format("[%s...]", self._commitids["branch"]:sub(1,8))
    end
    local d = {}
    table.insert(d, string.format("type       = %s", self:get_type()))
    table.insert(d, string.format("branch     = %-15s %s", self._branch, rev_branch))
    table.insert(d, string.format("tag        = %-15s %s", self._tag, rev_tag))
    table.insert(d, string.format("server     = %s", self._server))
    table.insert(d, string.format("location   = %s", self._location))
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

--- Check if a working copy for a git repository is available
-- @return True if available, false otherwise.
-- @return Error object if no directory.
function git.git_source:working_copy_available()
    if not e2lib.isdir(e2lib.join(e2tool.root(), self._working)) then
        return false, err.new("working copy for %s is not available", self._name)
    end
    return true
end

function git.git_source:check_workingcopy()

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

function git.git_source:fetch_source()
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
function git.git_source:update_source()
    local e, rc, re, gitwc, gitdir, argv, id, branch, remote

    e = err.new("updating source '%s' failed", self._name)

    rc, re = self:working_copy_available()
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

function git.git_source:prepare_source(sourceset, buildpath)
    local rc, re, e
    local srcdir, destdir

    e = err.new("preparing git source %s failed", self._name)

    rc, re = self:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = self:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    srcdir = e2lib.join(e2tool.root(), self:get_working())
    destdir = e2lib.join(buildpath, self._name)

    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    if sourceset == "working-copy" then
        local empty

        srcdir = e2lib.join(e2tool.root(), self:get_working())

        empty = true
        for f, re in e2lib.directory(srcdir, true) do
            if not f then
                return false, e:cat(re)
            end

            if string.sub(f, 1, 1) ~= "." then
                empty = false
            end

            if f ~= ".git" then
                rc, re = e2lib.cp(e2lib.join(srcdir, f), destdir, true)
                if not rc then
                    return false, e:cat(re)
                end
            end
        end

        if empty then
            e2lib.warnf("WOTHER", "in result: %s", self._name)
            e2lib.warnf("WOTHER", "working copy seems empty")
        end

        return true -- Early exit
    end

    local gitdir, git_argv, git_tool, tar_argv
    local git_pid, tar_pid, fdctv
    local writeend, readend, devnull

    gitdir = e2lib.join(srcdir, ".git")

    rc, re = self:git_commit_id(sourceset)
    if not rc then
        return false, e:cat(re)
    end

    git_argv = generic_git.git_new_argv(gitdir, srcdir, "archive")
    table.insert(git_argv, "--format=tar")

    if sourceset == "branch" then
        table.insert(git_argv, "refs/heads/" .. self:get_branch())
    elseif sourceset == "tag" then
        table.insert(git_argv, "refs/tags/" .. self:get_tag())
    else
        error(err.new("invalid sourceset: %s", sourceset))
    end

    table.insert(git_argv, "--")

    git_tool, re = tools.get_tool("git")
    if not git_tool then
        return false, re
    end

    table.insert(git_argv, 1, git_tool)

    tar_argv, re = tools.get_tool_flags_argv("tar")
    if not tar_argv then
        return false, e:cat(re)
    end

    table.insert(tar_argv, "-x")
    table.insert(tar_argv, "-f")
    table.insert(tar_argv, "-")
    table.insert(tar_argv, "-C")
    table.insert(tar_argv, destdir)

    readend, writeend = eio.pipe()
    if not readend then
        return false, e:cat(writeend)
    end

    devnull, re = eio.fopen("/dev/null", "rw")
    if not devnull then
        return false, re
    end

    fdctv = {
        { istype = "readfo", dup = eio.STDIN, file = devnull },
        { istype = "readfo", dup = eio.STDOUT, file = writeend }
    }

    git_pid, re = e2lib.callcmd(git_argv, fdctv, nil, nil, true)
    if not git_pid then
        return false, e:cat(re)
    end

    fdctv = {
        { istype = "readfo", dup = eio.STDIN, file = readend },
        { istype = "readfo", dup = eio.STDOUT, file = devnull }
    }

    tar_pid, re = e2lib.callcmd(tar_argv, fdctv, nil, nil, true)
    if not tar_pid then
        return false, e:cat(re)
    end

    rc, re = e2lib.wait(git_pid)
    if not rc then
        return false, e:cat(re)
    elseif rc ~= 0 then
        return false, e:cat("git archive failed with return code %d", rc)
    end

    rc, re = eio.close(writeend)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = e2lib.wait(tar_pid)
    if not rc then
        return false, e:cat(re)
    elseif rc ~= 0 then
        return false, e:cat("git archive - tar failed with return code %d", rc)
    end

    rc, re = eio.close(readend)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = eio.fclose(devnull)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--------------------------------------------------------------------------------

local function git_to_result(src, sourceset, directory)
    local rc, re, argv
    local e = err.new("converting %s to result", src:get_name())

    rc, re = src:working_copy_available()
    if not rc then
        return false, e:cat(re)
    end

    rc, re = src:check_workingcopy()
    if not rc then
        return false, e:cat(re)
    end

    local makefile = "Makefile"
    local source = "source"
    local sourcedir = e2lib.join(directory, source)
    local archive = string.format("%s.tar.gz", src:get_name())
    local cmd = nil

    rc, re = e2lib.mkdir_recursive(sourcedir)
    if not rc then
        return false, e:cat(re)
    end

    if sourceset == "tag" or sourceset == "branch" then
        local ref, tmpfn

        ref, re = generic_git.sourceset2ref(sourceset, src:get_branch(), src:get_tag())
        if not ref then
            return false, e:cat(re)
        end

        tmpfn, re = e2lib.mktempfile()
        if not tmpfn then
            return false, e:cat(re)
        end

        argv = generic_git.git_new_argv(nil, e2lib.join(e2tool.root(), src:get_working()))
        table.insert(argv, "archive")
        table.insert(argv, "--format=tar") -- older versions don't have "tar.gz"
        table.insert(argv, string.format("--prefix=%s/", src:get_name()))
        table.insert(argv, "-o")
        table.insert(argv, tmpfn)
        table.insert(argv, ref)

        rc, re = generic_git.git(argv)
        if not rc then
            return false, e:cat(re)
        end

        rc, re = e2lib.gzip({ "-n", tmpfn })
        if not rc then
            return false, re
        end

        rc, re = e2lib.mv(tmpfn..".gz", e2lib.join(sourcedir, archive))
        if not rc then
            return false, re
        end
    elseif sourceset == "working-copy" then
        argv = {
            "-C", e2lib.join(e2tool.root(), src:get_working()),
            string.format("--transform=s,^./,./%s/,", src:get_name()),
            "--exclude=.git",
            "-czf",
            e2lib.join(sourcedir, archive),
            "."
        }

        rc, re = e2lib.tar(argv)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:append("sourceset not supported: %s",
        sourceset)
    end
    local fname  = e2lib.join(directory, makefile)
    local out = string.format(
        ".PHONY:\tplace\n\n"..
        "place:\n"..
        "\ttar xzf \"%s/%s\" -C \"$(BUILD)\"\n", source, archive)
    rc, re = eio.file_write(fname, out)
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
    return true, nil
end

--------------------------------------------------------------------------------

--- Initialize git plugin.
-- @param ctx Plugin context. See plugin module.
-- @return True on success, false on error.
-- @return Error object on failure.
local function git_plugin_init(ctx)
    local rc, re

    rc, re = source.register_source_class("git", git.git_source)
    if not rc then
        return false, re
    end

    for typ, theclass in result.iterate_result_classes() do
        if typ == "collect_project" then
            theclass:add_source_to_result_fn("git", git_to_result)
            break
        end
    end

    if e2tool.current_tool() == "fetch-sources" then
        e2option.flag("git", "select git sources")
    end

    return true
end

plugin_descriptor = {
    description = "Git SCM Plugin",
    init = git_plugin_init,
    exit = function (ctx) return true end,
    depends = {
        "collect_project.lua"
    }
}


strict.lock(git)

-- vim:sw=4:sts=4:et:
