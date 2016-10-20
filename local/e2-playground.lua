--- e2-playground command
-- @module local.e2-playground

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

local console = require("console")
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local policy = require("policy")
local result = require("result")

local function e2_playground(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local info, re = e2tool.local_init(nil, "playground")
    if not info then
        error(re)
    end

    local e = err.new("entering playground failed")
    local rc, re

    e2option.option("command","execute command in chroot")
    e2option.flag("runinit","run init files automatically")
    e2option.flag("showpath", "prints the path of the build directory inside the chroot to stdout" )

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    -- get build mode from the command line
    local build_mode, re = policy.handle_commandline_options(opts, true)
    if not build_mode then
        error(re)
    end
    info, re = e2tool.collect_project_info(info)
    if not info then
        error(re)
    end

    if #arguments ~= 1 then
        e2option.usage(1)
    end

    local res = result.results[arguments[1]]
    if not res then
        error(err.new("unknown result: %s", arguments[1]))
    end

    -- apply the standard build mode to all results
    for _,res in pairs(result.results) do
        res:build_mode(build_mode)
    end

    local bc
    bc, re = res:buildconfig()
    if not bc then
        error(re)
    end

    if opts.showpath then
        if not e2lib.isfile(bc.chroot_marker) then
            error(err.new("playground does not exist"))
        end
        console.infonl(bc.c)
        e2lib.finish(0)
    end

    local settings = e2build.playground_settings_class:new()

    -- interactive mode, use bash profile
    local out = {}
    table.insert(out, string.format("export TERM='%s'\n",
        e2lib.globals.osenv["TERM"]))
    table.insert(out, string.format("export HOME=/root\n"))

    if opts.runinit then
        table.insert(out, string.format("source %s/script/%s\n",
            bc.Tc, bc.buildrc_file))
    else
        table.insert(out, string.format(
            "function runinit() { source %s/script/%s; }\n",
            bc.Tc, bc.buildrc_file))
        table.insert(out, string.format("source %s/script/%s\n",
            bc.Tc, bc.buildrc_noinit_file))
    end
    settings:profile(table.concat(out))

    local command
    if opts.command then
        settings:command(
            string.format("/bin/bash --rcfile '%s' -c '%s'", bc.profile,
            opts.command))
    else
        settings:command(string.format("/bin/bash --rcfile '%s'", bc.profile))
    end

    e2lib.logf(2, "entering playground for %s", res:get_name())

    if not opts.runinit then
        e2lib.log(2, "type `runinit' to run the init files")
    end

    res:build_settings(settings)
    rc, re = res:build_process():build(res)
    if not rc then
        error(e:cat(re))
    end
end

local pc, re = e2lib.trycall(e2_playground, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
