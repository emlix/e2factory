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

module("transport", package.seeall)

--- fetch a file from a server
-- @param surl url to the server
-- @param location location relative to the server url
-- @param destdir where to store the file locally
-- @param destname filename of the fetched file
-- @return true on success, false on error
-- @return an error object on failure
function fetch_file(surl, location, destdir, destname)
	e2lib.log(4, string.format("%s: %s %s %s", "fetch_file()", surl, 
							location, destdir))
	if not destname then
		destname = e2lib.basename(location)
	end
	local rc, re
	local e = new_error("transport: fetching file failed")
	local u, re = url.parse(surl)
	if not u then
		return false, e:cat(re)
	end
	-- create the destination directory
	rc, re = e2lib.mkdir(destdir, "-p")
	if not rc then
		return false, e:cat(re)
	end
	local template = string.format("%s/%s.XXXXXXXXXX", destdir, destname)
	local tmpfile_path = e2lib.mktempfile(template)
	local tmpfile = e2lib.basename(tmpfile_path)
	-- fetch the file to the temporary directory
	if u.transport == "file" or 
	   u.transport == "http" or
	   u.transport == "https" then
		-- use special flags here
		local curlflags = "--create-dirs --silent --show-error --fail"
		local args = string.format("%s %s/%s -o %s/%s",
				curlflags, u.url, location, destdir, tmpfile)
		rc, re = e2lib.curl(args)
		if not rc then
			return false, e:cat(re)
		end
	elseif u.transport == "rsync+ssh" then
		local user
		if u.user then
			user = string.format("%s@", u.user)
		else
			user = ""
		end
		-- rsync --rsh="ssh" "server:sourcefile" "destdir/destfile"
		local rsh = string.format("%s %s", tools.ssh.name,
							tools.ssh.flags)
		local args = string.format(
				"--rsh=\"%s\" '%s%s:/%s/%s' '%s/%s'",
				rsh, user, u.servername, u.path, location,
				destdir, tmpfile)
		rc, re = e2lib.rsync(args)
		if not rc then
			return false, e:cat(re)
		end
	elseif u.transport == "scp" or
	       u.transport == "ssh" then
		local user,port
		if u.user then
			user = string.format("%s@", u.user)
		else
			user = ""
		end
		if u.port then
			if u.transport == "scp" then
				port = "-P " .. u.port
			else
				port = "-p " .. u.port
			end
		else
			port = ""
		end

		local args = string.format(" %s '%s%s:/%s/%s' '%s/%s'",
					port,user, u.servername, u.path,
					location, destdir, tmpfile)
		rc, re = e2lib.scp(args)
		if not rc then
			return false, e:cat(re)
		end
	else
		e:append("unknown transport method: %s", u.transport)
		return false, e
	end
	-- move the file into place atomically
	local src = string.format("%s/%s", destdir, tmpfile)
	local dst = string.format("%s/%s", destdir, destname)
	rc, re = e2lib.mv(src, dst)
	if not rc then
		return false, e:cat(re)
	end
	-- file was moved away above, but remove it from the list anyway
	e2lib.rmtempfile(tmpfile_path)
	return true, nil
end

--- push a file to a server
-- @param sourcefile local file
-- @param durl url to the destination server
-- @param location location relative to the server url
-- @param push_permissions string: permissions to use on the destination
--        side. Works with rsync+ssh only.
-- @param try_hardlink bool: optimize by trying to hardlink instead of copying
-- @return true on success, false on error
-- @return nil, an error string on error
function push_file(sourcefile, durl, location, push_permissions, try_hardlink)
	e2lib.log(4, string.format("%s: %s %s %s %s", "transport.push_file()",
		sourcefile, durl, location, tostring(push_permissions)))
	local rc, e
	e = new_error("error pushing file to server")
	durl = string.format("%s/%s", durl, location)
	local u, re = url.parse(durl)
	if not u then
		return e:cat(re)
	end
	if u.transport == "file" then
		local destdir = string.format("/%s", e2lib.dirname(u.path))
		local destname = e2lib.basename(u.path)
		-- split directories, to apply permissions to all newly
		-- created parent directories, too.
		local dirs = e2lib.parentdirs(destdir)
		local mkdir_perm = ""
		local rsync_perm = ""
		if push_permissions then
			mkdir_perm = string.format("--mode \"%s\"",
							push_permissions)
			rsync_perm = string.format("--perms --chmod \"%s\"",
							push_permissions)
		end
		for _,d in ipairs(dirs) do
			local mkdir_flags = string.format("-p %s", mkdir_perm)
			rc, re = e2lib.mkdir(d, mkdir_flags)
			if not rc then
				return false, e:cat(re)
			end
		end
		local args = string.format("%s '%s' '%s/%s'", rsync_perm,
						sourcefile, destdir, destname)
		local done = false
		if (not push_permissions) and try_hardlink then
			local dst = string.format("%s/%s", destdir, destname)
			rc, re = e2lib.ln(sourcefile, dst, "--force")
			if rc then
				done = true
			else
				e2lib.logf(4, "Creating hardlink failed. "..
						"Falling back to copying.")
			end
		end
		if not done then
			rc, re = e2lib.rsync(args)
			if not rc then
				return false, re
			end
		end
	elseif u.transport == "rsync+ssh" then
		local destdir = string.format("/%s", e2lib.dirname(u.path))
		local destname = e2lib.basename(u.path)
		local user
		if u.user then
			user = string.format("%s@", u.user)
		else
			user = ""
		end
		local mkdir_perm = ""
		local rsync_perm = ""
		if push_permissions then
			mkdir_perm = string.format("--mode \"%s\"", 
							push_permissions)
			rsync_perm = string.format("--perms --chmod \"%s\"",
							push_permissions)
		end
		-- split directories, to apply permissions to all newly
		-- created parent directories, too.
		local dirs = e2lib.parentdirs(destdir)
		local tmp = e2lib.mktempfile()
		local f = io.open(tmp, "w")
		for _,d in ipairs(dirs) do
			local s = string.format("mkdir -p %s \"%s\"\n",
								mkdir_perm, d)
			e2lib.log(4, s)
			f:write(s)
		end
		f:close()
		-- run the mkdir script via ssh
		local args = string.format("'%s%s' <'%s'", user, u.servername,
									tmp)
		rc, re = e2lib.ssh(args)
		if not rc then
			return false, re
		end
		e2lib.rmtempfile(tmp)
		local rsh = string.format("%s %s", tools.ssh.name,
							tools.ssh.flags)
		-- rsync --rsh="ssh" "sourcefile" "destfile"
		local args = string.format(
				"%s --rsh='%s' '%s' '%s%s:/%s/%s'",
				rsync_perm, rsh, sourcefile, 
				user, u.servername, destdir, destname)
		rc, re = e2lib.rsync(args)
		if not rc then
			return false, re
		end
	elseif u.transport == "scp" or
	       u.transport == "ssh" then
		-- scp does not remove partial destination files when
		-- interrupted. Don't use.
		if push_permissions then
			e:append("ssh/scp transport does not support "..
							"permission settings")
			return false, e
		end
		local destdir = string.format("/%s", e2lib.dirname(u.path))
		local destname = e2lib.basename(u.path)
		local user
		if u.user then
			user = string.format("%s@", u.user)
		else
			user = ""
		end
		local args = string.format("'%s%s' mkdir -p '%s'",
						user, u.servername, destdir)
		rc, re = e2lib.ssh(args)
		if not rc then
			return false, re
		end
		local args = string.format("'%s' '%s%s:%s/%s'",
			sourcefile, user, u.servername, destdir, destname)
		rc, re = e2lib.scp(args)
		if not rc then
			return false, re
		end
	else
		e:append("push_file is not implemented for this transport: %s",
								u.transport)
		return false, e
	end
	return true, nil
end

--- fetch a file from a server
-- @param surl url to the server
-- @param location location relative to the server url
-- @return true on success, false on error
-- @return nil, an error string on error
function file_path(surl, location)
	e2lib.log(4, string.format("%s: %s %s", "file_path()", surl, 
							location))
	local e = new_error("can't get path to file")
	local u, re = url.parse(surl)
	if not u then
		return nil, e:cat(re)
	end
	if u.transport ~= "file" then
		return nil, e:append("transport does not support file_path()")
	end
	local path = string.format("/%s/%s", u.path, location)
	return path
end
