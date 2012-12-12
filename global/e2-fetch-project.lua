--- e2-fetch-project command
-- @module global.e2-fetch-project

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

local e2lib = require("e2lib")
local e2option = require("e2option")
local generic_git = require("generic_git")
local cache = require("cache")
local err = require("err")
require("buildconfig")

e2lib.init()
local e = err.new("fetching project failed")
local doc = [[
usage: e2-fetch-project [<option> ...] [<server>:]<location> [<destination>]

fetch the project located in server:location to a directory given in
<destination>.
<server> defaults to '%s'.
]]
e2option.documentation = string.format(doc,
e2lib.globals.default_projects_server)

e2option.option("branch", "retrieve a specific project branch")
e2option.option("tag", "retrieve a specific project tag")

local opts, arguments = e2option.parse(arg)
local rc, re = e2lib.read_global_config()
if not rc then
    e2lib.abort(e:cat(re))
end
e2lib.init2()

-- get the global configuration
local config = e2lib.get_global_config()

-- setup cache
local scache, re = e2lib.setup_cache()
if not scache then
    e2lib.abort(e:cat(re))
end

-- standard global tool setup finished

if #arguments < 1 then
    e2lib.abort("specify path to a project to fetch")
end
if #arguments > 2 then
    e2lib.abort("too many arguments")
end

local sl, re = e2lib.parse_server_location(arguments[1],
e2lib.globals.default_projects_server)
if not sl then
    e2lib.abort(e:cat(re))
end

local p = {}
p.server = sl.server
p.location = sl.location
p.name = e2lib.basename(p.location)
if arguments[2] then
    p.destdir = arguments[2]
else
    p.destdir = p.name
end
if opts["branch"] then
    p.branch = opts["branch"]
else
    p.branch = nil
end
if opts["tag"] then
    p.tag = opts["tag"]
else
    p.tag = nil
end

-- fetch project descriptor file
local tmpdir = e2lib.mktempdir()
local location = string.format("%s/version", p.location)
local rc, re = cache.fetch_file(scache, p.server, location, tmpdir, nil,
{ cache = false })
if not rc then
    e2lib.abort(e:cat(re))
end

-- read the version from the first line
local version_file = string.format("%s/version", tmpdir)
local line, re = e2lib.read_line(version_file)
if not line then
    e2lib.abort(e:cat(re))
end
e2lib.rmtempdir()

local v = tonumber(line:match("[0-9]+"))
if not v or v < 1 or v > 2 then
    e2lib.abort(e:append("unhandled project version"))
end

-- version is 1 or 2

-- clone the git repository
local location = string.format("%s/proj/%s.git", p.location, p.name)
local skip_checkout = false
local destdir = p.destdir
local rc, re = generic_git.git_clone_from_server(scache, p.server, location,
p.destdir, skip_checkout)
if not rc then
    e2lib.abort(e:cat(re))
end

e2lib.chdir(p.destdir)

-- checkout the desired branch, if a branch was given
if p.branch then
    local e = e:append("checking out branch failed: %s", p.branch)
    local args = string.format("-n1 refs/heads/%s", p.branch)
    local rc, re = e2lib.git(nil, "rev-list", args)
    if not rc then
        local args = string.format(
        "--track -b '%s' 'origin/%s'", p.branch, p.branch)
        local rc, re = e2lib.git(nil, "checkout", args)
        if not rc then
            e2lib.abort(e:cat(re))
        end
    end
end

-- checkout the desired tag, if a tag was given
if p.tag then
    local e = e:append("checking out tag failed: %s", p.tag)
    if p.branch then
        -- branch and tag were specified. The working branch was created above.
        -- Warn and go on checking out the tag...
        e2lib.warnf("WOTHER",
        "switching to tag '%s' after checking out branch '%s'",
        p.tag, p.branch)
    end
    local args = string.format("'refs/tags/%s'", p.tag)
    local rc, re = e2lib.git(nil, "checkout", args)
    if not rc then
        e2lib.abort(e:cat(re))
    end
end

-- write project location file
local file = ".e2/project-location"
local data = string.format("%s\n", p.location)
local rc, re = e2lib.write_file(file, data)
if not rc then
    e2lib.abort(e:cat(re))
end

-- write version file
local rc, re = e2lib.write_file(e2lib.globals.global_interface_version_file,
string.format("%d\n", v))

-- call e2-install-e2
local e2_install_e2 = string.format("%s %s/e2-install-e2",
    e2lib.shquote(buildconfig.LUA), e2lib.shquote(buildconfig.TOOLDIR))
rc, re = e2lib.callcmd_log(e2_install_e2)
if rc ~= 0 then
    e2lib.abort(err.new("installing local e2 failed"))
end
e2lib.finish()

-- vim:sw=4:sts=4:et:
