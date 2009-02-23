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

-- e2api.lua
-- Use e2 from a Lua program.


e2api = {}

function e2api.init(project_path)
  package.path = project_path .. "/.e2/lib/e2/?.lc;" ..
    project_path .. "/.e2/lib/e2/?.lua;" .. package.path
  package.cpath = project_path .. "/.e2/lib/e2/?.so;" .. package.cpath
  e2api.rpath = project_path
  require("e2local")
  e2lib.abort_with_message = error
end

function e2api.info()
  return e2tool.collect_project_info(e2api.rpath)
end
