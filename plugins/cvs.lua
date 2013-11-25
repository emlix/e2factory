--- CVS Plugin
-- @module plugins.cvs

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

local cvs = {}
local e2lib = require("e2lib")
local eio = require("eio")
local scm = require("scm")
local hash = require("hash")
local url = require("url")
local tools = require("tools")
local err = require("err")
local strict = require("strict")

plugin_descriptor = {
    description = "CVS SCM Plugin",
    init = function (ctx) scm.register("cvs", cvs) return true end,
    exit = function (ctx) return true end,
}

local function cvs_tool(argv, workdir)
    local rc, re, cvscmd, cvsflags, rsh

    cvscmd, re = tools.get_tool("cvs")
    if not cvscmd then
        return false, re
    end

    cvscmd = { cvscmd }

    cvsflags, re = tools.get_tool_flags("cvs")
    if not cvsflags then
        return false, re
    end

    for _,flag in ipairs(cvsflags) do
        table.insert(cvscmd, flag)
    end

    for _,arg in ipairs(argv) do
        table.insert(cvscmd, arg)
    end

    rsh, re = tools.get_tool("ssh")
    if not rsh then
        return false, re
    end

    return e2lib.callcmd_log(cvscmd, workdir, { CVS_RSH=rsh })
end

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
function cvs.validate_source(info, sourcename)
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
    if type(src.tag) ~= "string" then
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

--- Build the cvsroot string.
-- @param info Info table.
-- @param sourcename Source name.
-- @return CVSROOT string or false on error.
-- @return Error object on failure.
local function mkcvsroot(info, sourcename)
    local cvsroot, src, surl, u, re

    src = info.sources[sourcename]

    surl, re = info.cache:remote_url(src.server, src.cvsroot)
    if not surl then
        return false, e:cat(re)
    end

    u, re = url.parse(surl)
    if not u then
        return false, e:cat(re)
    end

    if u.transport == "file" then
        cvsroot = string.format("/%s", u.path)
    elseif (u.transport == "ssh") or (u.transport == "rsync+ssh") or
        u.transport == "scp" then
        cvsroot = string.format("%s:/%s", u.server, u.path)
    elseif u.transport == "cvspserver" then
        cvsroot = string.format(":pserver:%s:/%s", u.server, u.path)
    else
        return false, err.new("cvs: unhandled transport: %s", u.transport)
    end

    return cvsroot
end

function cvs.fetch_source(info, sourcename)
    local rc, re, e, src, cvsroot, workdir, argv

    rc, re = cvs.validate_source(info, sourcename)
    if not rc then
        return false, re
    end

    e = err.new("fetching source failed: %s", sourcename)
    src = info.sources[sourcename]

    cvsroot, re = mkcvsroot(info, sourcename)
    if not cvsroot then
        return false, e:cat(re)
    end

    -- split the working directory into dirname and basename as some cvs clients
    -- don't like slashes (e.g. in/foo) in their checkout -d<path> argument
    workdir = e2lib.dirname(e2lib.join(info.root, src.working))

    argv = {
        "-d", cvsroot,
        "checkout",
        "-R",
        "-d", e2lib.basename(src.working),
    }

    -- always fetch the configured branch, as we don't know the build mode here.
    -- HEAD has special meaning to cvs
    if src.branch ~= "HEAD" then
        table.insert(argv, "-r")
        table.insert(argv, src.branch)
    end

    table.insert(argv, src.module)

    rc, re = cvs_tool(argv, workdir)
    if not rc or rc ~= 0 then
        return false, e:cat(re)
    end
    return true
end

function cvs.prepare_source(info, sourcename, source_set, buildpath)
    local rc, re, e, src, cvsroot, argv

    rc, re = cvs.validate_source(info, sourcename)
    if not rc then
        return false, re
    end

    e = err.new("cvs.prepare_source failed")
    src = info.sources[sourcename]

    cvsroot, re = mkcvsroot(info, sourcename)
    if not cvsroot then
        return false, re
    end

    if source_set == "tag" or source_set == "branch" then
        argv = {
            "-d", cvsroot,
            "export", "-R",
            "-d", src.name,
            "-r",
        }

        if source_set == "branch" or
            (source_set == "lazytag" and src.tag == "^") then
            table.insert(argv, src.branch)
        elseif (source_set == "tag" or source_set == "lazytag") and
            src.tag ~= "^" then
            table.insert(argv, src.tag)
        else
            return false, e:cat(err.new("source set not allowed"))
        end

        table.insert(argv, src.module)

        rc, re = cvs_tool(argv, buildpath)
        if not rc or rc ~= 0 then
            return false, e:cat(re)
        end
    elseif source_set == "working-copy" then
        rc, re = e2lib.cp(e2lib.join(info.root, src.working),
            e2lib.join(buildpath, src.name), true)
        if not rc then
            return false, e:cat(re)
        end
    else
        return false, err.new("invalid build mode")
    end
    return true, nil
end

function cvs.update(info, sourcename)
    local rc, re, e, src, workdir, argv

    rc, re = cvs.validate_source(info, sourcename)
    if not rc then
        return false, re
    end

    e = err.new("updating source '%s' failed", sourcename)
    src = info.sources[sourcename]

    workdir = e2lib.join(info.root, src.working)

    argv = { "update", "-R" }
    rc, re = cvs_tool(argv, workdir)
    if not rc or rc ~= 0 then
        return false, e:cat(re)
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
    local e = err.new("calculating sourceid failed for source %s",
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
        hash.hash_line(hc, src.tag)
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
    src.sourceid[source_set] = hash.hash_finish(hc)
    return true, nil, src.sourceid[source_set]
end

function cvs.toresult(info, sourcename, sourceset, directory)
    -- <directory>/source/<sourcename>.tar.gz
    -- <directory>/makefile
    -- <directory>/licences
    local rc, re, out
    local e = err.new("converting result")
    rc, re = scm.generic_source_check(info, sourcename, true)
    if not rc then
        return false, e:cat(re)
    end
    local src = info.sources[sourcename]
    -- write makefile
    local makefile = "Makefile"
    local source = "source"
    local sourcedir = string.format("%s/%s", directory, source)
    local archive = string.format("%s.tar.gz", sourcename)
    local fname  = string.format("%s/%s", directory, makefile)
    rc, re = e2lib.mkdir_recursive(sourcedir)
    if not rc then
        return false, e:cat(re)
    end

    out = string.format(
        ".PHONY:\tplace\n\n"..
        "place:\n"..
        "\ttar xzf \"%s/%s\" -C \"$(BUILD)\"\n", source, archive)

    rc, re = eio.file_write(fname, out)
    if not rc then
        return false, e:cat(re)
    end
    -- export the source tree to a temporary directory
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        return false, re
    end

    rc, re = cvs.prepare_source(info, sourcename, sourceset, tmpdir)
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
    local destdir = string.format("%s/licences", directory)
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

function cvs.check_workingcopy(info, sourcename)
    local rc, re
    local e = err.new("checking working copy failed")
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

strict.lock(cvs)

-- vim:sw=4:sts=4:et:
