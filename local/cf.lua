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

-- e2-cf -*- Lua -*-

require("e2local")
e2lib.init()

e2option.documentation = [[
usage: e2 cf <command> ...

commands:
 newresult       <name>
 newsource       <name> <scm>
 editresult      <name>
 editbuildscript <name>
 editsource      <name>

Commands starting with 'edit' can be abbreviated by using e...
Commands starting with 'new' can be abbreviated by using n...
Commands can be shortened as long as they remain unambiguous

e.g.: eb <name> is equivalent to editbuildscript <name>

modify and create configuration files
]]

local opts = e2option.parse(arg)

local info, re = e2tool.collect_project_info()
if not info then
  e2lib.abort(re)
end
local rc, re = e2tool.check_project_info(info)
if not rc then
  e2lib.abort(re)
end

rc, re = e2lib.chdir(info.root)
if not rc then
  e2lib.abort(re)
end

local editor = e2lib.osenv["EDITOR"]

local commands = {}

local function newsource(info, ...)
  local e = new_error("newsource")
  local t = ...
  local name = t[2]
  local scm = t[3]
  if not name then
    e:append("missing parameter: name")
  end
  if not scm then
    e:append("missing parameter: scm")
  end
  if e:getcount() > 1 then
    return false, e
  end
  local cfdir = e2tool.sourcedir(name)
  local cf = e2tool.sourceconfig(name)
  local cftemplate = string.format("%s/source.%s", info.local_template_path,
									scm)
  if not e2lib.isfile(cftemplate) then
    return false, e:append("template not available:", cftemplate)
  end
  if not e2lib.isfile(cf) and e2lib.isfile(cftemplate) then
     local rc, re = e2lib.mkdir(cfdir)
     if not rc then
       return false, e:cat(re)
     end
     local rc, re = e2lib.cp(cftemplate, cf)
     if not rc then
       return false, e:cat(re)
     end
  end
  rc, re = commands.editsource(info, ...)
  if not rc then
    return false, e:cat(re)
  end
  return true, nil
end

local function editsource(info, ...)
  local e = new_error("editsource")
  local t = ...
  local name = t[2]
  if not name then
    e:append("missing parameter: name")
  end
  if e:getcount() > 1 then
    return false, e
  end
  local cf = e2tool.sourceconfig(name)
  rc = os.execute(string.format("%s %s", editor, cf))
  return true, nil
end

local function newresult(info, ...)
  local e = new_error("newresult")
  local t = ...
  local name = t[2]
  if not name then
    e:append("missing parameter: name")
  end
  if e:getcount() > 1 then
    return false, e
  end
  local cfdir = e2tool.resultdir(name)
  local cf = e2tool.resultconfig(name)
  local bs = e2tool.resultbuildscript(name)
  local cftemplate = string.format("%s/result", info.local_template_path)
  local bstemplate = string.format("%s/build-script", info.local_template_path)
  if not e2lib.isfile(cf) and not e2lib.isfile(bs) and
     e2lib.isfile(cftemplate) and e2lib.isfile(bstemplate) then
     local rc, re = e2lib.mkdir(cfdir)
     if not rc then
       return false, e:cat(re)
     end
     local rc, re = e2lib.cp(cftemplate, cf)
     if not rc then
       return false, e:cat(re)
     end
     local rc, re = e2lib.cp(bstemplate, bs)
     if not rc then
       return false, e:cat(re)
     end
  end
  rc, re = commands.editresult(info, ...)
  if not rc then
    return false, e:cat(re)
  end
  rc, re = commands.editbuildscript(info, ...)
  if not rc then
    return false, e:cat(re)
  end
  return true, nil
end

local function editresult(info, ...)
  local e = new_error("editresult")
  local t = ...
  local name = t[2]
  if not name then
    e:append("missing parameter: name")
  end
  if e:getcount() > 1 then
    return false, e
  end
  local cf = e2tool.resultconfig(name)
  os.execute(string.format("%s %s", editor, cf))
  return true, nil
end

local function editbuildscript(info, ...)
  local e = new_error("editbuildscript")
  local t = ...
  local name = t[2]
  if not name then
    e:append("missing parameter: name")
  end
  if e:getcount() > 1 then
    return false, e
  end
  local cf = e2tool.resultbuildscript(name)
  os.execute(string.format("%s %s", editor, cf))
  return true, nil
end

commands.editbuildscript = editbuildscript
commands.editresult = editresult
commands.newresult = newresult
commands.newsource = newsource
commands.editsource = editsource
commands.ebuildscript = editbuildscript
commands.eresult = editresult
commands.nresult = newresult
commands.nsource = newsource
commands.esource = editsource

local i = 1
local match = {}
local cmd = opts.arguments[1]
if #opts.arguments < 1 then
	e2option.usage()
	e2lib.finish(1)
end
for c,f in pairs(commands) do
	if c:match(string.format("^%s", cmd)) then
		table.insert(match, c)
	end
end
if #match == 1 then
	local a = {}
	for _,o in ipairs(opts.arguments) do
		table.insert(a, o)
	end
	local f = commands[match[1]]
	rc, re = f(info, a)
	if not rc then
		e2lib.abort(re)
	end
else
	if #match > 1 then
		print(string.format("Ambiguous command: %s", cmd))
	end
	print("Available commands:")
	for c,f in pairs(commands) do
		print(c)
	end
	e2lib.finish(1)
end
e2lib.finish(0)
