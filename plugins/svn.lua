--- Subversion Plugin
-- @module plugins.svn

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

local svn = {}
local scm = require("scm")
local hash = require("hash")
local url = require("url")
local tools = require("tools")
local err = require("err")
local e2lib = require("e2lib")
local eio = require("eio")
local strict = require("strict")

plugin_descriptor = {
    description = "SVN SCM Plugin",
    init = function (ctx) scm.register("svn", svn) return true end,
    exit = function (ctx) return true end,
}

--- translate url into subversion url
-- @param u table: url table
-- @return string: subversion style url
-- @return an error object on failure
local function mksvnurl(surl)
    local rc, re
    local e = err.new("cannot translate url into subversion url:")
    e:append("%s", surl)

    local u, re = url.parse(surl)
    if not u then
        return nil, e:cat(re)
    end

    local transport
    if u.transport == "ssh" or u.transport == "scp" or
        u.transport == "rsync+ssh" then
        transport = "svn+ssh"
    elseif u.transport == "http" or u.transport == "https"
        or u.transport == "svn" or u.transport == "file" then
        transport = u.transport
    else
        return nil,
            e:append("unsupported subversion transport: %s", u.transport)
    end

    return string.format("%s://%s/%s", transport, u.server, u.path)
end

--- Call the svn command.
-- @param argv table: vector with arguments for svn
-- @return True on success, false on error or when svn returned with exit
--         status other than 0.
-- @return Error object on failure.
local function svn_tool(argv, workdir)
    assert(type(argv) == "table")
    assert(workdir == nil or type(workdir) == "string")

    local rc, re
    local svn, flags, svncmd, out, fifo

    svncmd = {}
    out = {}
    fifo = {}

    svn, re = tools.get_tool("svn")
    if not svn then
        return false, re
    end

    table.insert(svncmd, svn)

    flags, re = tools.get_tool_flags("svn")
    if not flags then
        return false, re
    end

    for _,flag in ipairs(flags) do
        table.insert(svncmd, flag)
    end

    for _,arg in ipairs(argv) do
        table.insert(svncmd, arg)
    end

    local function capture(msg)
        if msg == "" then
            return
        end

        if #fifo > 4 then
            table.remove(fifo, 1)
        end

        e2lib.log(3, msg)
        table.insert(fifo, msg)
        table.insert(out, msg)
    end

    rc, re = e2lib.callcmd_capture(svncmd, capture, workdir)
    if not rc then
        return false, err.new("svn command %q failed to execute",
            table.concat(svncmd, " ")):cat(re)

    elseif rc ~= 0 then
        local e = err.new("svn command %q failed with exit status %d",
            table.concat(svncmd, " "), rc)
        for _,v in ipairs(fifo) do
            e:append("%s", v)
        end
        return false, e
    end

    return true, nil, table.concat(out)
end

function svn.fetch_source(info, sourcename)
    local rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local e = err.new("fetching source failed: %s", sourcename)
    local src = info.sources[sourcename]
    local location = src.location
    local server = src.server
    local surl, re = info.cache:remote_url(server, location)
    if not surl then
        return false, e:cat(re)
    end
    local svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, e:cat(re)
    end

    local argv = { "checkout", svnurl, info.root .. "/" .. src.working }

    rc, re = svn_tool(argv)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

function svn.prepare_source(info, sourcename, source_set, build_path)
    local rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local e = err.new("svn.prepare_source failed")
    local src = info.sources[ sourcename ]
    local location = src.location
    local server = src.server
    local surl, re = info.cache:remote_url(server, location)
    if not surl then
        return false, e:cat(re)
    end
    local svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, e:cat(re)
    end
    if source_set == "tag" or source_set == "branch" then
        local rev
        if source_set == "tag" then
            rev = src.tag
        else -- source_set == "branch"
            rev = src.branch
        end
        local argv = { "export", svnurl .. "/" .. rev,
        build_path .. "/" .. sourcename }
        rc, re = svn_tool(argv)
        if not rc then
            return false, e:cat(re)
        end
    elseif source_set == "working-copy" then
        -- cp -R info.root/src.working/src.workingcopy_subdir build_path
        local s = e2lib.join(info.root, src.working, src.workingcopy_subdir)
        local d = e2lib.join(build_path, src.name)
        rc, re = e2lib.cp(s, d, true)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, e:cat("invalid source set")
    end
    return true, nil
end

function svn.working_copy_available(info, sourcename)
    local rc, re
    rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local src = info.sources[sourcename]
    local dir = e2lib.join(info.root, src.working)
    return e2lib.isdir(dir)
end

function svn.check_workingcopy(info, sourcename)
    local rc, re
    local e = err.new("checking working copy failed")
    e:append("in source %s (svn configuration):", sourcename)
    e:setcount(0)
    rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local src = info.sources[sourcename]
    if e:getcount() > 0 then
        return false, e
    end
    -- check if the configured branch and tag exist
    local d
    d = e2lib.join(info.root, src.working, src.branch)
    if not e2lib.isdir(d) then
        e:append("branch does not exist: %s", src.branch)
    end
    d = e2lib.join(info.root, src.working, src.tag)
    if not e2lib.isdir(d) then
        e:append("tag does not exist: %s", src.tag)
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true, nil
end

function svn.has_working_copy(info, sname)
    return true
end

--- create a table of lines for display
-- @param info the info structure
-- @param sourcename string
-- @return a table, nil on error
-- @return an error string on failure
function svn.display(info, sourcename)
    local src = info.sources[sourcename]
    local rc, e
    rc, e = svn.validate_source(info, sourcename)
    if not rc then
        return false, e
    end
    local display = {}
    display[1] = string.format("type       = %s", src.type)
    display[2] = string.format("server     = %s", src.server)
    display[3] = string.format("remote     = %s", src.location)
    display[4] = string.format("branch     = %s", src.branch)
    display[5] = string.format("tag        = %s", src.tag)
    display[6] = string.format("working    = %s", src.working)
    local i = 7
    for _,l in pairs(src.licences) do
        display[i] = string.format("licence    = %s", l)
        i = i + 1
    end
    return display
end

--- calculate an id for a source
-- @param info
-- @param sourcename
-- @param source_set
function svn.sourceid(info, sourcename, source_set)
    local src = info.sources[sourcename]
    local rc, re
    local hc, surl, svnurl, argv, out, svnrev

    rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    if not src.sourceid then
        src.sourceid = {}
    end

    src.sourceid["working-copy"] = "working-copy"
    if src.sourceid[source_set] then
        return true, nil, src.sourceid[source_set]
    end

    hc = hash.hash_start()
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

    -- svn specific
    surl, re = info.cache:remote_url(src.server, src.location)
    if not surl then
        return false, re
    end

    svnurl, re = mksvnurl(surl)
    if not svnurl then
        return false, re
    end

    hash.hash_line(hc, src.server)
    hash.hash_line(hc, src.location)

    if source_set == "tag" then
        hash.hash_line(hc, src.tag)
        argv = { "info", svnurl.."/"..src.tag }
    elseif source_set == "branch" then
        hash.hash_line(hc, src.branch)
        argv = { "info", svnurl.."/"..src.branch }
    elseif source_set == "lazytag" then
        return false, err.new("svn source does not support lazytag mode")
    else
        return false,
            err.new("svn sourceid can't handle source_set %q", source_set)
    end

    rc, re, out = svn_tool(argv)
    if not rc then
        return false,
            err.new("retrieving revision for tag or branch failed"):cat(re)
    end

    svnrev = string.match(out, "Last Changed Rev: (%d+)")
    if not svnrev or string.len(svnrev) == 0 then
        return false, err.new("could not find SVN revision")
    end
    hash.hash_line(hc, svnrev)

    src.sourceid[source_set] = hash.hash_finish(hc)

    return true, nil, src.sourceid[source_set]
end

function svn.toresult(info, sourcename, sourceset, directory)
    -- <directory>/source/<sourcename>.tar.gz
    -- <directory>/makefile
    -- <directory>/licences
    local rc, re
    local e = err.new("converting result")
    rc, re = scm.generic_source_check(info, sourcename, true)
    if not rc then
        return false, e:cat(re)
    end
    local src = info.sources[sourcename]
    -- write makefile
    local makefile = "makefile"
    local source = "source"
    local sourcedir = e2lib.join(directory, source)
    local archive = string.format("%s.tar.gz", sourcename)
    local fname  = e2lib.join(directory, makefile)
    rc, re = e2lib.mkdir_recursive(sourcedir)
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
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, e:cat(re)
    end

    rc, re = svn.prepare_source(info, sourcename, sourceset, tmpdir)
    if not rc then
        return false, e:cat(re)
    end
    -- create a tarball in the final location
    local archive = string.format("%s.tar.gz", src.name)
    rc, re = e2lib.tar({ "-C", tmpdir ,"-czf", sourcedir .. "/" .. archive,
    sourcename })
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
    e2lib.rmtempdir(tmpdir)
    return true, nil
end

function svn.update(info, sourcename)
    local rc, re = svn.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local e = err.new("updating source '%s' failed", sourcename)
    local src = info.sources[ sourcename ]
    local working = e2lib.join(info.root, src.working)
    rc, re = e2lib.chdir(working)
    if not rc then
        return false, e:cat(re)
    end
    rc, re = svn_tool({ "update", })
    if not rc then
        return false, e:cat(re)
    end
    return true
end

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
function svn.validate_source(info, sourcename)
    local rc, re = scm.generic_source_validate(info, sourcename)
    if not rc then
        -- error in generic configuration. Don't try to go on.
        return false, re
    end
    local src = info.sources[ sourcename ]
    if not src.sourceid then
        src.sourceid = {}
    end
    local e = err.new("in source %s:", sourcename)
    rc, re = scm.generic_source_default_working(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    e:setcount(0)
    if not src.server then
        e:append("source has no `server' attribute")
    end
    if not src.licences then
        e:append("source has no `licences' attribute")
    end
    if not src.location then
        e:append("source has no `location' attribute")
    end
    if src.remote then
        e:append("source has `remote' attribute, not allowed for svn sources")
    end
    if not src.branch then
        e:append("source has no `branch' attribute")
    end
    if type(src.tag) ~= "string" then
        e:append("source has no `tag' attribute or tag attribute has wrong type")
    end
    if type(src.workingcopy_subdir) ~= "string" then
        e2lib.warnf("WDEFAULT", "in source %s", sourcename)
        e2lib.warnf("WDEFAULT",
        " workingcopy_subdir defaults to the branch: %s", src.branch)
        src.workingcopy_subdir = src.branch
    end
    if not src.working then
        e:append("source has no `working' attribute")
    end
    local rc, re = tools.check_tool("svn")
    if not rc then
        e:cat(re)
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true, nil
end

strict.lock(svn)

-- vim:sw=4:sts=4:et:
