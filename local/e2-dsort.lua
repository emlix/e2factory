--- e2-dsort command
-- @module local.e2-dsort

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

local console = require("console")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local e2option = require("e2option")

local function e2_dsort(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local info, re = e2tool.local_init(nil, "dsort")
    if not info then
        error(re)
    end

    local opts, re = e2option.parse(arg)
    if not opts then
        error(re)
    end

    info, re = e2tool.collect_project_info(info)
    if not info then
        error(re)
    end

    local d = e2tool.dsort(info)
    if d then
        for _,dep in ipairs(d) do
            console.infonl(dep)
        end
    end
end

local pc, re = pcall(e2_dsort, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
