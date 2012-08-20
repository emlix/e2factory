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

--- git.lua - Git-specific SCM operations -*- Lua -*-
--
-- See e2scm.lua for more information about these operations.

module("git", package.seeall)
local scm = require("scm")
local hash = require("hash")
local cache = require("cache")
local generic_git = require("generic_git")
local url = require("url")
local err = require("err")
local e2option = require("e2option")
local e2lib = require("e2lib")

--- git branch wrapper
-- get the current branch
-- @param gitdir
-- @return string: the branch name, nil on error
-- @return string: nil, or an error string on error
function git_branch_get(gitdir)
  -- git branch
  local cmd = string.format("GIT_DIR=\"%s\" git branch", gitdir)
  local p = io.popen(cmd, "r")
  local branch = nil
  while true do
    local line = p:read()
    if not line then
      break
    end
    local x
    -- search for a line matching '* <branchname>'
    x, branch = line:match("^(\* )(%S*)$")
    if x and branch then
      break
    end
  end
  p:close()
  if not branch then
    return branch, nil, "git branch: can't get current branch"
  end
  return branch, nil
end

--- return a value suitable for buildid computation, i.e. the commit-id
-- @param info the info table
-- @param source string: the source name
-- @param sourceset string: the sourceset
-- @param check_remote bool: in tag mode: make sure the tag is available remote
-- @return string: the commit id, nil on error
-- @return nil on success, an error string on error
function git.get_revision_id(info, source, sourceset, check_remote)
  local sourcename = source
  local rc, re
  local e = err.new("getting revision id failed for source: %s", source)
  local s = info.sources[source]
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
  local p = info.root .. "/" .. s.working .. "/.git/refs/"
  local id, fr, gitdir, ref
  gitdir = string.format("%s/%s/.git", info.root, s.working)
  if sourceset == "branch" or
     (sourceset == "lazytag" and s.tag == "^") then
    ref = string.format("refs/heads/%s", s.branch)
    id, re = generic_git.git_rev_list1(gitdir, ref)
    -- error checking delayed to end of function
  elseif sourceset == "tag" or
         (sourceset == "lazytag" and s.tag ~= "^") then
    gitdir = string.format("%s/%s/.git", info.root, s.working)
    ref = string.format("refs/tags/%s", s.tag)
    id, re = generic_git.git_rev_list1(gitdir, ref)
    -- error checking delayed to end of function
    if id and check_remote then
      e2lib.logf(4, "%s: check for remote tag", s.name)
      rc, re = generic_git.verify_remote_tag(gitdir, s.tag)
      if not rc then
        return false, e:cat(re)
      end
      e2lib.logf(4, "%s: check for remote tag: match", s.name)
    end
  else
    e2lib.abort("not an scm sourceset: " .. sourceset)
  end
  if not id then
    fr = string.format("can't get commit id for ref %s from repository %s",
							ref, s.working)
  end
  return id, not id and fr
end

function git.cache_source(info, sourcename)
  -- noop, return success
  return true, nil
end

--- apply default values where possible and a source configuration is
-- incomplete
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
function source_apply_default_licences(info, sourcename)
  local e = err.new("applying default licences failed.")
  local src = info.sources[ sourcename ]
  if src.licences_default_applied then
    return true
  end
  src.licences_default_applied = true
  if not src.licences and src.licence then
    e2lib.warnf("WDEPRECATED", "in source %s:", src.name)
    e2lib.warnf("WDEPRECATED",
		" licence attribute is deprecated. Replace by licences.")
    src.licences = src.licence
  end
  if not src.licences then
    e2lib.warnf("WDEFAULT", "in source %s:", src.name)
    e2lib.warnf("WDEFAULT",
		" licences attribute missing. Defaulting to empty list.")
    src.licences = {}
  elseif type(src.licences) == "string" then
    e2lib.warnf("WDEPRECATED", "in source %s:", src.name)
    e2lib.warnf("WDEPRECATED",
		" licences attribute is not in table format. Converting.")
    src.licences = { src.licences }
  end
  for i, s in pairs(src.licences) do
    if type(i) ~= "number" or type(s) ~= "string" then
      e:append("licences attribute is not a list of strings")
      return false, e
    end
  end
  for _,l in ipairs(src.licences) do
    if not info.licences[l] then
      e:append("unknown licence: %s", l)
      return false, e
    end
  end
  return true
end

-- XXX generics: Move to some other place
--- validate source configuration
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
function generic_validate_source(info, sourcename)
  local src = info.sources[ sourcename ]
  local rc, re
  local e
  if not src then
    return false, err.new("invalid source: %s", sourcename)
  end
  e = err.new("in source %s:", sourcename)
  rc, re = source_apply_default_licences(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  if not src.type then
    e:append("source has no `type' attribute")
  end
  if src.env and type(src.env) ~= "table" then
    e:append("source has invalid `env' attribute")
  else
    if not src.env then
      e2lib.warnf("WDEFAULT",
	    "source has no `env' attribute. Defaulting to empty dictionary")
      src.env = {}
    end
    src._env = environment.new()
    for k,v in pairs(src.env) do
      if type(k) ~= "string" then
        e:append("in `env' dictionary: key is not a string: %s", tostring(k))
      elseif type(v) ~= "string" then
        e:append("in `env' dictionary: value is not a string: %s", tostring(v))
      else
        src._env:set(k, v)
      end
    end
  end
  if e:getcount() > 1 then
    return false, e
  end
  return true, nil
end

--- do some consistency checks required before using sources
-- @param info
-- @param sourcename string: source name
-- @param require_workingcopy bool: return error if the workingcopy is missing
-- @return bool
-- @return an error object on failure
function check(info, sourcename, require_workingcopy)
  local rc, re
  rc, re = scm.validate_source(info, sourcename)
  if not rc then
    return false, re
  end
  rc, re = scm.working_copy_available(info, sourcename)
  if (not rc) and require_workingcopy then
    return false, err.new("working copy is not available")
  end
  rc, re = scm.check_workingcopy(info, sourcename)
  if not rc then
    return false, re
  end
  return true, nil
end

--- apply default values where possible and a git source configuration is
-- incomplete
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
function source_apply_default_working(info, sourcename)
  local src = info.sources[ sourcename ]
  if src.working_default_applied then
    return true
  end
  src.working_default_applied = true
  local src_working_default = string.format("in/%s", sourcename)
  if src.working and src.working ~= src_working_default then
    e2lib.warnf("WPOLICY", "in source %s:", src.name)
    e2lib.warnf("WPOLICY", " configuring non standard working direcory")
  elseif src.working then
    e2lib.warnf("WHINT", "in source %s:", src.name)
    e2lib.warnf("WHINT", " no need to configure working directory")
  else
    src.working = string.format("in/%s", sourcename)
    e2lib.warnf("WDEFAULT", "in source %s:", src.name)
    e2lib.warnf("WDEFAULT",
	     " `working' attribute missing. Defaulting to '%s'.", src.working)
  end
  return true
end

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on error
function git.validate_source(info, sourcename)
  local rc, re = generic_validate_source(info, sourcename)
  if not rc then
    -- error in generic configuration. Don't try to go on.
    return false, re
  end
  local src = info.sources[ sourcename ]
  local e = err.new("in source %s:", sourcename)
  rc, re = source_apply_default_working(info, sourcename)
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
  if src.server and (not info.cache:valid_server(src.server)) then
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
  local src = info.sources[ sourcename ]
  local rc, re
  local e = err.new("updating source failed")
  rc, re = scm.working_copy_available(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  local gitwc  = string.format("%s/%s", info.root, src.working)
  local gitdir = string.format("%s/%s/.git", info.root, src.working)
  e2lib.logf(2, "updating %s [%s]", src.working, src.branch)
  rc, re = e2tool.lcd(info, src.working)
  if not rc then
    return false, e:append("working copy not available")
  end
  rc, re = e2lib.git(nil, "fetch")  -- git fetch is safe
  if not rc then
    return false, e:cat(re)
  end
  e:append("fetch succeeded")

  -- setup the branch tracking its remote. This fails if the branch exists,
  -- but that's fine.
  local args
  args = string.format("--track '%s' 'origin/%s'", src.branch, src.branch)
  rc, re = e2lib.git(nil, "branch", args)

  -- sanity checks:
  --  must be on configured branch
  local branch, re = git_branch_get(gitdir)
  if not branch then
    return false, e:cat(re)
  end
  if branch ~= src.branch then
    e2lib.warnf("WOTHER", "not on configured branch. Skipping 'git pull'")
    return true, nil
  end
  rc, re = e2tool.lcd(info, src.working)
  if not rc then
    return false, e:append("working copy not available")
  end
  rc, re = e2lib.git(nil, "pull")
  if not rc then
    return false, e:cat(re)
  end
  return true, nil
end

--- fetch a git source
-- @param info the info structure
-- @param sourcename string
-- @return bool
-- @return nil on success, an error string on error
function git.fetch_source(info, sourcename)
  local src = info.sources[ sourcename ]
  local rc, re
  local e = err.new("fetching source failed: %s", sourcename)
  rc, re = git.validate_source(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  local wrk = info.root .. "/" .. src.working
  e2lib.log(2, string.format("cloning %s:%s [%s]",
				src.server, src.location, src.branch))
  local skip_checkout = e2lib.globals.git_skip_checkout
  rc, re = generic_git.git_clone_from_server(info.cache, src.server,
					src.location, wrk, skip_checkout)
  if not rc then
    return false, e:cat(re)
  end
  -- check for the branch, and checkout if it's not yet there after cloning.
  local ref = string.format("refs/heads/%s", src.branch)
  local gitdir = string.format("%s/.git", wrk)
  local rc, re = generic_git.git_rev_list1(gitdir, ref)
  if not rc then
    local track = true
    local start_point = string.format("origin/%s", src.branch)
    local rc, re = generic_git.git_branch_new1(wrk, track, src.branch,
							start_point)
    if not rc then
      return false, e:cat(re)
    end
    local rc, re = generic_git.git_checkout1(wrk, src.branch)
    if not rc then
      return false, e:cat(re)
    end
  end
  return true, nil
end

--- prepare a git source
-- @param info the info structure
-- @param sourcename string
-- @return bool
-- @return nil on success, an error string on error
function git.prepare_source(info, sourcename, sourceset, buildpath)
  local src = info.sources[ sourcename ]
  local rc, re, e
  local e = err.new("preparing git sources failed")
  rc, re = check(info, sourcename, true)
  if not rc then
    return false, e:cat(re)
  end
  local gitdir = info.root .. "/" .. src.working .. "/.git/"
  if sourceset == "branch" or
     (sourceset == "lazytag" and src.tag == "^") then
    local rev, re = git.get_revision_id(info, sourcename, sourceset)
    if not rev then
      return false, e:cat(re)
    end
    gitdir = string.format("%s/%s/.git", info.root, src.working)
    local git = string.format("GIT_DIR=%s "..
      "git archive --format=tar --prefix=%s/ refs/heads/%s",
      e2lib.shquote(gitdir), e2lib.shquote(sourcename),
      e2lib.shquote(src.branch))
    local tar = string.format("tar -C %s -xf -", e2lib.shquote(buildpath))
    local re = e2lib.callcmd_pipe({git, tar})
    if re then
      return false, e:cat(re)
    end
  elseif sourceset == "tag" or
	 (sourceset == "lazytag" and src.tag ~= "^") then
    local rev, re = git.get_revision_id(info, sourcename, sourceset)
    if not rev then
      return false, e:cat(re)
    end
    gitdir = string.format("%s/%s/.git", info.root, src.working)
    local git = string.format("GIT_DIR=%s "..
      "git archive --format=tar --prefix=%s/ refs/tags/%s",
      e2lib.shquote(gitdir), e2lib.shquote(sourcename), e2lib.shquote(src.tag))
    local tar = string.format("tar -C %s -xf -", e2lib.shquote(buildpath))
    local re = e2lib.callcmd_pipe({git, tar})
    if re then
      return false, e:cat(re)
    end
  elseif sourceset == "working-copy" then
    -- warn for empty working-copy
    local working = string.format("%s/%s", info.root, src.working)
    local d = e2util.directory(working, false)
    if #d == 0 then
      e2lib.warnf("WOTHER", "in result: %s", src.name)
      e2lib.warnf("WOTHER", "working copy seems empty")
    end
    local dir = string.format("%s/%s", buildpath, sourcename)
    local rc, re = e2lib.mkdir(dir, "-p")
    if not rc then
      return false, re
    end
    local tar = tools.get_tool("tar")
    local tarflags = tools.get_tool_flags("tar")
    local cmd1 = string.format("%s %s -c -C %s/%s --exclude '.git' .",
      e2lib.shquote(tar), tarflags, e2lib.shquote(info.root),
      e2lib.shquote(src.working))
    local cmd2 = string.format("%s %s -x -C %s/%s", e2lib.shquote(tar),
      tarflags, e2lib.shquote(buildpath), e2lib.shquote(sourcename))
    local r = e2lib.callcmd_pipe({ cmd1, cmd2 })
    if r then e2lib.abort(r) end
  else e2lib.abort("invalid sourceset: ", sourceset)
  end
  return true, nil
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
  local gitwc = info.root .. "/" .. src.working
  local rc = e2lib.isdir(gitwc)
  return rc, nil
end

function git.has_working_copy(info, sname)
  return true
end

function git.tag_available(info, sourcename, tag)
  local src = info.sources[sourcename]
  local rc, e
  rc, e = check(info, sourcename, true)
  if not rc then
    return false, e
  end
  local gitdir = string.format("%s/%s/.git", info.root, src.working)
  local ref = string.format("refs/tags/%s", tag)
  local id, e = generic_git.git_rev_list1(gitdir, ref)
  if not id then
    return false
  end
  return true
end

--- turn server:location into a git-style url
-- @param c table: a cache
-- @param server string: server name
-- @param location string: location
-- @return string: the git url, or nil
-- @return an error object on failure
function git.git_url(c, server, location)
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

function git.git_remote_add(c, lserver, llocation, name, rserver, rlocation)
  e2lib.log(4, string.format("%s, %s, %s, %s, %s, %s",
	tostring(c), tostring(lserver), tostring(llocation),
	tostring(name), tostring(rserver), tostring(rlocation)))
  local rurl, e = cache.remote_url(c, rserver, rlocation)
  if not rurl then
    e2lib.abort(e)
  end
  local lurl, e = cache.remote_url(c, lserver, llocation)
  if not lurl then
    e2lib.abort(e)
  end
  local rc, e = generic_git.git_remote_add1(lurl, rurl, name)
  if not rc then
    e2lib.abort(e)
  end
  return true, nil
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
-- @return string: the sourceid, or nil
-- @return an error string
function git.sourceid(info, sourcename, sourceset)
	local src = info.sources[sourcename]
	local e
	if not src.sourceid then
		src.sourceid = {}
		src.sourceid["working-copy"] = "working-copy"
		src.commitid = {}
	end
	if src.sourceid[sourceset] then
		return true, nil, src.sourceid[sourceset]
	end
	src.commitid[sourceset], e = git.get_revision_id(info, sourcename,
				sourceset, e2option.opts["check-remote"])
	if not src.commitid[sourceset] then
		return false, e
	end
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
	e2lib.log(4, string.format("hash data for source %s\n%s", src.name,
								hc.data))
	src.sourceid[sourceset] = hash.hash_finish(hc)
	return true, nil, src.sourceid[sourceset]
end

function git.toresult(info, sourcename, sourceset, directory)
	local rc, re
	local e = err.new("converting result")
	rc, re = check(info, sourcename, true)
	if not rc then
		return false, e:cat(re)
	end
	local src = info.sources[sourcename]
	local makefile = "makefile"
	local source = "source"
	local sourcedir = string.format("%s/%s", directory, source)
	e2lib.mkdir(sourcedir, "-p")
	local archive = string.format("%s.tar.gz", src.name)
	local cmd = nil
	if sourceset == "tag" or sourceset == "branch" then
		local ref = generic_git.sourceset2ref(sourceset, src.branch, src.tag)
		-- git archive --format=tar <ref> | gzip > <tarball>
		cmd = string.format(
			"cd %s/%s && git archive --format=tar --prefix=%s/ %s"..
			" | gzip > %s/%s",
			e2lib.shquote(info.root), e2lib.shquote(src.working),
			e2lib.shquote(sourcename), e2lib.shquote(ref),
			e2lib.shquote(sourcedir), e2lib.shquote(archive))
	elseif sourceset == "working-copy" or sourceset == "mmm" then
		cmd = string.format("tar -C %s/%s " ..
			"--transform=s,^./,./%s/, "..
			"--exclude=.git "..
			"-czf %s/%s .",
			e2lib.shquote(info.root), e2lib.shquote(src.working),
			e2lib.shquote(sourcename), e2lib.shquote(sourcedir),
			e2lib.shquote(archive))
	else
		return false, e:append("sourceset not supported: %s",
								sourceset)
	end
	local rc, re = e2lib.callcmd_log(cmd)
	if rc ~= 0 then
		return false, e:cat(re)
	end
	local fname  = string.format("%s/%s", directory, makefile)
	local f, msg = io.open(fname, "w")
	if not f then
		return false, e:cat(msg)
	end
	f:write(string.format(
		".PHONY:\tplace\n\n"..
		"place:\n"..
		"\ttar xzf \"%s/%s\" -C \"$(BUILD)\"\n",
		source, archive))
	f:close()
	-- write licences
	local destdir = string.format("%s/licences", directory)
	local fname = string.format("%s/%s.licences", destdir, archive)
	local licence_list = table.concat(src.licences, "\n") .. "\n"
	rc, re = e2lib.mkdir(destdir, "-p")
	if not rc then
			return false, e:cat(re)
	end
	rc, re = e2lib.write_file(fname, licence_list)
	if not rc then
		return false, e:cat(re)
	end
	return true, nil
end

function git.check_workingcopy(info, sourcename)
	local rc, re
	local e = err.new("checking working copy failed")
	e:append("in source %s (git configuration):", sourcename)
	e:setcount(0)
	rc, re = git.validate_source(info, sourcename)
	if not rc then
		return nil, re
	end
	local src = info.sources[sourcename]
	local query, expect, res
	local rc, re = scm.working_copy_available(info, sourcename)
	if not rc then
		e2lib.warnf("WOTHER", "in source %s: ", sourcename)
		e2lib.warnf("WOTHER", " working copy is not available")
		return true, nil
	end
	local gitdir = string.format("%s/%s/.git", info.root, src.working)
	-- check if branch exists
	rc, re = e2tool.lcd(info, src.working)
	if not rc then
		return false, e:cat(re)
	end
	local ref = string.format("refs/heads/%s", src.branch)
	rc, re = generic_git.git_rev_list1(nil, ref)
	if not rc then
		e:append("branch not available: %s", src.branch)
		return false, e:cat(re)
	end
	-- git config branch.<branch>.remote == "origin"
	query = string.format("branch.%s.remote", src.branch)
	expect = string.format("origin")
	res, re = generic_git.git_config(gitdir, query)
	if not res then
		e:append("remote is not configured for branch %s", src.branch)
	elseif res ~= expect then
		e:append("%s is not \"origin\"", query)
	end
	-- git config remote.origin.url == server:location
	query = string.format("remote.origin.url")
	expect, re = git.git_url(info.cache, src.server, src.location)
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
		e:append("%s does not match the configuration", query)
	end
	if e:getcount() > 0 then
		return false, e
	end
	return true, nil
end

scm.register("git", git)
