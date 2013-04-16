--- e2-playground command
-- @module local.e2-playground

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

-- playground - enter existing chroot(1) environment -*- Lua -*-

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local e2build = require("e2build")
local err = require("err")
local e2option = require("e2option")
local policy = require("policy")

local function e2_playground(arg)
    e2lib.init()
    local info, re = e2tool.local_init(nil, "playground")
    if not info then
        return false, re
    end

    local e = err.new("entering playground failed")
    local rc, re

    e2option.option("command","execute command in chroot")
    e2option.flag("runinit","run init files automatically")
    e2option.flag("showpath", "prints the path of the build directory inside the chroot to stdout" )

    local opts, arguments = e2option.parse(arg)
    -- get build mode from the command line
    local build_mode, re = policy.handle_commandline_options(opts, true)
    if not build_mode then
        return false, re
    end
    info, re = e2tool.collect_project_info(info)
    if not info then
        return false, re
    end
    local rc, re = e2tool.check_project_info(info)
    if not rc then
        return false, re
    end

    if #arguments ~= 1 then
        e2option.usage(1)
    end

    local r = arguments[1]

    -- apply the standard build mode to all results
    for _,res in pairs(info.results) do
        res.build_mode = build_mode
    end
    rc, re = e2build.build_config(info, r, {})
    if not rc then
        return false, e:cat(re)
    end
    if not e2build.chroot_exists(info, r) then
        return false, err.new("playground does not exist")
    end
    if opts.showpath then
        print(info.results[r].build_config.c)
        e2lib.finish(0)
    end
    -- interactive mode, use bash profile
    local res = info.results[r]
    local bc = res.build_config
    local profile = string.format("%s/%s", bc.c, bc.profile)
    local f, msg = io.open(profile, "w")
    if not f then
        return false, e:cat(msg)
    end
    f:write(string.format("export TERM='%s'\n", e2lib.globals.osenv["TERM"]))
    f:write(string.format("export HOME=/root\n"))
    if opts.runinit then
        f:write(string.format("source %s/script/%s\n", bc.Tc, bc.buildrc_file))
    else
        f:write(string.format("function runinit() { source %s/script/%s; }\n",
            bc.Tc, bc.buildrc_file))
            f:write(string.format("source %s/script/%s\n", bc.Tc,
            bc.buildrc_noinit_file))
    end
    f:close()
    local command = nil
    if opts.command then
        command = string.format("/bin/bash --rcfile '%s' -c '%s'", bc.profile,
        opts.command)
    else
        command = string.format("/bin/bash --rcfile '%s'", bc.profile)
    end
    e2lib.logf(2, "entering playground for %s", r)
    if not opts.runinit then
        e2lib.log(2, "type `runinit' to run the init files")
    end
    rc, re = e2build.enter_playground(info, r, command)
    if not rc then
        return false, re
    end

    return true
end

local rc, re = e2_playground(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
