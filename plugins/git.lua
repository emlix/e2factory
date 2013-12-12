--- Git Plugin
-- @module plugins.git

--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2007-2009 Gordon Hecker <gh@emlix.com>, emlix GmbH
   Copyright (C) 2007-2009 Oskar Schirmer <os@emlix.com>, emlix GmbH
   Copyright (C) 2007-2008 Felix Winkelmann, emlix GmbH

   For more information have a look at http://www.e2factory.org

   e2factory is a registered trademark by emlix GmbH.

   This file is part of e2factory, the emlix embedded build system.

   e2factory is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

local git = {}
local cache = require("cache")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local generic_git = require("generic_git")
local hash = require("hash")
local scm = require("scm")
local strict = require("strict")
local tools = require("tools")
local url = require("url")

--- Initialize git plugin.
-- @param ctx Plugin context. See plugin module.
-- @return True on succes, false on error.
-- @return Error object on failure.
local function git_plugin_init(ctx)
    local rc, re

    rc, re = scm.register("git", git)
    if not rc then
        return false, re
    end

    -- Additional interfaces only available with git sources.
    rc, re = scm.register_interface("git_commit_id")
    if not rc then
        return false, re
    end

    rc, re = scm.register_function("git", "git_commit_id", git.git_commit_id)
    if not rc then
        return false, re
    end

    return true
end

plugin_descriptor = {
    description = "Git SCM Plugin",
    init = git_plugin_init,
    exit = function (ctx) return true end,
}

--- Return the git commit ID of the specified source configuration. Specific to
-- sources of type git, useful for writing plugins.
-- @param info Info table.
-- @param sourcename Source name.
-- @param sourceset string: the sourceset
-- @param check_remote bool: in tag mode: make sure the tag is available remote
-- @return True on success, false on error.
-- @return Error object on failure.
-- @return Commit ID (string) on success.
function git.git_commit_id(info, sourcename, sourceset, check_remote)
    local rc, re, e, src, id, fr, gitdir, ref

    e = err.new("getting commit ID failed for source: %s", sourcename)
    src = info.sources[sourcename]

    rc, re = git.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = scm.working_copy_available(info, sourcename)
    if not rc then
        return false, e:append("working copy is not available")
    end

    rc, re = scm.check_workingcopy(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end

    gitdir = e2lib.join(info.root, src.working, ".git")

    if sourceset == "branch" or (sourceset == "lazytag" and src.tag == "^") then
        ref = string.format("refs/heads/%s", src.branch)

        rc, re, id = generic_git.lookup_id(gitdir, false, ref)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "tag" or (sourceset == "lazytag" and src.tag ~= "^") then
        ref = string.format("refs/tags/%s", src.tag)

        rc, re, id = generic_git.lookup_id(gitdir, false, ref)
        if not rc then
            return false, e:cat(re)
        end

        if id and check_remote then
            rc, re = generic_git.verify_remote_tag(gitdir, src.tag)
            if not rc then
                return false, e:cat(re)
            end
        end
    else
        return false, err.new("not an scm sourceset: %s", sourceset)
    end

    if not id then
        re = err.new("can't get git commit ID for ref %q from repository %q",
            ref, src.working)
        return false, e:cat(re)
    end

    return true, nil, id
end

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on error
function git.validate_source(info, sourcename)
    local rc, re = scm.generic_source_validate(info, sourcename)
    if not rc then
        -- error in generic configuration. Don't try to go on.
        return false, re
    end
    local src = info.sources[ sourcename ]
    local e = err.new("in source %s:", sourcename)
    rc, re = scm.generic_source_default_working(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    e:setcount(0)
    -- catch deprecated attributes
    if src.remote then
        e:append("source has deprecated `remote' attribute")
    end
    if not src.server then
        e:append("source has no `server' attribute")
    end
    if src.server and (not cache.valid_server(info.cache, src.server)) then
        e:append("invalid server: %s", src.server)
    end
    if not src.licences then
        e:append("source has no `licences' attribute")
    end
    if not src.branch then
        e:append("source has no `branch' attribute")
    end
    if type(src.tag) ~= "string" then
        e:append("source has no `tag' attribute or tag attribute has wrong type")
    end
    if not src.location then
        e:append("source has no `location' attribute")
    end
    if not src.working then
        e:append("source has no `working' attribute")
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true, nil
end

--- update a working copy
-- @param info the info structure
-- @param sourcename string
-- @return bool
-- @return an error object
function git.update(info, sourcename)
    local e, rc, re, src, gitwc, gitdir, argv, id, branch, remote

    src = info.sources[sourcename]
    e = err.new("updating source '%s' failed", sourcename)

    rc, re = scm.working_copy_available(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end

    e2lib.logf(2, "updating %s [%s]", src.working, src.branch)

    gitwc  = e2lib.join(info.root, src.working)
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

    if branch ~= "refs/heads/" .. src.branch then
        e2lib.warnf("WOTHER", "not on configured branch. Skipping.")
        return true
    end

    rc, re, remote = generic_git.git_config(
        gitdir, "branch."..src.branch.."remote")
    if not rc or string.len(remote) == 0  then
        e2lib.warnf("WOTHER", "no remote configured for branch %q. Skipping.",
            src.branch)
        return true
    end

    branch = remote .. "/" .. src.branch
    argv = generic_git.git_new_argv(gitdir, gitwc, "merge", "--ff-only", branch)
    rc, re = generic_git.git(argv)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- fetch a git source
-- @param info the info structure
-- @param sourcename string
-- @return bool
-- @return nil on success, an error string on error
function git.fetch_source(info, sourcename)
    local e, rc, re, src, git_dir, work_tree, id

    src = info.sources[sourcename]
    e = err.new("fetching source failed: %s", sourcename)

    rc, re = git.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end

    work_tree = e2lib.join(info.root, src.working)
    git_dir = e2lib.join(work_tree, ".git")

    e2lib.logf(2, "cloning %s:%s [%s]", src.server, src.location, src.branch)

    rc, re = generic_git.git_clone_from_server(info.cache, src.server,
        src.location, work_tree, false --[[always checkout]])
    if not rc then
        return false, e:cat(re)
    end

    rc, re, id = generic_git.lookup_id(git_dir, false,
        "refs/heads/" .. src.branch)
    if not rc then
        return false, e:cat(re)
    elseif not id then
        rc, re = generic_git.git_branch_new1(work_tree, true, src.branch,
            "origin/" .. src.branch)
        if not rc then
            return false, e:cat(re)
        end

        rc, re = generic_git.git_checkout1(work_tree,
            "refs/heads/" .. src.branch)
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- prepare a git source
-- @param info the info structure
-- @param sourcename string
-- @param sourceset
-- @param buildpath
-- @return bool
-- @return nil on success, an error string on error
function git.prepare_source(info, sourcename, sourceset, buildpath)
    local src = info.sources[ sourcename ]
    local rc, re, e
    local e = err.new("preparing git sources failed")
    rc, re = scm.generic_source_check(info, sourcename, true)
    if not rc then
        return false, e:cat(re)
    end
    local gitdir = e2lib.join(info.root, src.working, ".git")
    if sourceset == "branch" or
        (sourceset == "lazytag" and src.tag == "^") then
        local argv, work_tree

        rc, re = git.git_commit_id(info, sourcename, sourceset)
        if not rc then
            return false, e:cat(re)
        end

        work_tree = e2lib.join(buildpath, sourcename)
        rc, re = e2lib.mkdir_recursive(work_tree)
        if not rc then
            return e:cat(re)
        end

        argv = generic_git.git_new_argv(gitdir, work_tree, "checkout")
        table.insert(argv, "refs/heads/" .. src.branch)
        table.insert(argv, "--")

        rc, re = generic_git.git(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "tag" or
        (sourceset == "lazytag" and src.tag ~= "^") then
        local argv, work_tree

        rc, re = git.git_commit_id(info, sourcename, sourceset)
        if not rc then
            return false, e:cat(re)
        end

        work_tree = e2lib.join(buildpath, sourcename)
        rc, re = e2lib.mkdir_recursive(work_tree)
        if not rc then
            return e:cat(re)
        end

        argv = generic_git.git_new_argv(gitdir, work_tree, "checkout")
        table.insert(argv, "refs/tags/" .. src.tag)
        table.insert(argv, "--")

        rc, re = generic_git.git(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif sourceset == "working-copy" then
        local working, destdir, empty

        working = e2lib.join(info.root, src.working)
        destdir = e2lib.join(buildpath, sourcename)

        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        empty = true
        for f, re in e2lib.directory(working, true) do
            if not f then
                return false, e:cat(re)
            end

            if string.sub(f, 1, 1) ~= "." then
                empty = false
            end

            if f ~= ".git" then
                rc, re = e2lib.cp(e2lib.join(working, f), destdir, true)
                if not rc then
                    return false, e:cat(re)
                end
            end
        end

        if empty then
            e2lib.warnf("WOTHER", "in result: %s", src.name)
            e2lib.warnf("WOTHER", "working copy seems empty")
        end
    else
        return false, err.new("invalid sourceset: %s", sourceset)
    end

    return true
end

--- check if a working copy for a git repository is available
-- @param info the info structure
-- @param sourcename string
-- @return bool
-- @return sometimes an error string, when ret. false. XXX interface cleanup.
function git.working_copy_available(info, sourcename)
    local src = info.sources[sourcename]
    local rc, re
    local e = err.new("checking if working copy is available for source %s",
    sourcename)
    rc, re = git.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    local gitwc = e2lib.join(info.root, src.working)
    local rc = e2lib.isdir(gitwc)
    return rc, nil
end

function git.has_working_copy(info, sname)
    return true
end

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

--- create a table of lines for display
-- @param info the info structure
-- @param sourcename string
-- @return a table, nil on error
-- @return an error string on failure
function git.display(info, sourcename)
    local src = info.sources[sourcename]
    local rc, re
    local e = err.new("display source information failed")
    rc, re = git.validate_source(info, sourcename)
    if not rc then
        return nil, e:cat(re)
    end
    -- try to calculte the sourceid, but do not care if it fails.
    -- working copy might be unavailable
    scm.sourceid(info, sourcename, "tag")
    scm.sourceid(info, sourcename, "branch")
    local rev_tag = ""
    local rev_branch = ""
    if src.commitid["tag"] then
        rev_tag = string.format("[%s...]", src.commitid["tag"]:sub(1,8))
    end
    if src.commitid["branch"] then
        rev_branch = string.format("[%s...]", src.commitid["branch"]:sub(1,8))
    end
    local display = {}
    display[1] = string.format("type       = %s", src.type)
    display[2] = string.format("branch     = %-15s %s", src.branch, rev_branch)
    display[3] = string.format("tag        = %-15s %s", src.tag, rev_tag)
    display[4] = string.format("server     = %s", src.server)
    display[5] = string.format("location   = %s", src.location)
    display[6] = string.format("working    = %s", src.working)
    local i = 8
    for _,l in ipairs(src.licences) do
        display[i] = string.format("licence    = %s", l)
        i = i + 1
    end
    for _,sourceset in pairs({"tag", "branch"}) do
        if src.sourceid and src.sourceid[sourceset] then
            local id = src.sourceid[sourceset]
            local s = string.format("sourceid[%s]", sourceset)
            display[i] = string.format("%-11s= %s", s, id)
            i = i + 1
        end
    end
    i = i + 1
    return display
end

--- calculate an id for a source
-- @param info
-- @param sourcename
-- @param sourceset
-- @return string: the sourceid, or nil
-- @return an error string
function git.sourceid(info, sourcename, sourceset)
    local src = info.sources[sourcename]
    local rc, re, e, id
    if not src.sourceid then
        src.sourceid = {}
        src.sourceid["working-copy"] = "working-copy"
        src.commitid = {}
    end
    if src.sourceid[sourceset] then
        return true, nil, src.sourceid[sourceset]
    end

    rc, re, id = git.git_commit_id(info, sourcename, sourceset,
        e2option.opts["check-remote"])
    if not rc then
        return false, re
    end

    src.commitid[sourceset] = id
    local hc = hash.hash_start()
    hash.hash_line(hc, src.name)
    hash.hash_line(hc, src.type)
    hash.hash_line(hc, src._env:id())
    for _,l in ipairs(src.licences) do
        hash.hash_line(hc, l)
        local licenceid, re = e2tool.licenceid(info, l)
        if not licenceid then
            return false, re
        end
        hash.hash_line(hc, licenceid)
    end
    -- git specific
    --hash.hash_line(hc, src.branch)
    --hash.hash_line(hc, src.tag)
    hash.hash_line(hc, src.server)
    hash.hash_line(hc, src.location)
    hash.hash_line(hc, src.working)
    hash.hash_line(hc, src.commitid[sourceset])
    src.sourceid[sourceset] = hash.hash_finish(hc)
    return true, nil, src.sourceid[sourceset]
end

function git.toresult(info, sourcename, sourceset, directory)
    local rc, re, argv
    local e = err.new("converting result")
    rc, re = scm.generic_source_check(info, sourcename, true)
    if not rc then
        return false, e:cat(re)
    end
    local src = info.sources[sourcename]
    local makefile = "Makefile"
    local source = "source"
    local sourcedir = e2lib.join(directory, source)
    local archive = string.format("%s.tar.gz", src.name)
    local cmd = nil

    rc, re = e2lib.mkdir_recursive(sourcedir)
    if not rc then
        return false, e:cat(re)
    end

    if sourceset == "tag" or sourceset == "branch" then
        local ref, tmpfn

        ref, re = generic_git.sourceset2ref(sourceset, src.branch, src.tag)
        if not ref then
            return false, e:cat(re)
        end

        tmpfn, re = e2lib.mktempfile()
        if not tmpfn then
            return false, e:cat(re)
        end

        argv = generic_git.git_new_argv(nil, e2lib.join(info.root, src.working))
        table.insert(argv, "archive")
        table.insert(argv, "--format=tar") -- older versions don't have "tar.gz"
        table.insert(argv, string.format("--prefix=%s/", sourcename))
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
            "-C", e2lib.join(info.root, src.working),
            string.format("--transform=s,^./,./%s/,", sourcename),
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
    local licence_list = table.concat(src.licences, "\n") .. "\n"
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

function git.check_workingcopy(info, sourcename)
    local rc, re
    local e = err.new("checking working copy of source %s failed", sourcename)

    rc, re = git.validate_source(info, sourcename)
    if not rc then
        return false, re
    end

    rc, re = scm.working_copy_available(info, sourcename)
    if not rc then
        e2lib.warnf("WOTHER", "in source %s: ", sourcename)
        e2lib.warnf("WOTHER", " working copy is not available")
        return true, nil
    end

    -- check if branch exists
    local src = info.sources[sourcename]
    local gitdir = e2lib.join(info.root, src.working, ".git")
    local ref = string.format("refs/heads/%s", src.branch)
    local id

    rc, re, id = generic_git.lookup_id(gitdir, false, ref)
    if not rc then
        return false, e:cat(re)
    elseif not id then
        return false, e:cat(err.new("branch %q does not exist", src.branch))
    end

    -- git config branch.<branch>.remote == "origin"
    local query, expect, res
    query = string.format("branch.%s.remote", src.branch)
    res, re = generic_git.git_config(gitdir, query)
    if not res then
        e:append("remote is not configured for branch \"%s\"", src.branch)
        return false, e
    elseif res ~= "origin" then
        e:append("%s is not \"origin\"", query)
        return false, e
    end

    -- git config remote.origin.url == server:location
    query = string.format("remote.origin.url")
    expect, re = git_url(info.cache, src.server, src.location)
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

strict.lock(git)

-- vim:sw=4:sts=4:et:
