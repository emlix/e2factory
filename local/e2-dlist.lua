--- e2-dlist command
-- @module local.e2-dlist

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
local e2option = require("e2option")
local e2tool = require("e2tool")
local err = require("err")
local result = require("result")

local function e2_dlist(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local info, re = e2tool.local_init(nil, "dlist")
    if not info then
        error(re)
    end

    e2option.flag("recursive", "show indirect dependencies, too")
    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    if #arguments == 0 then
        error(err.new(
            "no result given - enter `e2-dlist --help' for usage information"))
    elseif #arguments ~= 1 then e2option.usage(1) end

    local resultname = arguments[1]
    info, re = e2tool.collect_project_info(info)
    if not info then
        error(re)
    end

    if not result.results[resultname] then
       error(err.new("no such result: %s", resultname))
    end

    local dep, re
    if opts.recursive then
        dep, re = e2tool.dlist_recursive(resultname)
    else
        dep, re = result.results[resultname]:depends_list():totable_sorted()
    end
    if not dep then
        error(re)
    end

    for _,d in ipairs(dep) do
        console.infonl(d)
    end
end

local pc, re = e2lib.trycall(e2_dlist, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
