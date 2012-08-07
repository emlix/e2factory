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
local url = require("url")

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

    local rsh = tools.get_tool("ssh") .. " " .. tools.get_tool_flags("ssh")
    table.insert(argv, "--rsh=" .. rsh)

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
-- @param directory string: the directory to create on the server
-- @return bool
-- @return an error object on failure
local function rsync_ssh_mkdir(opts, user, server, dir)
    assert(type(opts) == "table")
    assert(type(server) == "string")
    assert(type(dir) == "string")

    local emptydir = e2lib.mktempdir()
    local stack = {}
    local argv = {}
    for _,opt in ipairs(opts) do
        table.insert(argv, opt)
    end
    table.insert(argv, "-r")

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
            local e = new_error("could not create remote directory")
            return false, e:cat(re)
        end
    end
    e2lib.rmtempdir(emptydir)
    return true, nil
end

--- fetch a file from a server
-- @param surl url to the server
-- @param location location relative to the server url
-- @param destdir where to store the file locally
-- @param destname filename of the fetched file
-- @return true on success, false on error
-- @return an error object on failure
function transport.fetch_file(surl, location, destdir, destname)
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
    if u.transport == "http" or
        u.transport == "https" then
        -- use special flags here
        local curlflags = "--create-dirs --silent --show-error --fail"
        local args = string.format("%s '%s/%s' -o '%s/%s'",
        curlflags, u.url, location, destdir, tmpfile)
        rc, re = e2lib.curl(args)
        if not rc then
            return false, e:cat(re)
        end
    elseif u.transport == "file" then
        -- rsync "sourcefile" "destdir/destfile"
        local argv = {}
        table.insert(argv, "/" .. u.path .. "/" .. location)
        table.insert(argv, destdir .. "/" .. tmpfile)
        rc, re = e2lib.rsync(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif u.transport == "rsync+ssh" then
        local sdir = "/" .. u.path .. "/" .. location
        local ddir = destdir .. "/" .. tmpfile
        local src =  rsync_quote_remote(u.user, u.servername, sdir)
        rc, re = rsync_ssh({}, src, ddir)
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
        local destfile = string.format("%s/%s", destdir, tmpfile)

        rc, re = e2lib.scp({ sourcefile , destfile })
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
function transport.push_file(sourcefile, durl, location, push_permissions, try_hardlink)
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
        local rsync_argv = {}
        if push_permissions then
            mkdir_perm = string.format("--mode \"%s\"",
            push_permissions)

            table.insert(rsync_argv, "--perms")
            table.insert(rsync_argv, "--chmod")
            table.insert(rsync_argv, push_permissions)

        end
        for _,d in ipairs(dirs) do
            local mkdir_flags = string.format("-p %s", mkdir_perm)
            rc, re = e2lib.mkdir(d, mkdir_flags)
            if not rc then
                return false, e:cat(re)
            end
        end
        table.insert(rsync_argv, sourcefile)
        table.insert(rsync_argv, destdir .. "/" .. destname)
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
            rc, re = e2lib.rsync(rsync_argv)
            if not rc then
                return false, re
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

        local argv = { user..u.servername, "mkdir", "-p",
        e2lib.shquote(destdir) }
        rc, re = e2lib.ssh(argv)
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

--- fetch a file from a server
-- @param surl url to the server
-- @param location location relative to the server url
-- @return true on success, false on error
-- @return nil, an error string on error
function transport.file_path(surl, location)
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

return transport

-- vim:sw=4:sts=4:et:
