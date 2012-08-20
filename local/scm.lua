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
local err = require("err")

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

return scm
