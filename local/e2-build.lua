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
require("e2tool")
local e2build = require("e2build")
local err = require("err")
local e2option = require("e2option")
local scm = require("scm")

e2lib.init()
local info, re = e2tool.local_init(nil, "build")
if not info then
    e2lib.abort(re)
end

e2option.documentation = [[
usage: e2-build [<option> | <result> ...]

build results from repository or local sources.
]]

e2option.flag("all", "build all results (default unless for working copy)")
policy.register_commandline_options()
e2option.flag("branch-mode", "build selected results in branch mode")
e2option.flag("wc-mode", "build selected results in working-copy mode")
e2option.flag("force-rebuild", "force rebuilding even if a result exists [broken]")
e2option.flag("playground", "prepare environment but do not build")
e2option.flag("keep", "do not remove chroot environment after build")
e2option.flag("buildnumber", "use real build numbers")
e2option.flag("buildid", "display buildids and exit")
-- cache is not yet initialized when parsing command line options, so
-- remember settings in order of appearance, and perform settings as soon
-- as the cache is initialized.
local writeback = {}
local function disable_writeback(server)
    table.insert(writeback, { set = "disable", server = server })
end
local function enable_writeback(server)
    table.insert(writeback, { set = "enable", server = server })
end
local function perform_writeback_settings(writeback)
    local rc, re
    local enable_msg = "enabling writeback for server '%s' [--enable-writeback]"
    local disable_msg =
    "disabling writeback for server '%s' [--disable-writeback]"
    for _,set in ipairs(writeback) do
        if set.set == "disable" then
            e2lib.logf(3, disable_msg, set.server)
            rc, re = info.cache:set_writeback(set.server, false)
            if not rc then
                local e = err.new(disable_msg, set.server)
                e2lib.abort(e:cat(re))
            end
        elseif set.set == "enable" then
            e2lib.logf(3, enable_msg, set.server)
            rc, re = info.cache:set_writeback(set.server, true)
            if not rc then
                local e = err.new(enable_msg, set.server)
                e2lib.abort(e:cat(re))
            end
        end
    end
end
e2option.option("disable-writeback", "disable writeback for server", nil,
disable_writeback, "SERVER")
e2option.option("enable-writeback", "enable writeback for server", nil,
enable_writeback, "SERVER")

local opts, arguments = e2option.parse(arg)

-- get build mode from the command line
local build_mode = policy.handle_commandline_options(opts, true)
if not build_mode then
    e2lib.abort("no build mode given")
end

info, re = e2tool.collect_project_info(info)
if not info then
    e2lib.abort(re)
end
perform_writeback_settings(writeback)
local rc, re = e2tool.check_project_info(info)
if not rc then
    e2lib.abort(re)
end

-- apply the standard build mode to all results
for _,res in pairs(info.results) do
    res.build_mode = build_mode
end

-- handle result selection
local results = {}
if opts["all"] then
    for r,_ in pairs(info.results) do
        table.insert(results, r)
    end
elseif #arguments > 0 then
    for i,r in ipairs(arguments) do
        table.insert(results, r)
    end
end

-- handle command line flags
local build_mode = nil
if opts["branch-mode"] and opts["wc-mode"] then
    e = err.new("--branch-mode and --wc-mode are mutually exclusive")
    e2lib.abort(e)
end
if opts["branch-mode"] then
    -- selected results get a special build mode
    build_mode = policy.default_build_mode["branch"]
end
if opts["wc-mode"] then
    build_mode = policy.default_build_mode["working-copy"]
end
local playground = opts["playground"]
if playground then
    if opts.release then
        e2lib.abort("--release and --playground are mutually exclusive")
    end
    if opts.all then
        e2lib.abort("--all and --playground are mutually exclusive")
    end
    if #arguments ~= 1 then
        e2lib.abort("please select one single result for the playground")
    end
end
local force_rebuild = opts["force-rebuild"]
local request_buildno = opts["request-buildno"]
local keep_chroot = opts["keep"]

-- apply flags to the selected results
rc, re = e2tool.select_results(info, results, force_rebuild, request_buildno,
keep_chroot, build_mode, playground)
if not rc then
    e2lib.abort(re)
end

-- a list of results to build, topologically sorted
local sel_res = {}
if #results > 0 then
    local re
    sel_res, re = e2tool.dlist_recursive(info, results)
    if not sel_res then
        e2lib.abort(re)
    end
else
    local re
    sel_res, re = e2tool.dsort(info)
    if not sel_res then
        e2lib.abort(re)
    end
end

rc, re = e2tool.print_selection(info, sel_res)
if not rc then
    e2lib.abort(re)
end

if opts.release and not e2tool.e2_has_fixed_tag(info) then
    e2lib.abort("Failure: e2 is on pseudo tag while building in release mode.")
end

if opts["buildnumber"] then
    e2lib.logf(1, "setting up build numbers")
    local rc, re
    rc, re = e2tool.buildnumber_read(info)
    if not rc then
        e2lib.abort(re)
    end
    rc, re = e2tool.buildnumber_mergetoresults(info)
    if not rc then
        e2lib.abort(re)
    end
end

-- calculate buildids for selected results
for _,r in ipairs(sel_res) do
    local bid, re = e2tool.buildid(info, r)
    if not bid then
        e2lib.abort(re)
    end
end

if opts["buildid"] then
    for _,r in ipairs(sel_res) do
        print(string.format("%-20s [%s]", r, e2tool.buildid(info, r)))
    end
    e2lib.finish()
end

-- build
local rc, re = e2build.build_results(info, sel_res)
if not rc then
    e2lib.abort(re)
end
e2lib.finish()

-- vim:sw=4:sts=4:et:
