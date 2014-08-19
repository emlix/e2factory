--- Transport Backend
-- @module generic.transport

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

local transport = {}
local e2lib = require("e2lib")
local url = require("url")
local tools = require("tools")
local err = require("err")
local strict = require("strict")

--- call rsync with appropriate rsh argument according to the tools
-- configuration
-- @param opts table: options vector to pass to rsync
-- @param src string: source path
-- @param dest string: destination path
-- @return bool
-- @return an error object on failure
local function rsync_ssh(opts, src, dest)
    assert(type(opts) == "table")
    assert(type(src) == "string")
    assert(type(dest) == "string")

    local argv = {}

    for _,opt in ipairs(opts) do
        table.insert(argv, opt)
    end

    table.insert(argv, "-L") -- copy symlinks as real files
    table.insert(argv, "-k") -- copy dirlinks as directories

    local rsh, rshflags, re

    rsh, re = tools.get_tool("ssh")
    if not rsh then
        return false, re
    end

    rsh = string.format("--rsh=%s", rsh)

    rshflags, re = tools.get_tool_flags("ssh")
    if not rshflags then
        return false, re
    end

    rshflags = table.concat(rshflags, " ")

    if rshflags ~= "" then
        rsh = string.format("%s %s", rsh, rshflags)
    end


    table.insert(argv, rsh)
    table.insert(argv, src)
    table.insert(argv, dest)

    return e2lib.rsync(argv)
end

--- escape remote directory name
-- @param user string: optional username or nil
-- @param server string: server name
-- @param dir string: remote directory
-- @return string: quoted remote dir string
local function rsync_quote_remote(user, server, dir)
    assert(user == nil or type(user) == "string")
    assert(type(server) == "string")
    assert(type(dir) == "string")

    if user then
        user = string.format("%s@", user)
    else
        user = ""
    end

    return string.format("%s%s:%s", user, server, e2lib.shquote(dir))
end

--- create a remote directory by copying an empty directory using rsync
-- (for use with restriced shell access)
-- @param opts table: options vector to pass to rsync
-- @param user string: optional username or nil
-- @param server string: the server part of the directory to create
-- @param dir string: the directory to create on the server
-- @return bool
-- @return an error object on failure
local function rsync_ssh_mkdir(opts, user, server, dir)
    assert(type(opts) == "table")
    assert(type(server) == "string")
    assert(type(dir) == "string")

    local stack = {}
    local argv = {}
    for _,opt in ipairs(opts) do
        table.insert(argv, opt)
    end
    table.insert(argv, "-r")

    local emptydir, re = e2lib.mktempdir()
    if not emptydir then
        return false, re
    end

    while dir ~= "/" do
        local dest = rsync_quote_remote(user, server, dir .. "/")
        local rc, re = rsync_ssh(argv, emptydir .. "/", dest)
        if rc then
            e2lib.logf(4, "created remote directory '%s'", dir)
            -- successfully made a directory
            break
        else
            -- this directory could not be made, put on stack
            -- and try again with one component removed
            e2lib.logf(4, "could not create remote directory '%s'", dir)
            table.insert(stack, 1, e2lib.basename(dir))
            dir = e2lib.dirname(dir)
        end
    end

    while #stack > 0 do
        dir = dir .. "/" .. stack[1]
        table.remove(stack, 1)
        local dest = rsync_quote_remote(user, server, dir .. "/")
        local rc, re = rsync_ssh(argv, emptydir .. "/", dest)
        if not rc then
            e2lib.rmtempdir(emptydir)
            local e = err.new("could not create remote directory")
            return false, e:cat(re)
        end
    end
    e2lib.rmtempdir(emptydir)
    return true, nil
end

--- Fetch a file from a server.
-- @param surl url to the server
-- @param location location relative to the server url
-- @param destdir Where to store the file locally.
-- @param destname Filename of the fetched file (optional). If not specified,
--                 the basename of location is used.
-- @return True on success, false on error.
-- @return Error object on failure.
function transport.fetch_file(surl, location, destdir, destname)
    if not destname then
        destname = e2lib.basename(location)
    end

    local rc, re
    local e = err.new("transport: fetching file failed")
    local u, re = url.parse(surl)
    if not u then
        return false, e:cat(re)
    end
    -- create the destination directory
    rc, re = e2lib.mkdir_recursive(destdir)
    if not rc then
        return false, e:cat(re)
    end

    local template = string.format("%s/%s.XXXXXX", destdir, destname)
    local tmpfile_path, re = e2lib.mktempfile(template)
    if not tmpfile_path then
        return false, e:cat(re)
    end
    local tmpfile = e2lib.basename(tmpfile_path)

    -- Some tools (rsync) do not return an error code when skipping symlinks,
    -- device files, etc. Thus we delete the tmp file here, let rsync do its
    -- job, and detect the silent error condition when moving the file to its
    -- final destination. Yes there is a race, but we take that chance over
    -- missing error detection.
    e2lib.rmtempfile(tmpfile_path)

    -- Some tools (rsync) do not return an error code when skipping symlinks,
    -- device files, etc. Thus we delete the tmp file here, let rsync do its
    -- job, and detect the silent error condition when moving the file to its
    -- final destination. Yes there is a race, but we take that chance over
    -- missing error detection.
    e2lib.rmtempfile(tmpfile_path)

    -- fetch the file to the temporary directory
    if u.transport == "http" or
        u.transport == "https" then
        local curl_argv = {}
        local url_loc =  string.format("%s/%s",  u.url, location)
        -- use special flags here
        table.insert(curl_argv, "--create-dirs")
        table.insert(curl_argv, "--silent")
        table.insert(curl_argv, "--show-error")
        table.insert(curl_argv, "--fail")

        table.insert(curl_argv, url_loc)
        table.insert(curl_argv, "-o")
        table.insert(curl_argv, tmpfile_path)

        rc, re = e2lib.curl(curl_argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif u.transport == "file" then
        -- rsync "sourcefile" "destdir/destfile"
        local argv = {}
        table.insert(argv, "-L") -- copy symlinks as real files.
        table.insert(argv, e2lib.join("/", u.path, location))
        table.insert(argv, tmpfile_path)
        rc, re = e2lib.rsync(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif u.transport == "rsync+ssh" then
        local sdir = e2lib.join("/", u.path, location)
        local src =  rsync_quote_remote(u.user, u.servername, sdir)
        rc, re = rsync_ssh({}, src, tmpfile_path)
        if not rc then
            return false, e:cat(re)
        end
    elseif u.transport == "scp" or
        u.transport == "ssh" then
        local user = ""
        if u.user then
            user = string.format("%s@", u.user)
        end

        local sourceserv = string.format("%s%s:", user, u.servername)
        local sourcefile = string.format("/%s/%s", u.path, location)
        sourcefile = e2lib.shquote(sourcefile)
        sourcefile = sourceserv .. sourcefile

        rc, re = e2lib.scp({ sourcefile , tmpfile_path })
        if not rc then
            return false, e:cat(re)
        end
    else
        e:append("fetch file: unhandled transport: %s", u.transport)
        return false, e
    end
    -- Move the file into place atomically. This may fail when the copy
    -- operation above failed silently (looking at rsync here).
    rc, re = e2lib.mv(tmpfile_path, e2lib.join(destdir, destname))
    if not rc then
        return false, e:cat(re)
    end
    return true
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
function transport.push_file(sourcefile, durl, location, push_permissions, try_hardlink)
    assert(type(sourcefile) == "string" and sourcefile ~= "", "sourcefile invalid")
    assert(type(durl) == "string" and durl ~= "")
    assert(type(location) == "string" and location ~= "")
    assert(push_permissions == nil or type(push_permissions) == "string")
    assert(try_hardlink == nil or type(try_hardlink) == "boolean")

    local rc, e
    e = err.new("error pushing file to server")
    durl = string.format("%s/%s", durl, location)
    local u, re = url.parse(durl)
    if not u then
        return false, e:cat(re)
    end
    if u.transport == "file" then
        local destdir = string.format("/%s", e2lib.dirname(u.path))
        local destname = e2lib.basename(u.path)
        local mode = nil

        if push_permissions then
            mode, re = e2lib.parse_mode(push_permissions)
            if not mode then
                return false, e:cat(re)
            end
        end

        rc, re = e2lib.mkdir_recursive(destdir, mode)
        if not rc then
            return false, e:cat(re)
        end

        local rsync_argv = {}
        if push_permissions then
            table.insert(rsync_argv, "--perms")
            table.insert(rsync_argv, "--chmod")
            table.insert(rsync_argv, push_permissions)
        end
        local done = false
        local dst = e2lib.join(destdir, destname)
        if (not push_permissions) and try_hardlink then
            local dst = e2lib.join(destdir, destname)
            if e2lib.exists(dst) then
                e2lib.unlink(dst) -- ignore error, hardlink will fail
            end
            rc, re = e2lib.hardlink(sourcefile, dst)
            if rc then
                done = true
            else
                e2lib.log(4, "Creating hardlink failed. "..
                "Falling back to copying.")
            end
        end
        if not done then
            rc, re = rsync_ssh(rsync_argv, sourcefile, dst)
            if not rc then
                return false, e:cat(re)
            end
        end
    elseif u.transport == "rsync+ssh" then
        local destdir = string.format("/%s", e2lib.dirname(u.path))
        local destname = e2lib.basename(u.path)

        local rsync_argv = {}
        if push_permissions then
            table.insert(rsync_argv, "--perms")
            table.insert(rsync_argv, "--chmod")
            table.insert(rsync_argv, push_permissions)
        end

        rc, re = rsync_ssh_mkdir(rsync_argv, u.user,
        u.servername, destdir)
        if not rc then
            return false, re
        end

        local ddir = destdir .. "/" .. destname
        local dest = rsync_quote_remote(u.user, u.servername, ddir)
        rc, re = rsync_ssh(rsync_argv, sourcefile, dest)
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
        local user = ""
        if u.user then
            user = string.format("%s@", u.user)
        end

        rc, re = e2lib.ssh_remote_cmd(u, { "mkdir", "-p", destdir })
        if not rc then
            return false, re
        end

        local destserv = string.format("%s%s:", user, u.servername)
        local destfile = string.format("%s/%s", destdir, destname)
        destfile = e2lib.shquote(destfile)
        destfile = destserv .. destfile
        rc, re = e2lib.scp({ sourcefile, destfile })
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

--- Get file path to the specified location, if the file is locally accessable.
-- It's the responsibilty of the caller to check whether the file exists.
-- @param surl Url to the server.
-- @param location Location relative to the server url.
-- @return File path on success, false on error.
-- @return Error string on failure.
function transport.file_path(surl, location)
    local e = err.new("can't get path to file")
    local u, re = url.parse(surl)
    if not u then
        return false, e:cat(re)
    end
    if u.transport ~= "file" then
        return false, e:append("transport does not support file_path()")
    end
    return string.format("/%s/%s", u.path, location)
end

return strict.lock(transport)

-- vim:sw=4:sts=4:et:
