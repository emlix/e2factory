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

-- e2-buildnumbers -*- Lua -*-

require("e2local")
e2lib.init()

e2option.documentation = [[
usage:
e2-buildnumbers [--no-sync]
]]

policy.register_commandline_options()
e2option.flag("no-sync", "do not synchronize with the server")

local opts = e2option.parse(arg)
local info, re = e2tool.collect_project_info()
if not info then
  e2lib.abort(re)
end
local rc, re = e2tool.check_project_info(info)
if not rc then
  e2lib.abort(re)
end

-- get build mode from the command line
local build_mode = policy.handle_commandline_options(opts, true)
if not build_mode then
	e2lib.abort("no build mode given")
end
-- apply the standard build mode to all results
for _,res in pairs(info.results) do
	res.build_mode = build_mode
end

e2lib.log_invocation(info, arg)

-- read build numbers,
-- merge to results,
-- flush buildids,
-- calculate buildids,
-- merge back,
-- request new build numbers,
-- write new build numbers

local rc, re
rc, re = e2tool.buildnumber_read(info)
if not rc then
	e2lib.abort(re)
end
rc, re = e2tool.buildnumber_mergetoresults(info)
if not rc then
	e2lib.abort(re)
end
-- recalculate build ids ids
e2tool.flush_buildids(info)
e2tool.calc_buildids(info)
rc, re = e2tool.buildnumber_mergefromresults(info)
if not rc then
	e2lib.abort(re)
end
if opts["no-sync"] then
	rc, re = e2tool.buildnumber_request_local(info)
else
	rc, re = e2tool.buildnumber_request(info)
end
if not rc then
	e2lib.abort(re)
end
rc, re = e2tool.buildnumber_write(info)
if not rc then
	e2lib.abort(re)
end
e2tool.buildnumber_display(info.build_numbers, 1)
e2lib.finish()
