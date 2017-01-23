--- e2-build-numbers command.
-- This command was removed in e2factory 2.3.13.
-- @module local.e2-build-numbers

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

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")

local function e2_build_numbers(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    rc, re = e2tool.local_init(nil, "build-numbers")
    if not rc then
        error(re)
    end

    error(err.new("e2-build-numbers is deprecated and has been removed"))
end

local pc, re = e2lib.trycall(e2_build_numbers, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
