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

-- e2scm.lua - SCM-specific functionality -*- Lua -*-


e2scm = e2lib.module("e2scm")


-- General SCM wrapping
--
-- SCM-specific functions are implemented as sub-tables of the "e2scm"
-- namespace and calls to "e2scm.<SCM>.<op>(...)" are simply passed
-- to the SCM specific entries (after checking whether such an operation
-- exists for the selected SCM).
--
--   e2scm.register(SCMNAME, [TABLE]) -> TABLE
--
--     Registers an SCM with the given name and creates the namespace and
--     returns it (to be filled with operations). If a table is given as
--     argument, then the argument table is used instead of creating a
--     fresh one.
--
--   e2scm.register_op(OPNAME, DOC)
--
--     Registers SCM operation with documentation string.
--

local scms = {}
local ops = {}
local scmmt = {}

function scmmt.__index(t, k)
  local doc = ops[ k ] or 
    e2lib.bomb("invalid SCM operation `" .. k .. "'")
  local x = rawget(t, k)
  return x or e2lib.abort("`" .. t.name .. "' can not " .. ops[ k ])
end

function e2scm.register(scm, t)
  t = t or {}
  t.name = scm
  scms[ scm ] = t
  return t
end

function e2scm.register_op(op, doc)
  ops[ op ] = doc
end

function e2scm.registered(scm)
  return scms[ scm ]
end

-- iterate over registrated scm, include "files" when all is true
function e2scm.iteratescms(all)
  local k = nil
  local t = scms
  local function nextscm(t)
    k = next(t, k)
    if k == "files" and not all then k = next(t, k) end
    return k
  end
  return nextscm, t
end

-- for all scms, add an options flag
function e2scm.optionsaddflags(all, text)
  local t = text or "use"
  for scm in e2scm.iteratescms(all) do
    e2option.flag(scm, t .. " source of type '" .. scm .. "'")
  end
end

-- with options parsed, see which flag has been given with the options
function e2scm.optionswhichflag(options, default)
  local f = nil
  for scm in e2scm.iteratescms(true) do
    if options[scm] then
      f = f and e2lib.abort("scm type flags to be used exclusively") or scm
    end
  end
  return f or default or e2lib.abort("no scm type flag given")
end

local mt = {}

function mt.__index(t, k)
  local scm = scms[ k ]
  return scm or e2lib.bomb("no SCM is registered under the name `" .. k .. "'")
end

setmetatable(e2scm, mt)

scm = {}

local function sourcebyname(info, sourcename)
	local s = info.sources[sourcename]
	if not s then
		return nil, new_error("no source by that name: %s", sourcename)
	end
	return s, nil
end

--- calculate and return the sourceid
-- @param info
-- @param sourcename
-- @param sourceset string: source set
-- @return string: the sourceid, or nil
-- @return an error object on failure
function scm.sourceid(info, sourcename, sourceset)
	local src = sourcebyname(info, sourcename)
	local rc, re, e
	e = new_error("getting sourceid failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].sourceid then
		e:append("sourceid not implemented for source type: %s",
								src.type)
		return false, e
	end
	local sourceid
	sourceid, re = e2scm[src.type].sourceid(info, sourcename, sourceset)
	if not sourceid then
		return nil, re
	end
	return sourceid, nil
end

--- validate a source configuration
-- @param info
-- @param sourcename
-- @return bool
-- @return an error object on failure
function scm.validate_source(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("validating source failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].validate_source then
		e:append("validate_source not implemented for source type: %s",
								src.type)
		return false, e
	end
	rc, re = e2scm[src.type].validate_source(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- create a result from a source
-- @param info
-- @param sourcename
-- @param sourceset string: source set
-- @param directory string: destination path to create the result
-- @return bool
-- @return an error object on failure
function scm.toresult(info, sourcename, sourceset, directory)
	-- create in directory the following structure:
	-- ./makefile
	-- ./source/<files>
	-- ./licences/<files>.licences   -- a list of licences per file
	--          ...
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].toresult then
		e:append("toresult not implemented for source type: %s",
								src.type)
		return false, e
	end
	local rc, re = e2scm[src.type].toresult(info, sourcename, 
						sourceset, directory)
	if not rc then
		return false, re
	end
	return true, nil
end

--- prepare a source for building
-- @param info
-- @param sourcename
-- @param sourceset string: source set
-- @param buildpath string: destination path
-- @return bool
-- @return an error object on failure
function scm.prepare_source(info, sourcename, sourceset, buildpath)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].prepare_source then
		e:append("prepare_source not implemented for source type: %s",
								src.type)
		return false, e
	end
	rc, re = e2scm[src.type].prepare_source(info, sourcename, sourceset,
								buildpath)
	if not rc then
		return false, re
	end
	return true, nil
end

--- fetch a source
-- @param info
-- @param sourcename
-- @return bool
-- @return an error object on failure
function scm.fetch_source(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].fetch_source then
		e:append("fetch_source not implemented for source type: %s",
								src.type)
		return false, e
	end
	rc, re = e2scm[src.type].fetch_source(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- update a source
-- @param info
-- @param sourcename
-- @return bool
-- @return an error object on failure
function scm.update(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].update then
		e:append("update not implemented for source type: %s",
								src.type)
		return false, e
	end
	rc, re = e2scm[src.type].update(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- sanity check a working copy
-- @param info
-- @param sourcename
-- @return bool
-- @return an error object on failure
function scm.check_workingcopy(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].check_workingcopy then
		e:append(
		    "check_workingcopy not implemented for source type: %s",
								src.type)
		return false, e
	end
	rc, re = e2scm[src.type].check_workingcopy(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- check if a working copy is available
-- @param info
-- @param sourcename
-- @return bool
-- @return an error object on failure
function scm.working_copy_available(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].working_copy_available then
		e:append(
			"working_copy_available not implemented for source "..
			"type: %s", src.type)
		return false, e
	end
	rc, re = e2scm[src.type].working_copy_available(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- create a table of lines for display
-- @param info
-- @param sourcename
-- @return a table
-- @return an error object on failure
function scm.display(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].display then
		e:append(
			"display not implemented for source "..
			"type: %s", src.type)
		return false, e
	end
	rc, re = e2scm[src.type].display(info, sourcename)
	if not rc then
		return nil, re
	end
	return rc, nil
end

--- check if this scm type supports a working copy
-- @param info
-- @param sourcename
-- @return a table
-- @return an error object on failure
function scm.has_working_copy(info, sourcename)
	local src = info.sources[sourcename]
	local rc, re, e
	e = new_error("calling scm operation failed")
	if not e2scm[src.type] then
		return false, e:append("no such source type: %s", src.type)
	end
	if not e2scm[src.type].has_working_copy then
		e:append(
			"has_working_copy not implemented for source "..
			"type: %s", src.type)
		return false, e
	end
	rc, re = e2scm[src.type].has_working_copy(info, sourcename)
	if not rc then
		return false, re
	end
	return true, nil
end

--- register a new scm interface
-- @param name string: interface name
-- @param func function: interface function
-- @return bool
-- @return an error object on failure
function scm.register_interface(name, func)
  local e = new_error("registering scm interface failed")
  if scm[name] then
    return false, e:append(
		"interface with that name exists: %s", name)
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
  local e = new_error("registering scm function failed")
  if not e2scm[type] then
    return false, e:append("no scm type by that name: %s", type)
  end
  if not scm[name] then
    return false, e:append("no scm interface by that name: %s", name)
  end
  if e2scm[type][name] then
    return false, e:append("scm function exists: %s.%s", type, name)
  end
  scms[type][name] = func
  return true, nil
end
