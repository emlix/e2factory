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

-- e2-new-source - add new source onto an existing server -*- Lua -*-


local e2lib = require("e2lib")
local e2tool = require("e2tool")
local generic_git = require("generic_git")
local cache = require("cache")
local err = require("err")
local e2option = require("e2option")

e2lib.init()
local info, re = e2tool.local_init(nil, "new-source")
if not info then
    e2lib.abort(re)
end

e2option.documentation = [[
usage: e2-new-source --git [--server <server>] <name>
       e2-new-source --files [--no-checksum]
		[<server>:]<location> <source_file_url> [<checksum_file_url>]

 Put new source onto an existing server.

 --git
 Put a repository named <name> into the projects' 'git/' directory on
 the server, i.e. <server>/<project>/git/<name>.git
 The server defaults to the default repository server, and the <project>
 part is the project location relative to the projects server.

 --files
 Put a new file onto the server.
 Server defaults to 'upstream'

 Note that URLs must be passed as the <source_file_url> and
 <checksum_file_url> arguments, not filesystem paths.
]]

e2option.flag("git", "create a git repository")
e2option.flag("files", "create a new file on a files server")
e2option.option("server", "specify server")
e2option.flag("no-checksum", "don't verify checksum")
local opts, arguments = e2option.parse(arg)

-- read a checksum from a file
-- @param checksum_file string: the file containing the checksums
-- @param filename string: the filename
-- @return a table with fields checksum and checksum_type ("sha1", "md5")
-- @return nil, or an error string on error
local function read_checksum(checksum_file, filename)
    e2lib.log(4, string.format("read_checksum(%s, %s)", checksum_file,
    filename))
    local f, e = io.open(checksum_file, "r")
    if not f then
        return nil, e
    end
    local rc = nil
    local e = err.new("no checksum available")
    while true do
        local line = f:read()
        if not line then
            break
        end
        local c, f = line:match("(%S+)  (%S+)")
        if (not c) or (not f) then
            e:append("Checksum file has wrong format. ")
            e:append("The standard sha1sum or md5sum format is "..
            "required.")
            return nil, e
        end
        if c and f and f == filename then
            local cs = {}
            cs.checksum = c
            if c:len() == 40 then
                cs.checksum_type = "sha1"
            elseif c:len() == 32 then
                cs.checksum_type = "md5"
            else
                rc = nil
                e = "can't guess checksum type"
                break
            end
            rc = cs
            e = nil
            break
        end
    end
    f:close()
    return rc, e
end

--- generate a sha1 checksum file
-- @param source_file string: source file name
-- @param checksum_file: checksum file name
-- @return bool
-- @return nil, an error string on error
local function write_checksum_file_sha1(source_file, checksum_file)
    e2lib.log(4, string.format("write_checksum_file_sha1(%s, %s)",
    source_file, checksum_file))
    local cmd = string.format("sha1sum %s > %s",
    e2lib.shquote(source_file), e2lib.shquote(checksum_file))
    local rc = e2lib.callcmd_capture(cmd)
    if rc ~= 0 then
        return false, "error writing checksum file"
    end
    return true, nil
end

local function download(f)
    local name = e2lib.basename(f)
    local cmd = string.format("curl --silent --fail %s > %s",
    e2lib.shquote(f), e2lib.shquote(name))
    local rc = e2lib.callcmd_capture(cmd)
    if rc ~= 0 then
        return false, err.new("download failed: %s", f)
    end
    return true, nil
end

--- new files source
-- @param location string: server/location string
-- @param source_file string: source file url
-- @param checksum_file string: checksum file url
-- @param flags table: flags
-- @return bool
-- @return nil, an error string on error
local function new_files_source(c, server, location, source_file, checksum_file,
    checksum_file_format, no_checksum)
    local source_file_base = e2lib.basename(source_file)
    local do_checksum = (not no_checksum)
    local checksum_type = "sha1"
    local checksum_file_base
    local checksum_file1
    local checksum_file2 = string.format("%s.%s", source_file_base,
    checksum_type)
    local cs1, cs2
    local rc, e
    if not do_checksum then
        e2lib.warn("WOTHER", "Checksum verifying is disabled!")
    end

    -- change to a temporary directory
    local tmpdir, e = e2lib.mktempdir()
    if not e2lib.chdir(tmpdir) then
        e2lib.abort("can't chdir")
    end

    -- download
    e2lib.log(1, string.format("fetching %s ...", source_file))
    local rc, re = download(source_file)
    if not rc then
        e2lib.abort(re)
    end

    -- checksum checking
    if do_checksum then
        e2lib.log(1, string.format("fetching %s ...", checksum_file))
        local rc, re = download(checksum_file)
        if not rc then
            e2lib.abort(re)
        end
        checksum_file_base = e2lib.basename(checksum_file)
        checksum_file1 = string.format("%s.orig",
        checksum_file_base)
        rc, e = e2lib.mv(checksum_file_base, checksum_file1)
        if not rc then
            e2lib.abort(e)
        end
        cs1, e = read_checksum(checksum_file1, source_file_base)
        if not cs1 then
            e2lib.abort(e)
        end
        checksum_type = cs1.checksum_type
    end

    -- write the checksum file to store on the server
    rc = write_checksum_file_sha1(source_file_base, checksum_file2)
    cs2, e = read_checksum(checksum_file2, source_file_base)
    if not cs2 then
        e2lib.abort(e)
    end

    -- compare checksums
    if do_checksum then
        if cs1.checksum == cs2.checksum then
            e2lib.log(2, string.format(
            "checksum matches (%s): %s",
            cs1.checksum_type, cs1.checksum))
        else
            e2lib.abort("checksum mismatch")
        end
    end

    -- store
    local flags = {}
    local rlocation = string.format("%s/%s", location, source_file_base)
    e2lib.log(1, string.format("storing file %s to %s:%s",
    source_file_base, server, rlocation))
    local rc, e = cache.push_file(c, source_file_base, server,
    rlocation, flags)
    if not rc then
        e2lib.abort(e)
    end
    local rlocation = string.format("%s/%s", location, checksum_file2)
    e2lib.log(1, string.format("storing file %s to %s:%s",
    checksum_file2, server, rlocation))
    local rc, e = cache.push_file(c, checksum_file2, server,
    rlocation, flags)
    if not rc then
        e2lib.abort(e)
    end
    if not e2lib.chdir("/") then
        e2lib.abort("can't chdir")
    end
    return true, nil
end

info, re = e2tool.collect_project_info(info)
if not info then
    e2lib.abort(re)
end

if opts.git then
    if #arguments ~= 1 then
        e2lib.abort("<name> argument required")
    end
    -- remote
    local rserver = info.default_repo_server
    if opts["server"] then
        rserver = opts["server"]
    end
    local name = arguments[1]
    local rlocation = string.format("%s/git/%s.git", info.project_location, name)
    -- local
    local lserver = info.root_server_name
    local llocation = string.format("in/%s/.git", name)
    local flags = {}
    local rc, re = generic_git.new_repository(info.cache, lserver, llocation,
    rserver, rlocation, flags)
    if not rc then
        e2lib.abort(re)
    end
    e2lib.log(1,
    "See e2-new-source(1) to see how to go on")
elseif opts.files then
    local location = arguments[1]
    local sl, e = e2lib.parse_server_location(location, info.default_files_server)
    if not sl then
        e2lib.abort(e)
    end
    local server = sl.server
    local location = sl.location
    local source_file = arguments[2]
    local checksum_file = arguments[3]
    local checksum_file_format = opts["checksum-file"]
    local no_checksum = opts["no-checksum"]
    if not no_checksum and not checksum_file then
        e2lib.abort("checksum file not given")
    end
    local rc = new_files_source(info.cache, server, location, source_file,
    checksum_file, checksum_file_format, no_checksum)
else
    e2lib.log(1, "Creating repositories other than git is not supported yet.")
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
