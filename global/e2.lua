--- e2 command
-- @module global.e2

-- Copyright (C) 2007-2016 emlix GmbH, see file AUTHORS
--
-- This file is part of e2factory, the emlix embedded build system.
-- For more information see http://www.e2factory.org
--
-- e2factory is a registered trademark of emlix GmbH.
--
-- e2factory is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details.

local buildconfig = require("buildconfig")
local console = require("console")
local e2lib = require("e2lib")
local e2option = require("e2option")
local err = require("err")

local function e2(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
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
            error(re)
        end

        if #opts == 0 then
            e2option.usage(1)
        end
        return nil, 0
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
        error(err.new("%s is not a global tool and we're not in a "..
            "project environment", e2call.toolname))
    else
        error(err.new("%s is neither local nor global tool", e2call.toolname))
    end

    table.insert(cmd, e2call.tool)
    for i,a in ipairs(arg) do
        if i >= e2call.argindex then
            table.insert(cmd, a)
        end
    end

    e2lib.logf(3, "calling %s", e2call.tool)
    e2lib.signal_install()
    rc, re = e2lib.callcmd(cmd, {}, nil, env, true)
    if not rc then
        error(re)
    end
    local sig
    rc, re, sig = e2lib.wait_pid_delete(rc)
    if not rc then
        error(re)
    end

    e2lib.logf(4, "%s returned: exit status: %d pid: %d signal: %d",
        e2call.tool, rc, re, sig or 0)

    return nil, rc
end

local pc, re, rc = e2lib.trycall(e2, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(rc)

-- vim:sw=4:sts=4:et:
