--- e2-dsort command
-- @module local.e2-dsort

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
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local e2option = require("e2option")

local function e2_dsort(arg)
    local e2project
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    e2project = e2tool.e2project()
    e2project:init_project("dsort")

    local opts, re = e2option.parse(arg)
    if not opts then
        error(re)
    end

    rc, re = e2project:load_project()
    if not rc then
        error(re)
    end

    local d = e2tool.dsort()
    if d then
        for _,dep in ipairs(d) do
            console.infonl(dep)
        end
    end
end

local pc, re = e2lib.trycall(e2_dsort, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
