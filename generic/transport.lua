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

require("buildconfig")

local tools = {
	which = { name = "which", flags = "", optional = false },
	curl = { name = "curl", flags = "", optional = false },
	ssh = { name = "ssh", flags = "", optional = false },
	scp = { name = "scp", flags = "", optional = false },
	rsync = { name = "rsync", flags = "", optional = false },
	git = { name = "git", flags = "", optional = false },
	cvs = { name = "cvs", flags = "", optional = true },
	svn = { name = "svn", flags = "", optional = true },
	mktemp = { name = "mktemp", flags = "", optional = false },
	rm = { name = "rm", flags = "", optional = false },
	mkdir = { name = "mkdir", flags = "", optional = false },
	rmdir = { name = "rmdir", flags = "", optional = false },
	cp = { name = "cp", flags = "", optional = false },
	ln = { name = "ln", flags = "", optional = false },
	mv = { name = "mv", flags = "", optional = false },
	tar = { name = "tar", flags = "", optional = false },
	sha1sum = { name = "sha1sum", flags = "", optional = false },
	md5sum = { name = "md5sum", flags = "", optional = false },
	chmod = { name = "chmod", flags = "", optional = false },
	test = { name = "test", flags = "", optional = false },
	cat = { name = "cat", flags = "", optional = false },
	touch = { name = "touch", flags = "", optional = false },
	uname = { name = "uname", flags = "", optional = false },
	patch = { name = "patch", flags = "", optional = false },
        ["e2-su"] = { name = buildconfig.PREFIX .. "/bin/e2-su", flags = "",
							optional = false },
	["e2-su-2.2"] = { name = buildconfig.PREFIX .. "/bin/e2-su-2.2",
						flags = "", optional = false },
}


--- get a tool command
-- @param name string: the tool name
-- @return string: the tool command, nil on error
local function get_tool(name)
	if not tools[name] then
		e2lib.bomb("looking up invalid tool: " .. tostring(name))
	end
	return tools[name].path
end

--- get tool flags
-- @param name string: the tool name
-- @return string: the tool flags
local function get_tool_flags(name)
	if not tools[name] then
		e2lib.bomb("looking up flags for invalid tool: " .. 
							tostring(name))
	end
	return tools[name].flags or ""
end

--- set a tool command and flags
-- @param name string: the tool name
-- @param value string: the new tool command
-- @param flags string: the new tool flags. Optional.
-- @return bool
-- @return nil, an error string on error
local function set_tool(name, value, flags)
	if not tools[name] then
		return false, "invalid tool setting"
	end
	if type(value) == "string" then
		tools[name].name = value
	end
	if type(flags) == "string" then
		tools[name].flags = flags
	end
	e2lib.log(3, string.format("setting tool: %s=%s flags=%s",
				name, tools[name].name, tools[name].flags))
	return true, nil
end

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

		local args = string.format(
					" %s '%s%s:/%s/%s' '%s/%s'",
					port,user, u.servername, u.path, location,
					destdir, tmpfile)
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
-- @return true on success, false on error
-- @return nil, an error string on error
function push_file(sourcefile, durl, location, push_permissions)
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
		rc, re = e2lib.rsync(args)
		if not rc then
			return false, re
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

--- check if a tool is available
-- @param name string a valid tool name
-- @return bool
-- @return nil, an error string on error
function check_tool(name)
	local tool = tools[name]
	if not tool.path then
		local which = string.format("which \"%s\"", tool.name)
		local p = io.popen(which, "r")
		tool.path = p:read()
		p:close()
		if not tool.path then
			e2lib.log(3, string.format(
				"tool not available: %s", tool.name))
			return false, "tool not available"
		end
	end
	e2lib.log(4, string.format(
		"tool available: %s (%s)", 
		tool.name, tool.path))
	return true
end

--- initialize the library
-- @return bool
function init()
	local error = false
	for tool,t in pairs(tools) do
		local rc = check_tool(tool)
		if not rc then
			local warn = "Warning"
			if not t.optional then
				error = true
				warn = "Error"
			end
			e2lib.log(1, string.format(
					"%s: tool is not available: %s",
							warn, tool))
		end
	end
	if error then
		return false, "missing mandatory tools"
	end
	return true, nil
end

transport = {}
transport.check_tool = check_tool
transport.get_tool = get_tool
transport.get_tool_flags = get_tool_flags
transport.set_tool = set_tool
transport.init = init
transport.fetch_file = fetch_file
transport.push_file = push_file
transport.file_path = file_path
