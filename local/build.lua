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

-- e2-build -*- Lua -*-

require("e2local")
e2lib.init()

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

local opts = e2option.parse(arg)

-- get build mode from the command line
local build_mode = policy.handle_commandline_options(opts, true)
if not build_mode then
	e2lib.abort("no build mode given")
end

local info, re = e2tool.collect_project_info()
if not info then
  e2lib.abort(re)
end
local rc, re = e2tool.check_project_info(info)
if not rc then
  e2lib.abort(re)
end

e2lib.log_invocation(info, arg)

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
elseif #opts.arguments > 0 then
	for i,r in ipairs(opts.arguments) do
		table.insert(results, r)
	end
end

-- handle command line flags
local build_mode = nil
if opts["branch-mode"] and opts["wc-mode"] then
	e = new_error("--branch-mode and --wc-mode are mutually exclusive")
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
  if #opts.arguments ~= 1 then
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
	sel_res = e2tool.dlist_recursive(info, results)
else
	sel_res = e2tool.dsort(info)
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

-- calculate build ids ids
e2tool.calc_buildids(info)

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

