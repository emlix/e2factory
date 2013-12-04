--- e2-install-e2 command
-- @module global.e2-install-e2

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
local eio = require("eio")
local generic_git = require("generic_git")
local err = require("err")
local buildconfig = require("buildconfig")

local function e2_install_e2(arg)
    local rc, re = e2lib.init()
    if not rc then
        return false, re
    end

    -- When called from e2-fetch-project, we inherit its arg vector.
    -- Parse the options but do nothing with them.
    e2option.option("branch", "ignored option, do not document")
    e2option.option("tag", "ignored option, do not document")

    local opts, arguments = e2option.parse(arg)
    if not opts then
        return false, arguments
    end

    local root = e2lib.locate_project_root()
    if not root then
        return false, err.new("can't locate project root.")
    end

    rc, re = e2lib.init2()
    if not rc then
        return false, re
    end

    local e = err.new("e2-install-e2 failed")

    local config, re = e2lib.get_global_config()
    if not config then
        return false, re
    end

    local servers = config.servers
    if not servers then
        return false, err.new("no servers configured in global config")
    end

    local scache, re = e2lib.setup_cache()
    if not scache then
        return false, e:cat(re)
    end

    -- standard global tool setup finished

    if #arguments > 0 then
        e2option.usage(1)
    end

    -- change to the project root directory
    rc, re = e2lib.chdir(root)
    if not rc then
        return false, e:cat(re)
    end

    -- read the version from the first line
    local line, re = eio.file_read_line(
        e2lib.globals.global_interface_version_file)
    if not line then
        return false, e:cat(re)
    end

    local v = tonumber(line:match("[0-9]+"))
    if not v or v < 1 or v > 2 then
        return false, e:append("unhandled project version")
    end

    -- version is 1 or 2

    -- remove the old e2 source, installation and plugins, if it exists
    for _,dir in ipairs({".e2/e2",  ".e2/bin", ".e2/lib", ".e2/plugins"}) do
        if e2lib.exists(dir) then
            rc, re = e2lib.unlink_recursive(dir)
            if not rc then
                return false, e:cat(re)
            end
        end
    end

    e2lib.logf(2, "installing local tools")

    local extensions, re = e2lib.read_extension_config(root)
    if not extensions then
        return false, e:cat(re)
    end

    local ef = e2lib.join(root, e2lib.globals.e2version_file)
    local s, re = eio.file_read_line(ef)
    local branch, tag = s:match("(%S+) (%S+)")
    if not branch or not tag then
        e:cat(re)
        return false, e:cat(err.new("cannot parse e2 version"))
    end
    local ref
    if tag == "^" then
        e2lib.warnf("WOTHER", "using e2 version by branch")
        if branch:match("/") then
            ref = branch
        else
            ref = string.format("remotes/origin/%s", branch)
        end
    else
        ref = string.format("refs/tags/%s", tag)
    end

    rc, re = e2lib.chdir(".e2")
    if not rc then
        return false, e:cat(re)
    end

    -- checkout e2factory itself
    local server = config.site.e2_server
    local location = config.site.e2_location
    local destdir = e2lib.join(root, ".e2/e2")
    e2lib.logf(2, "fetching e2factory (ref %s)", ref)
    rc, re = generic_git.git_clone_from_server(scache, server, location,
        destdir, false)
    if not rc then
        return false, e:cat(re)
    end
    e2lib.chdir(destdir)

    -- change to requested branch or tag
    rc, re = generic_git.git_checkout1(destdir, ref)
    if not rc then
        return false, e:cat(re)
    end

    for _,ex in ipairs(extensions) do
        -- change to the e2factory extensions directory
        rc, re = e2lib.chdir(root .. "/.e2/e2/extensions")
        if not rc then
            return false, e:cat(re)
        end
        local ref
        if ex.ref:match("/") then
            ref = ex.ref
        else
            ref = string.format("refs/tags/%s", ex.ref)
        end
        e2lib.logf(2, "fetching extension: %s (%s)", ex.name, ref)
        local server = config.site.e2_server
        local location = string.format("%s/%s.git", config.site.e2_base, ex.name)
        local destdir = e2lib.join(root, ".e2/e2/extensions", ex.name)

        if e2lib.exists(destdir) then
            rc, re = e2lib.unlink_recursive(destdir)
            if not rc then
                return false, e:cat(re)
            end
        end

        rc, re = generic_git.git_clone_from_server(scache, server, location,
            destdir, false)
        if not rc then
            return false, e:cat(re)
        end
        e2lib.chdir(destdir)

        rc, re = generic_git.git_checkout1(destdir, ref)
        if not rc then
            return false, e:cat(re)
        end
    end

    -- build and install
    e2lib.logf(2, "building e2factory")
    rc, re = e2lib.chdir(root .. "/.e2/e2")
    if not rc then
       return false, e:cat(re)
    end
    local cmd = {
        buildconfig.MAKE,
        "PREFIX="..buildconfig.PREFIX,
        "BINDIR="..buildconfig.BINDIR,
        "local",
        "install-local",
    }

    rc, re = e2lib.callcmd_log(cmd)
    if not rc or rc ~= 0 then
        return false, e:cat(re)
    end

    return true
end

local rc, re = e2_install_e2(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
