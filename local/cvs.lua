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

-- cvs.lua - CVS-specific SCM operations -*- Lua -*-
--
module("cvs", package.seeall)
require("scm")

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
function cvs.validate_source(info, sourcename)
  local rc, re = git.generic_validate_source(info, sourcename)
  if not rc then
    -- error in generic configuration. Don't try to go on.
    return false, re
  end
  local src = info.sources[ sourcename ]
  if not src.sourceid then
    src.sourceid = {}
  end
  local e = new_error("in source %s:", sourcename)
  rc, re = git.source_apply_default_working(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  e:setcount(0)
  -- XXX should move the default value out of the validate function
  if not src.server then
    e:append("source has no `server' attribute")
  end
  if not src.licences then
    e:append("source has no `licences' attribute")
  end
  if not src.cvsroot then
    e2lib.warnf("WDEFAULT", "in source %s:", sourcename)
    e2lib.warnf("WDEFAULT",
	" source has no `cvsroot' attribute, defaulting to the server path")
    src.cvsroot = "."
  end
  if not src.cvsroot then
    e:append("source has no `cvsroot' attribute")
  end
  if src.remote then
    e:append("source has `remote' attribute, not allowed for cvs sources")
  end
  if not src.branch then
    e:append("source has no `branch' attribute")
  end
  if not type(src.tag) == "string" then
    e:append("source has no `tag' attribute or tag attribute has wrong type")
  end
  if not src.module then
    e:append("source has no `module' attribute")
  end
  if not src.working then
    e:append("source has no `working' attribute")
  end
  local rc, re = tools.check_tool("cvs")
  if not rc then
    e:cat(re)
  end
  if e:getcount() > 0 then
    return false, e
  end
  return true, nil
end

--- build the cvsroot string
-- @param u url table
-- @return string: cvsroot, nil on error
-- @return an error object on failure
local function mkcvsroot(u)
  local cvsroot = nil
  if u.transport == "file" then
    cvsroot = string.format("/%s", u.path)
  elseif (u.transport == "ssh") or
         (u.transport == "rsync+ssh") then
    cvsroot = string.format("%s:/%s", u.server, u.path)
  elseif u.transport == "cvspserver" then
    cvsroot = string.format(":pserver:%s:/%s", u.server, u.path)
  else
    return nil, new_error("cvs: transport not supported")
  end
  return cvsroot, nil
end

--- build the revision string containing branch or tag name
-- @param src table: source table
-- @param source_set string: source set
-- @return string: cvsroot, nil on error
-- @return an error object on failure
local function mkrev(src, source_set)
  local rev = nil
  if source_set == "branch" or
     (source_set == "lazytag" and src.tag == "^") then
    rev = src.branch
  elseif (source_set == "tag" or source_set == "lazytag") and
	 src.tag ~= "^" then
    rev = src.tag
  end
  if not rev then
    return nil, new_error("source set not allowed")
  end
  return rev, nil
end

function cvs.fetch_source(info, sourcename)
  local rc, re = cvs.validate_source(info, sourcename)
  if not rc then
    return false, re
  end
  local e = new_error("fetching source failed: %s", sourcename)
  local src = info.sources[ sourcename ]
  local location = src.cvsroot
  local server = src.server
  local surl, re = info.cache:remote_url(server, location)
  if not surl then
    return false, e:cat(re)
  end
  local u, re = url.parse(surl)
  if not u then
    return false, e:cat(re)
  end
  local cmd = nil
  local cvsroot, re = mkcvsroot(u)
  if not cvsroot then
    return false, e:cat(re)
  end
  -- always fetch the configured branch, as we don't know the build mode here.
  local rev = src.branch
  local rsh = tools.get_tool("ssh")
  local cvstool = tools.get_tool("cvs")
  local cvsflags = tools.get_tool_flags("cvs")
  -- split the working directory into dirname and basename as some cvs clients
  -- don't like slashes (e.g. in/foo) in their checkout -d<path> argument
  local dir = e2lib.dirname(src.working)
  local base = e2lib.basename(src.working)
  -- cd info.root && cvs -d cvsroot checkout -R [-r rev] -d working module
  if rev == "HEAD" then
    -- HEAD is a special case in cvs: do not pass -r 'HEAD' to cvs checkout
    rev = ""
  else
    rev = string.format("-r '%s'", rev)
  end
  cmd = string.format("cd %s/%s && CVS_RSH=%s " ..
    "%s %s -d %s checkout -R %s -d %s %s",
    e2lib.shquote(info.root), e2lib.shquote(dir), e2lib.shquote(rsh),
    e2lib.shquote(cvstool), cvsflags, e2lib.shquote(cvsroot),
    e2lib.shquote(rev), e2lib.shquote(base), e2lib.shquote(src.module))
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    return false, e:cat(re)
  end
  return true, nil
end

function cvs.prepare_source(info, sourcename, source_set, buildpath)
  local rc, re = cvs.validate_source(info, sourcename)
  if not rc then
    return false, re
  end
  local e = new_error("cvs.prepare_source failed")
  local src = info.sources[ sourcename ]
  local location = src.cvsroot
  local server = src.server
  local surl, re = info.cache:remote_url(server, location)
  if not surl then
    return false, e:cat(re)
  end
  local u, re = url.parse(surl)
  if not u then
    return false, e:cat(re)
  end
  local cvsroot, re = mkcvsroot(u)  -- XXX error checking
  if not cvsroot then
    return false, re
  end
  local cmd = nil
  if source_set == "tag" or source_set == "branch" then
    local rev = mkrev(src, source_set)
    local rsh = tools.get_tool("ssh")
    local cvstool = tools.get_tool("cvs")
    local cvsflags = tools.get_tool_flags("cvs")
    -- cd buildpath && cvs -d cvsroot export -R -r rev module
    cmd = string.format("cd %s && CVS_RSH=%s " ..
      "%s %s -d %s export -R -r %s -d %s %s",
      e2lib.shquote(buildpath), e2lib.shquote(rsh), e2lib.shquote(cvstool),
      cvsflags, e2lib.shquote(cvsroot), e2lib.shquote(rev),
      e2lib.shquote(src.name), e2lib.shquote(src.module))
  elseif source_set == "working-copy" then
    -- cp -R info.root/src.working buildpath
    cmd = string.format("cp -R %s/%s %s/%s",
      e2lib.shquote(info.root), e2lib.shquote(src.working),
      e2lib.shquote(buildpath), e2lib.shquote(src.name))
  else
    e2lib.abort("invalid build mode")
  end
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    return false, e:cat(re)
  end
  return true, nil
end

function cvs.update(info, sourcename)
  local rc, re = cvs.validate_source(info, sourcename)
  if not rc then
    e2lib.abort(re)
  end
  local e = new_error("updating cvs source failed")
  local src = info.sources[ sourcename ]
  local working = string.format("%s/%s", info.root, src.working)
  local rsh = tools.get_tool("ssh")
  local cvstool = tools.get_tool("cvs")
  local cvsflags = tools.get_tool_flags("cvs")
  local cmd = string.format("cd %s && CVS_RSH=%s %s %s update -R",
    e2lib.shquote(working), e2lib.shquote(rsh), e2lib.shquote(cvstool),
    cvsflags)
  local rc, re = e2lib.callcmd_log(cmd)
  if rc ~= 0 then
    e:cat(re)
    return false, e
  end
  return true, nil
end

function cvs.working_copy_available(info, sourcename)
  local rc, e
  rc, e = cvs.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  local src = info.sources[sourcename]
  local dir = string.format("%s/%s", info.root, src.working)
  return e2lib.isdir(dir)
end

function cvs.has_working_copy(info, sourcename)
  return true
end

--- create a table of lines for display
-- @param info the info structure
-- @param sourcename string
-- @return a table, nil on error
-- @return an error object on failure
function cvs.display(info, sourcename)
  local src = info.sources[sourcename]
  local rc, re
  rc, re = cvs.validate_source(info, sourcename)
  if not rc then
    return false, re
  end
  local display = {}
  display[1] = string.format("type       = %s", src.type)
  display[2] = string.format("branch     = %s", src.branch)
  display[3] = string.format("tag        = %s", src.tag)
  display[4] = string.format("server     = %s", src.server)
  display[5] = string.format("cvsroot    = %s", src.cvsroot)
  display[6] = string.format("module     = %s", src.module)
  display[7] = string.format("working    = %s", src.working)
  local i = 8
  for _,l in ipairs(src.licences) do
    display[i] = string.format("licence    = %s", l)
    i = i + 1
  end
  for k,v in pairs(src.sourceid) do
    if v then
      display[i] = string.format("sourceid [%s] = %s", k, v)
      i = i + 1
    end
  end
  return display, nil
end

function cvs.sourceid(info, sourcename, source_set)
	local src = info.sources[sourcename]
	local rc, re
	rc, re = cvs.validate_source(info, sourcename)
	if not rc then
		return false, re
	end
	if source_set == "working-copy" then
		src.sourceid[source_set] = "working-copy"
	end
	if src.sourceid[source_set] then
		return true, nil, src.sourceid[source_set]
	end
	local e = new_error("calculating sourceid failed for source %s",
								sourcename)
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
	-- cvs specific
	if source_set == "tag" and src.tag ~= "^" then
		-- we rely on tags being unique with cvs
		hc:hash_line(src.tag)
	else
		-- the old function took a hash of the CVS/Entries file, but
		-- forgot the subdirecties' CVS/Entries files. We might
		-- reimplement that once...
		e:append("cannot calculate sourceid for source set %s",
								source_set)
		return false, e
	end
	hash.hash_line(hc, src.server)
	hash.hash_line(hc, src.cvsroot)
	hash.hash_line(hc, src.module)
	-- skip src.working
	e2lib.logf(4, "hash data for source %s\n%s", src.name, hc.data)
	src.sourceid[source_set] = hash.hash_finish(hc)
	return true, nil, src.sourceid[source_set]
end

function cvs.toresult(info, sourcename, sourceset, directory)
	-- <directory>/source/<sourcename>.tar.gz
	-- <directory>/makefile
	-- <directory>/licences
	local rc, re
	local e = new_error("converting result")
	rc, re = git.check(info, sourcename, true)
	if not rc then
		return false, e:cat(re)
	end
	local src = info.sources[sourcename]
	-- write makefile
	local makefile = "makefile"
	local source = "source"
	local sourcedir = string.format("%s/%s", directory, source)
	local archive = string.format("%s.tar.gz", sourcename)
	local fname  = string.format("%s/%s", directory, makefile)
	rc, re = e2lib.mkdir(sourcedir, "-p")
	if not rc then
		return false, e:cat(re)
	end
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
	-- export the source tree to a temporary directory
	local tmpdir = e2lib.mktempdir()
	rc, re = cvs.prepare_source(info, sourcename, sourceset, tmpdir)
	if not rc then
		return false, e:cat(re)
	end
	-- create a tarball in the final location
	local archive = string.format("%s.tar.gz", src.name)
	local tar_args = string.format("-C '%s' -czf '%s/%s' '%s'",
					tmpdir,	sourcedir, archive, sourcename)
	rc, re = e2lib.tar(tar_args)
	if not rc then
		return false, e:cat(re)
	end
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
	e2lib.rmtempdir(tmpdir)
	return true, nil
end

function cvs.check_workingcopy(info, sourcename)
	local rc, re
	local e = new_error("checking working copy failed")
	e:append("in source %s (cvs configuration):", sourcename)
	e:setcount(0)
	rc, re = cvs.validate_source(info, sourcename)
	if not rc then
		return false, re
	end
	local src = info.sources[sourcename]
	if e:getcount() > 0 then
		return false, e
	end
	return true, nil
end

scm.register("cvs", cvs)
