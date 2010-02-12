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

-- fetch-sources - Retrieve sources for project -*- Lua -*-

require("e2local")
require("e2tool")
require("e2build")
e2lib.init()

e2option.documentation = [[
usage: e2-fetch-sources <source> ...

fetch all sources for a project, provided they are not fetched yet.
up-to-dateness is not checked for sources which are already fetched.
]]

-- --all (--scm)
-- --source    select sources by source names
-- --result    select sources by result names
-- --chroot    select chroot files
-- --files     select files sources
-- --scm       select sources using scm systems
--  --git
--  --cvs
--  --svn
--
-- --fetch, --cache  fetch selected sources
-- --update          update selected sources

local e = new_error()

e2option.flag("all", "select all sources, even files sources")
e2option.flag("chroot", "select chroot files")
e2option.flag("files", "select files sources")
e2option.flag("scm", "select all scm sources")
e2option.flag("git", "select scm sources")
e2option.flag("cvs", "select cvs sources")
e2option.flag("svn", "select svn sources")
e2option.flag("fetch", "fetch selected sources (default)")
e2option.flag("update", "update selected source")
e2option.flag("source", "select sources by source names (default)")
e2option.flag("result", "select sources by result names")

local opts = e2option.parse(arg)
local info, re = e2tool.collect_project_info()
if not info then
  e2lib.abort(re)
end
local rc, re = e2tool.check_project_info(info)
if not rc then
  e2lib.abort(e:cat(re))
end

if not (opts.fetch or opts.update) then
  opts.fetch = true
  e2lib.warn("WOTHER", "Selecting fetch by default")
end
if opts.all then
  e2lib.warn("WOTHER", "--all selects all sources, even files sources")
end
if #opts.arguments > 0 then
  opts.selection = true
end
if not (opts.scm or opts.files or opts.chroot or opts.selection 
   or opts.git or opts.cvs or opts.svn) then
  e2lib.warn("WOTHER", "Selecting scm sources by default")
  opts.scm = true
end
if opts.scm then
  opts.git = true
  opts.cvs = true
  opts.svn = true
end
local select_type = {}
if opts["git"] then
  select_type["git"] = true
end
if opts["svn"] then
  select_type["svn"] = true
end
if opts["cvs"] then
  select_type["cvs"] = true
end
if opts["files"] then
  select_type["files"] = true
end

--- cache chroot files
-- @param info the info table
-- @return bool
-- @return nil, an error string on error
function cache_chroot(info)
  for _,c in ipairs(info.chroot) do
    for _,file in ipairs(c.files) do
      local rc, e = info.cache:cache_file(c.server, file, {})
      if not rc then
        return false, "caching file failed"
      end
    end
  end
  return true, nil
end

--- fetch and upgrade sources
-- @param info the info table
-- @param opts the option table
-- @param sel table of selected results
-- @return bool
-- @return nil, an error string on error
function fetch_sources(info, opts, sel)
  local rc1 = true    -- global return code
  local nfail = 0     -- failure counter
  local e = new_error()  -- no message yet, append the summary later on

  -- fetch
  for _, s in pairs(info.sources) do
    local has_wc = scm.has_working_copy(info, s.name)
    local wc_avail = scm.working_copy_available(info, s.name)
    if opts.fetch and sel[s.name] then
      if wc_avail then
        e2lib.log(1, "working copy for " .. s.name .. " is already available")
      else
        e2lib.log(1, "fetching working copy for source " .. s.name)
        local rc, re = scm.fetch_source(info, s.name)
        if not rc then
          e2lib.log(4, string.format("fetching source failed: %s",
								s.name))
	  e:cat(re)
        end
      end
    end
  end
  
  -- update
  for _, s in pairs(info.sources) do
    local has_wc = scm.has_working_copy(info, s.name)
    local wc_avail = scm.working_copy_available(info, s.name)
    if opts.update and has_wc and sel[s.name] then
      if not wc_avail then
        e2lib.log(1, string.format("working copy for %s is not available",
							s.name))
      else
        e2lib.log(1, "updating working copy for " .. s.name)
        local rc, re = scm.update(info, s.name)
        if not rc then
          e2lib.log(4, string.format("updating working copy failed: %s", 
								s.name))
	  e:cat(re)
        end
      end
    end
  end
  local nfail = e:getcount()
  if nfail > 0 then
    e:append("There were errors fetching %d sources", nfail)
    return false, e
  end
  return true, nil
end

local sel = {} -- selected sources

if #opts.arguments > 0 then
  for _, x in pairs(opts.arguments) do
    if info.sources[x] and not opts.result then
      e2lib.log(3, "is regarded as source: " .. x)
      sel[x] = x
    elseif info.results[x] and opts.result then
      e2lib.log(3, "is regarded as result: " .. x)
      local res = info.results[x]
      for _, s in ipairs(res.sources) do
	sel[s] = s
      end
    elseif opts.result then
      e2lib.abort("is not a result: " .. x)
    else
      e2lib.abort("is not a source: " .. x)
    end
  end
elseif opts["all"] then
  -- select all sources
  for s,src in pairs(info.sources) do
    sel[s] = s
  end
end

-- select all sources by scm type
for s, src in pairs(info.sources) do
  if select_type[src.type] then
    sel[s] = s
  end
end


for _, s in pairs(sel) do
	e2lib.logf(2, "selecting source: %s" , s)
	local src = info.sources[s]
	if not src then
		e:append("selecting invalid source: %s", s)
	end
end
if e:getcount() > 0 then
	e2lib.abort(e)
end

if opts.chroot then
  e2lib.log(2, "caching chroot files")
  local rc, re = cache_chroot(info)
  if not rc then
    e:append("Error: Caching chroot files failed")
    e:cat(re)
  end
end

if opts.scm or opts.files or opts.git or opts.cvs or opts.svn or 
	opts.selection then
  e2lib.log(2, "fetching sources...")
  local rc, re = fetch_sources(info, opts, sel)
  if not rc then
    e:cat(re)
  end
end

if e:getcount() > 0 then
  e2lib.abort(e)
end

e2lib.finish()
