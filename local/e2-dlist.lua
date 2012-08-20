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
require("e2build")
local e2option = require("e2option")

e2lib.init()
local info, re = e2tool.local_init(nil, "dlist")
if not info then
    e2lib.abort(re)
end

e2option.documentation = [[
usage: e2-dlist [<option> | <result> ...]

for the given result show those results which it depends on
]]

e2option.flag("recursive", "show indirect dependencies, too")
local opts, arguments = e2option.parse(arg)

if #arguments == 0 then
    e2lib.abort("no result given - enter `e2-dlist --help' for usage information")
elseif #arguments ~= 1 then e2option.usage(1) end

local result = arguments[1]
info, re = e2tool.collect_project_info(info)
if not info then
    e2lib.abort(re)
end

if not info.results[ result ] then
    e2lib.abort("no such result: ", result)
end

local dep, re
if opts.recursive then
    dep, re = e2tool.dlist_recursive(info, result)
else
    dep, re = e2tool.dlist(info, result)
end
if not dep then
    e2lib.abort(re)
end

for i = 1, #dep do print(dep[i]) end

e2lib.finish()

-- vim:sw=4:sts=4:et:
