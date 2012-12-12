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
local e2lib = require("e2lib")
local err = require("err")
local environment = require("environment")
local strict = require("strict")

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
    local e = err.new("error registering scm")
    if scms[scmname] then
        return false, e:append("scm with that name exists")
    end
    scms[scmname] = {}
    for name,func in pairs(intf) do
        local rc, re = scm.register_function(scmname, name, mod[name])
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
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

    -- closure: name
    local function func(info, sourcename, ...)
        local src = info.sources[sourcename]
        local rc, re, e
        e = err.new("calling scm operation failed")
        if not scms[src.type] then
            return false, e:append("no such source type: %s", src.type)
        end
        local f = scms[src.type][name]
        if not f then
            e:append("%s is not implemented for source type: %s", src.type)
            return false, e
        end
        return f(info, sourcename, ...)
    end

    intf[name] = func

    -- we have lots of calls like scm.<function>(...). Register the interface
    -- function in the scm module to support those calls.
    if strict.islocked(scm) then
        strict.declare(scm, {name})
    end
    scm[name] = func

    return true, nil
end

--- register a new scm function (accessible through a scm interface)
-- @param type string: scm type
-- @param name string: interface name
-- @param func function: interface function
-- @return bool
-- @return an error object on failure
function scm.register_function(type, name, func)
    local e = err.new("registering scm function failed")
    if not scms[type] then
        return false, e:append("no scm type by that name: %s", type)
    end
    if not intf[name] then
        return false, e:append("no scm interface by that name: %s", name)
    end
    if scms[type][name] then
        return false, e:append("scm function exists: %s.%s", type, name)
    end
    scms[type][name] = func
    return true, nil
end

--- apply default values where possible and a source configuration is
-- incomplete
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
local function source_apply_default_licences(info, sourcename)
  local e = err.new("applying default licences failed.")
  local src = info.sources[ sourcename ]
  if src.licences_default_applied then
    return true
  end
  src.licences_default_applied = true
  if not src.licences and src.licence then
    e2lib.warnf("WDEPRECATED", "in source %s:", src.name)
    e2lib.warnf("WDEPRECATED",
		" licence attribute is deprecated. Replace by licences.")
    src.licences = src.licence
  end
  if not src.licences then
    e2lib.warnf("WDEFAULT", "in source %s:", src.name)
    e2lib.warnf("WDEFAULT",
		" licences attribute missing. Defaulting to empty list.")
    src.licences = {}
  elseif type(src.licences) == "string" then
    e2lib.warnf("WDEPRECATED", "in source %s:", src.name)
    e2lib.warnf("WDEPRECATED",
		" licences attribute is not in table format. Converting.")
    src.licences = { src.licences }
  end
  for i, s in pairs(src.licences) do
    if type(i) ~= "number" or type(s) ~= "string" then
      e:append("licences attribute is not a list of strings")
      return false, e
    end
  end
  for _,l in ipairs(src.licences) do
    if not info.licences[l] then
      e:append("unknown licence: %s", l)
      return false, e
    end
  end
  return true
end

--- validate generic source configuration, usable by SCM plugins
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
function scm.generic_source_validate(info, sourcename)
    local src = info.sources[sourcename]
    local rc, re
    local e
    if not src then
        return false, err.new("invalid source: %s", sourcename)
    end
    e = err.new("in source %s:", sourcename)
    rc, re = source_apply_default_licences(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    if not src.type then
        e:append("source has no `type' attribute")
    end
    if src.env and type(src.env) ~= "table" then
        e:append("source has invalid `env' attribute")
    else
        if not src.env then
            e2lib.warnf("WDEFAULT",
            "source has no `env' attribute. Defaulting to empty dictionary")
            src.env = {}
        end
        src._env = environment.new()
        for k,v in pairs(src.env) do
            if type(k) ~= "string" then
                e:append("in `env' dictionary: key is not a string: %s", tostring(k))
            elseif type(v) ~= "string" then
                e:append("in `env' dictionary: value is not a string: %s", tostring(v))
            else
                src._env:set(k, v)
            end
        end
    end
    if e:getcount() > 1 then
        return false, e
    end
    return true, nil
end

--- apply default values where possible
-- @param info the info table
-- @param sourcename the source name
-- @return bool
-- @return an error object on failure
function scm.generic_source_default_working(info, sourcename)
    local src = info.sources[ sourcename ]
    if src.working_default_applied then
        return true
    end
    src.working_default_applied = true
    local src_working_default = string.format("in/%s", sourcename)
    if src.working and src.working ~= src_working_default then
        e2lib.warnf("WPOLICY", "in source %s:", src.name)
        e2lib.warnf("WPOLICY", " configuring non standard working direcory")
    elseif src.working then
        e2lib.warnf("WHINT", "in source %s:", src.name)
        e2lib.warnf("WHINT", " no need to configure working directory")
    else
        src.working = string.format("in/%s", sourcename)
        e2lib.warnf("WDEFAULT", "in source %s:", src.name)
        e2lib.warnf("WDEFAULT",
        " `working' attribute missing. Defaulting to '%s'.", src.working)
    end
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
    rc, re = scm.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
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

scm.register_interface("sourceid")
scm.register_interface("validate_source")
scm.register_interface("toresult")
scm.register_interface("prepare_source")
scm.register_interface("fetch_source")
scm.register_interface("update")
scm.register_interface("check_workingcopy")
scm.register_interface("working_copy_available")
scm.register_interface("display")
scm.register_interface("has_working_copy")

return strict.lock(scm)

-- vim:sw=4:sts=4:et:
