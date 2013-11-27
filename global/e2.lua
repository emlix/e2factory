--- e2 command
-- @module global.e2

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

local buildconfig = require("buildconfig")
local console = require("console")
local e2lib = require("e2lib")
local e2option = require("e2option")
local err = require("err")

local function e2(arg)
    local rc, re = e2lib.init()
    if not rc then
        return false, re
    end

    e2option.flag("prefix", "print installation prefix",
    function()
        console.infonl(buildconfig.PREFIX)
        e2lib.finish(0)
    end)

    local root = e2lib.locate_project_root()

    local e2call = {}
    e2call.basename = e2lib.basename(arg[0])

    if e2call.basename == "e2" and arg[1] and string.sub(arg[1], 1, 1) ~= "-" then
        e2call.toolname = "e2-" .. arg[1]
        e2call.argindex = 2
    elseif e2call.basename == "e2" then
        e2call.toolname = "e2"
        local opts, re = e2option.parse(arg)
        if not opts then
            return false, re
        end

        if #opts == 0 then
            e2option.usage(1)
        end
        return 0
    else
        e2call.toolname = e2call.basename
        e2call.argindex = 1
    end

    e2call.globaltool = buildconfig.TOOLDIR .. "/" .. e2call.toolname
    if root then
        e2call.localtool = root .. "/.e2/bin/" .. e2call.toolname
    end

    local env, cmd
    cmd = { buildconfig.LUA }
    env = {}

    if e2lib.stat(e2call.globaltool) then
        e2call.tool = e2call.globaltool
        env.LUA_PATH = string.format("%s/?.lua", buildconfig.LIBDIR)
        env.LUA_CPATH= string.format("%s/?.so", buildconfig.LIBDIR)
    elseif root and e2lib.stat(e2call.localtool) then
        e2call.tool = e2call.localtool
        -- Search for .lc files, the local e2 may be of an older version
        env.LUA_PATH = string.format("%s/.e2/lib/e2/?.lc;%s/.e2/lib/e2/?.lua",
            root, root)
        env.LUA_CPATH = string.format("%s/.e2/lib/e2/?.so", root)
    elseif not root then
        return false,
            err.new("%s is not a global tool and we're not in a "..
                "project environment", e2call.toolname)
    else
        return false,
            err.new("%s is neither local nor global tool", e2call.toolname)
    end

    table.insert(cmd, e2call.tool)
    for i,a in ipairs(arg) do
        if i >= e2call.argindex then
            table.insert(cmd, a)
        end
    end

    e2lib.log(3, "calling " .. e2call.tool)

    rc, re = e2lib.callcmd(cmd, {}, nil, env)
    if not rc then
        return false, re
    end

    return rc
end

local rc, re = e2(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(rc)

-- vim:sw=4:sts=4:et:
