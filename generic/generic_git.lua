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

--- functions with '1' postfix take url strings as parameter. the others
-- take server / location

module("generic_git", package.seeall)

--- clone a git repository
-- @param surl url to the server
-- @param location location relative to the server url
-- @param skip_checkout bool: pass -n to git clone?
-- @return true on success, false on error
-- @return nil, an error object on failure
function git_clone_url1(surl, location, destdir, skip_checkout)
  if (not surl) or (not location) or (not destdir) then
    e2lib.abort("git_clone2(): missing parameter")
  end
  local rc, re
  local e = new_error("cloning git repository")
  local full_url = string.format("%s/%s", surl, location)
  local u, re = url.parse(full_url)
  if not u then
    return false, e:cat(re)
  end
  local src, re = git_url1(u)
  if not src then
    return false, e:cat(re)
  end
  local flags = ""
  if skip_checkout then
    flags = "-n"
  end
  local cmd = string.format("git clone %s --quiet %s %s", flags, src, destdir)
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    return false, e:cat(re)
  end
  return true, nil
end

--- git branch wrapper
-- @param gitwc string: path to the git repository
-- @param track bool: use --track or --no-track
-- @param branch string: name of the branch to create
-- @param start_point string: where to start the branch
-- @return bool
-- @return nil, an error object on failure
function git_branch_new1(gitwc, track, branch, start_point)
  -- git branch [--track|--no-track] <branch> <start_point>
  local f_track = nil
  if track == true then
    f_track = "--track"
  else
    f_track = "--no-track"
  end
  local cmd = string.format(
	"cd \"%s\" && git branch %s \"%s\" \"%s\"",
	gitwc, f_track, branch, start_point)
  local rc = e2lib.callcmd_capture(cmd)
  if rc ~= 0 then
    return false, new_error("creating new branch failed")
  end
  return true, nil
end

--- git checkout wrapper
-- @param gitwc string: path to the git repository
-- @param branch name of the branch to checkout
-- @return bool
-- @return an error object on failure
function git_checkout1(gitwc, branch)
  e2lib.log(3, string.format("checking out branch: %s", branch))
  -- git checkout <branch>
  local cmd = string.format(
	"cd %s && git checkout \"%s\"",
	gitwc, branch)
  local rc = e2lib.callcmd_capture(cmd)
  if rc ~= 0 then
    return false, new_error("git checkout failed")
  end
  return true, nil
end

--- git rev-list wrapper function
-- @param gitdir string: GIT_DIR
-- @param ref string: a reference, according to the git manual
-- @return string: the commit id matching the ref parameter, or nil on error
-- @return an error object on failure
function git_rev_list1(gitdir, ref)
  e2lib.log(4, string.format("git_rev_list(): %s %s",
					tostring(gitdir), tostring(ref)))
  local e = new_error("git rev-list failed")
  local rc, re
  local tmpfile = e2lib.mktempfile()
  local args = string.format("--max-count=1 '%s' -- >'%s'", ref, tmpfile)
  rc, re = e2lib.git(gitdir, "rev-list", args)
  if not rc then
    return false, e -- do not include the low-level error here
  end
  local f, msg = io.open(tmpfile, "r")
  if not f then
    return nil, e:cat(msg)
  end
  local rev = f:read()
  f:close()
  e2lib.rmtempfile(tmpfile)
  if (not rev) or (not rev:match("^%S+$")) then
    return nil, new_error("can't parse git rev-list output")
  end
  if rev then
    e2lib.log(4, string.format("git_rev_list: %s", rev))
  else
    e2lib.log(4, string.format("git_rev_list: unknown ref: %s", ref))
  end
  return rev, nil
end

--- initialize a git repository
-- @param rurl string: remote url
-- @return bool
-- @return an error object on failure
function git_init_db1(rurl)
  if (not rurl) then
    e2lib.abort("git_init_db1(): missing parameter")
  end
  local e = new_error("running git_init_db")
  local rc, re
  local u, re = url.parse(rurl)
  if not u then
    return false, e:cat(re)
  end
  local rc = false
  local cmd = nil
  local gitdir = string.format("/%s", u.path)
  local gitcmd = string.format(
		"mkdir -p \"%s\" && GIT_DIR=\"%s\" git init-db --shared", 								gitdir, gitdir)
  if u.transport == "ssh" or u.transport == "scp" or
     u.transport == "rsync+ssh" then
    local ssh = tools.get_tool("ssh")
    cmd = string.format("%s '%s' '%s'", ssh, u.server, gitcmd)
  elseif u.transport == "file" then
    cmd = gitcmd
  else
    return false, e:append("transport not supported: %s", u.transport)
  end
  rc = e2lib.callcmd_capture(cmd)
  if rc ~= 0 then
    return false, e:append("error running git init-db")
  end
  return true, nil
end

--- do a git push
-- @param gitdir string: absolute path to a gitdir
-- @param rurl string: remote url
-- @param refspec string: a git refspec
-- @return bool
-- @return an error object on failure
function git_push1(gitdir, rurl, refspec)
  if (not rurl) or (not gitdir) or (not refspec) then
    e2lib.abort("git_push1(): missing parameter")
  end
  local rc, re
  local e = new_error("git push failed")
  local u, re = url.parse(rurl)
  if not u then
    return false, e:cat(re)
  end
  local remote_git_url, re = git_url1(u)
  if not remote_git_url then
    return false, e:cat(re)
  end
  -- GIT_DIR=gitdir git push remote_git_url refspec
  local cmd = string.format("GIT_DIR=\"%s\" git push \"%s\" \"%s\"",
		gitdir, remote_git_url, refspec)
  local rc = e2lib.callcmd_capture(cmd)
  if rc ~= 0 then
    return false, e
  end
  return true, nil
end

--- do a git remote-add
-- @param lurl string: local git repo
-- @param rurl string: remote url
-- @param name string: remote name
-- @return bool
-- @return an error object on failure
function git_remote_add1(lurl, rurl, name)
  if (not lurl) or (not rurl) or (not name) then
    e2lib.abort("missing parameter")
  end
  local rc, re
  local e = new_error("git remote-add failed")
  local lrepo, re = url.parse(lurl)
  if not lrepo then
    return false, e:cat(re)
  end
  local rrepo, re = url.parse(rurl)
  if not rrepo then
    return false, e:cat(re)
  end
  local giturl, re = git_url1(rrepo)
  if not giturl then
    return false, e:cat(re)
  end
  -- git remote add <name> <giturl>
  local cmd = string.format(
	"cd \"/%s\" && git remote add \"%s\" \"%s\"", lrepo.path, name, giturl)
  local rc = e2lib.callcmd_capture(cmd)
  if rc ~= 0 then
    return false, e
  end
  return true, nil
end

--- translate a url to a git url
-- @param u url table
-- @return string: the git url
-- @return an error object on failure
function git_url1(u)
  e2lib.log(4, string.format("git_url(%s)", tostring(u)))
  local giturl
  if u.transport == "ssh" or u.transport == "scp" or
     u.transport == "rsync+ssh" then
    giturl = string.format("git+ssh://%s/%s", u.server, u.path)
  elseif u.transport == "file" then
    giturl = string.format("/%s", u.path)
  else
    return nil, new_error("transport not supported: %s", u.transport)
  end
  return giturl, nil
end

--- clone a git repository by server and location
-- @param cache
-- @param server
-- @param location
-- @param destdir string: destination directory
-- @param skip_checkout bool: pass -n to git clone?
-- @return bool
-- @return an error object on failure
function git_clone_from_server(c, server, location, destdir,
								skip_checkout)
  local rc, re
  local e = new_error("cloning git repository")
  local surl, re = cache.remote_url(c, server, location)
  if not surl then
    return false, e:cat(re)
  end
  local rc, re = git_clone_url1(surl, "", destdir, skip_checkout)
  if not rc then
    return false, re
  end
  return true, nil
end

--- initialize a git repository
-- @param c a cache
-- @param server string: server name
-- @param location string: location
-- @return bool
-- @return an error object on failure
function git_init_db(c, server, location)
  local rc, re
  local e = new_error("initializing git repository")
  local rurl, re = cache.remote_url(c, server, location)
  if not rurl then
    return false, e:cat(re)
  end
  local rc, re = git_init_db1(rurl)
  if not rc then
    return false, re
  end
  return true, nil
end

--- do a git push
-- @param c a cache
-- @param gitdir string: gitdir
-- @param server string: server name
-- @param location string: location
-- @param refspec string: a git refspec
-- @return bool
-- @return an error object on failure
function git_push(c, gitdir, server, location, refspec)
  local rc, re
  local e = new_error("git push failed")
  local rurl, re = cache.remote_url(c, server, location)
  if not rurl then
    return false, e:cat(re)
  end
  return git_push1(gitdir, rurl, refspec)
end

--- do a git config query
-- @param gitdir string: gitdir
-- @param query string: query to pass to git config
-- @return string: the value printed to stdout by git config, or nil
-- @return an error object on failure
function git_config(gitdir, query)
  local rc, re
  local e = new_error("running git config")
  local tmpfile = e2lib.mktempfile()
  local cmd = string.format("GIT_DIR=\"%s\" git config \"%s\" > %s",
							gitdir, query, tmpfile)
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    e:append("git config failed")
    return nil, e
  end
  local git_output = e2lib.read_line(tmpfile)
  if not git_output then
    return nil, e:append("can't read git output from temporary file")
  end
  e2lib.rmtempfile(tmpfile)
  return git_output, nil
end

--- do a git add
-- @param gitdir string: gitdir (optional, default: .git)
-- @param args string: args to pass to git add
-- @return bool
-- @return an error object on failure
function git_add(gitdir, args)
  local rc, re
  local e = new_error("running git add")
  if not gitdir then
	gitdir = ".git"
  end
  local cmd = string.format("GIT_DIR=\"%s\" git add '%s'",
							gitdir, args)
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    return nil, e:cat(re)
  end
  return true, nil
end

--- do a git commit
-- @param gitdir string: gitdir (optional, default: .git)
-- @param args string: args to pass to git add
-- @return bool
-- @return an error object on failure
function git_commit(gitdir, args)
  local rc, re
  local e = new_error("git commit failed")
  return e2lib.git("commit", gitdir, args)
end

--- compare a local tag and the remote tag with the same name
-- @param gitdir string: gitdir (optional, default: .git)
-- @param tag string: tag name
-- @return bool, or nil on error
-- @return an error object on failure
function verify_remote_tag(gitdir, tag)
  e2lib.logf(4, "generic_git.verify_remote_tag(%s, %s)", tostring(gitdir),
							tostring(tag))
  local e = new_error("verifying remote tag")
  local rc, re

  -- fetch the remote tag
  local rtag = string.format("%s.remote", tag)
  local args = string.format("origin refs/tags/%s:refs/tags/%s",
								tag, rtag)
  rc, re = e2lib.git(gitdir, "fetch", args)
  if not rc then
    return false, new_error("remote tag is not available: %s", tag)
  end

  -- store commit ids for use in the error message, if any
  local lrev = git_rev_list1(gitdir, tag)
  if not lrev then
    return nil, e:cat(re)
  end
  local rrev = git_rev_list1(gitdir, rtag)
  if not rrev then
    return nil, e:cat(re)
  end

  -- check that local and remote tags point to the same revision
  local args = string.format("--quiet '%s' '%s'", rtag, tag)
  local equal, re = e2lib.git(gitdir, "diff", args)

  -- delete the remote tag again, before evaluating the return code
  -- of 'git diff'
  local args = string.format("-d '%s'", rtag)
  rc, re = e2lib.git(gitdir, "tag", args)
  if not rc then
    return nil, e:cat(re)
  end
  if not equal then
    return false, e:append(
      "local tag differs from remote tag\n"..
      "tag name: %s\n"..
      "local:  %s\n"..
      "remote: %s\n", tag, lrev, rrev)
  end
  return true, nil
end

--- verify that the working copy is clean and matches HEAD
-- @param gitwc string: path to a git working tree (default: .)
-- @return bool, or nil on error
-- @return an error object on failure
function verify_clean_repository(gitwc)
  e2lib.logf(4, "generic_git.verify_clean_repository(%s)", tostring(gitwc))
  gitwc = gitwc or "."
  local e = new_error("verifying that repository is clean")
  local rc, re
  local tmp = e2lib.mktempfile()
  rc, re = e2lib.chdir(gitwc)
  if not rc then
    return nil, e:cat(re)
  end
  -- check for unknown files in the filesystem
  local args = string.format(
			"--exclude-standard --directory --others >%s", tmp)
  rc, re = e2lib.git(nil, "ls-files", args)
  if not rc then
    return nil, e:cat(re)
  end
  local x, msg = io.open(tmp, "r")
  if not x then
    return nil, e:cat(msg)
  end
  local files = x:read("*a")
  x:close()
  if #files > 0 then
    local msg = "the following files are not checked into the repository:\n"
    msg = msg .. files
    return false, new_error("%s", msg)
  end
  -- verify that the working copy matches HEAD
  local args = string.format("--name-only HEAD >%s", tmp)
  rc, re = e2lib.git(nil, "diff-index", args)
  if not rc then
    return nil, e:cat(re)
  end
  local x, msg = io.open(tmp, "r")
  if not x then
    return nil, e:cat(msg)
  end
  local files = x:read("*a")
  x:close()
  if #files > 0 then
    msg = "the following files are modified:\n"
    msg = msg..files
    return false, new_error("%s", msg)
  end
  -- verify that the index matches HEAD
  local args = string.format("--name-only --cached HEAD >%s", tmp)
  rc, re = e2lib.git(nil, "diff-index", args)
  if not rc then
    return nil, e:cat(re)
  end
  local x, msg = io.open(tmp, "r")
  if not x then
    return nil, e:cat(msg)
  end
  local files = x:read("*a")
  x:close()
  if #files > 0 then
    msg = "the following files in index are modified:\n"
    msg = msg..files
    return false, new_error("%s", msg)
  end
  return true
end

--- verify that HEAD matches the given tag
-- @param gitdir string: gitdir (optional, default: .git)
-- @param tag string: tag name
-- @return bool, or nil on error
-- @return an error object on failure
function verify_head_match_tag(gitwc, verify_tag)
  e2lib.logf(4, "generic_git.verify_head_match_tag(%s, %s)", tostring(gitwc),
							tostring(verify_tag))
  assert(verify_tag)
  gitwc = gitwc or "."
  local e = new_error("verifying that HEAD matches 'refs/tags/%s'", verify_tag)
  local rc, re
  local tmp = e2lib.mktempfile()
  local args = string.format("--tags --match '%s' >%s", verify_tag, tmp)
  rc, re = e2lib.chdir(gitwc)
  if not rc then
    return nil, e:cat(re)
  end
  rc, re = e2lib.git(nil, "describe", args)
  if not rc then
    return nil, e:cat(re)
  end
  local x, msg = io.open(tmp, "r")
  if not x then
    return nil, e:cat(msg)
  end
  local tag, msg = x:read()
  x:close()
  if tag == nil then
    return nil, e:cat(msg)
  end
  if tag ~= verify_tag then
    return false
  end
  return true
end

function sourceset2ref(sourceset, branch, tag)
	if sourceset == "branch" or
	   (sourceset == "lazytag" and tag == "^") then
		return string.format("refs/heads/%s", branch)
	elseif sourceset == "tag" or
         (sourceset == "lazytag" and tag ~= "^") then
		return string.format("refs/tags/%s", tag)
	end
	return nil, "invalid sourceset"
end
