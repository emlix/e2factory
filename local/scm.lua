--- SCM Interface
-- @module local.scm

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

local scm = {}
package.loaded["scm"] = scm
local err = require("err")
local strict = require("strict")
local source = require("source")

-- scm modules
local scms = {}

-- scm interfaces
local intf = {}

--- register a scm module
-- @param scmname string: scm name
-- @param mod the module
-- @return bool
-- @return an error object on failure
function scm.register(scmname, mod)
    local e, rc, re, func

    e = err.new("error registering scm")
    if scms[scmname] then
        return false, e:append("scm with that name exists")
    end
    scms[scmname] = {}
    for name,_ in pairs(intf) do
        -- interface function may not exist in this particular module,
        -- resulting in a generic error message if called.
        if strict.islocked(mod) then
            strict.unlock(mod)
            func = mod[name]
            strict.lock(mod)
        else
            func = mod[name]
        end

        if func then
            rc, re = scm.register_function(scmname, name, func)
            if not rc then
                return false, e:cat(re)
            end
        end
    end
    return true
end

--- register a new scm interface
-- @param name string: interface name
-- @return bool
-- @return an error object on failure
function scm.register_interface(name)
    local e = err.new("registering scm interface failed")
    if intf[name] then
        return false, e:append(
        "interface with that name exists: %s", name)
    end

    local function func(info, sourcename, ...)
        assert(info)
        assert(sourcename)

        local typ
        local rc, re, e

        e = err.new("calling scm operation failed")

        typ = source.sources[sourcename]:get_type()
        if not scms[typ] then
            return false, e:append("no such source type: %s", tostring(typ))
        end
        local f = scms[typ][name]
        if not f then
            e:append("%s() is not implemented for source type: %s", name, typ)
            return false, e
        end
        return f(info, sourcename, ...)
    end

    intf[name] = true

    -- we have lots of calls like scm.<function>(...). Register the interface
    -- function in the scm module to support those calls.
    if strict.islocked(scm) then
        strict.declare(scm, {name})
    end
    scm[name] = func

    return true
end

--- Register a new SCM function (accessible through the scm interface).
-- @param scmtype SCM type (string).
-- @param name string: interface name
-- @param func function: interface function
-- @return True on success, false on error.
-- @return Error object on failure.
function scm.register_function(scmtype, name, func)
    local e = err.new("registering scm function failed")
    if not scms[scmtype] then
        return false, e:append("no scm type by that name: %s", type)
    end
    if not intf[name] then
        return false, e:append("no scm interface by that name: %s", name)
    end
    if scms[scmtype][name] then
        return false, e:append("scm function exists: %s.%s", type, name)
    end
    if type(func) ~= "function" then
        return false, e:append("scm function argument is not a function")
    end

    scms[scmtype][name] = func

    return true
end

--- do some consistency checks required before using sources
-- @param info
-- @param sourcename string: source name
-- @param require_workingcopy bool: return error if the workingcopy is missing
-- @return bool
-- @return an error object on failure
function scm.generic_source_check(info, sourcename, require_workingcopy)
    local rc, re

    rc, re = scm.working_copy_available(info, sourcename)
    if (not rc) and require_workingcopy then
        return false, err.new("working copy is not available")
    end
    rc, re = scm.check_workingcopy(info, sourcename)
    if not rc then
        return false, re
    end
    return true, nil
end

scm.register_interface("toresult")
scm.register_interface("prepare_source")
scm.register_interface("fetch_source")
scm.register_interface("update")
scm.register_interface("check_workingcopy")
scm.register_interface("working_copy_available")
scm.register_interface("has_working_copy")

return strict.lock(scm)

-- vim:sw=4:sts=4:et:
