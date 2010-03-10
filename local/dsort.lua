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

-- dsort -*- Lua -*-

require("e2local")
require("e2tool")
require("e2build")
e2lib.init()
local info, re = e2tool.local_init(nil, "dsort")
if not info then
  e2lib.abort(re)
end

e2option.documentation = [[
usage: e2-dsort

lists all results sorted by dependency
]]

e2option.parse(arg)

info, re = e2tool.collect_project_info(info)
if not info then
  e2lib.abort(re)
end

local d = e2tool.dsort(info)
if d then
  for i = 1, #d do print(d[i]) end
end

e2lib.finish()

