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

-- files.lua - non-SCM operations -*- Lua -*-
--
-- See e2scm.lua for more information about these operations.


local files = {}

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
function files.validate_source(info, sourcename)
  local rc1 = true   -- the return value
  local rc, e = generic_validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  e = new_error("in source %s:", sourcename)
  e:setcount(0)
  local src = info.sources[ sourcename ]
  if not src.file then
    e:append("%s: source has no `file' attribute", sourcename)
  end
  if src.file then
    for _,f in pairs(src.file) do
      -- catch deprecated configuration
      if f.name then
	e:append("source has file entry with `name' attribute")
      end
      if (not f.licences) and src.licences then
	f.licences = src.licences
      end
      if (not f.server) and src.server then
        f.server = src.server
      end
      if not f.licences then
        e:append("source has file entry without `licences' attribute")
      end
      for _,l in ipairs(f.licences) do
	if not info.licences[l] then
	  e:append("invalid licence assigned to file: %s", l)
	end
      end
      if not f.server then
	e:append("source has file entry without `server' attribute")
      end
      if f.server and (not info.servers[f.server]) then
	e:append("invalid server: %s", f.server)
      end
      if not f.location then
	e:append("source has file entry without `location' attribute")
      end
      if not (f.unpack or f.copy or f.patch) then
        e:append("source has file entry without `unpack, copy or patch' " ..
			"attribute")
      end
      if f.location and (not f.checksum_file) then
        f.checksum_file = string.format("%s%s", f.location, 
					info.default_checksum_file_suffix)
	e2lib.warnf("WDEFAULT", "in source %s:", sourcename)
	e2lib.warnf("WDEFAULT", " file: %s:%s", f.server, f.location)
	e2lib.warnf("WDEFAULT", " checksum_file defaulting to %s",
							f.checksum_file)
      end
    end
  end
  if e:getcount() > 0 then
    return false, e
  end
  return true, nil
end

function files.get_revision_id(info, sourcename, sourceset)
  local rc, e
  rc, e = files.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  local function files_hash_iterator(files)
    local i = nil
    local function nextfile(f)
      i = next(f, i)
      return i and files[i].hash
    end
    return nextfile, files
  end
  local s = info.sources[sourcename]
  if not s.fhash then
    -- store hash for each file
    for _,f in pairs(s.file) do
      f.hash, e = e2tool.read_hash_file(info, f.server, f.checksum_file)
      if not f.hash then
	e2lib.log(3, string.format(
		"hash file not available for %s:%s. Hashing on-the-fly", 
		f.server, f.location))
        f.hash, e = e2tool.hash_file(info, f.server, f.location)
      end
      if not f.hash then
	e2lib.log(1, e)
	e2lib.abort(string.format("fetching file %s:%s", f.server, f.location))
      end
    end
    s.fhash = e2lib.compute_hash(files_hash_iterator, s.file)
  end
  return s.fhash
end

--- cache files for a source
-- @param info the info structure
-- @param sourcename name of the source
-- @return bool
-- @return nil, an error string on error
function files.cache_source(info, sourcename)
  local rc, e
  rc, e = files.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  local s = info.sources[sourcename]
  -- cache all files for this source
  for i,f in pairs(s.file) do
    e2lib.log(4, string.format("files.cache_source: caching file %s:%s", 
  						f.server, f.location))
    local flags = { cache = true }
    if f.server ~= info.root_server_name then
      local rc, e = cache.cache_file(info.cache, f.server, f.location, flags)
      if not rc then
        return false, e
      end
      local rc, e = cache.cache_file(info.cache, f.server, f.checksum_file, 
									flags)
      if not rc then
	e2lib.log(3,
		estring(e, string.format("%s:%s", f.server, f.checksum_file)))
        -- this is not fatal
      end
    else
      e2lib.log(4, string.format("not caching %s:%s (stored locally)", 
							f.server, f.location))
    end
  end
  return true, nil
end

function files.fetch_source(info, sourcename)
  local rc, re
  local e = new_error("fetching source failed: %s", sourcename)
  rc, re = files.validate_source(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  local rc, re = files.cache_source(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  return true, nil
end

function files.working_copy_available(info, sourcename)
  local rc, e
  rc, e = files.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  return false
end

function files.has_working_copy(info, sourcename)
  local rc, e
  rc, e = files.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  return false
end

--- prepare a files source
-- @return bool
-- @return nil, maybe an error string on error
function files.prepare_source(info, sourcename, sourceset, buildpath)
  local rc, re
  local e = new_error("error preparing source: %s", sourcename)
  rc, re = files.validate_source(info, sourcename)
  if not rc then
    return false, e:cat(re)
  end
  local symlink = nil
  e2lib.log(4, string.format("prepare source: %s", sourcename))
  local s = info.sources[sourcename]
  for _,file in ipairs(info.sources[sourcename].file) do
    if file.unpack then
      local cache_flags = { cache = true }
      local rc, re = cache.cache_file(info.cache, file.server, file.location, 
							cache_flags)
      if not rc then
	return false, e:cat(re)
      end
      local path, re = cache.file_path(info.cache, file.server, file.location, 
							cache_flags)
      if not path then
	return false, e:cat(re)
      end
      local y = e2lib.howtounpack(path, path, buildpath)
      if not y or e2lib.callcmd_capture(y) ~= 0 then
	return false, e:append("failed to unpack: %s", path)
      end
      if not symlink then
	symlink = buildpath .. "/" .. sourcename
	if file.unpack ~= sourcename then
	  if not e2util.symlink(file.unpack, symlink) then
	    return false, e:append("cannot create symlink: %s -> %s", symlink, 
								file.unpack)
	  end
	end
      end
    else
      if not symlink then
        symlink = buildpath .. "/" .. sourcename
	local rc, re = e2lib.mkdir(symlink, "-p")
	if not rc then
	  return false, e:cat(re)
	end
      end
      if file.patch then
	local cache_flags = { cache = true }
	local rc, re = cache.cache_file(info.cache, file.server, file.location,
								cache_flags)
	if not rc then
	  return false, e:cat(re)
	end
	local path, re = cache.file_path(info.cache, file.server,
						file.location, cache_flags)
	if not path then
	  return false, e:append(re)
	end
	local args = string.format("-p '%s' -d '%s' -i '%s'", file.patch,
								symlink, path)
	rc, re = e2lib.patch(args)
	if not rc then
	  return false, e:cat(re)
	end
      elseif file.copy then
	local fcdirname = e2lib.dirname(file.copy)
	local fcbasename = e2lib.basename(file.copy)
	local destination = string.format("%s/%s/%s", buildpath, sourcename,
								file.copy)
	local destdir, destname
	-- emulate the cp behaviour to feed the cache.fetch_file interface
	-- correctly, that does not allow ambiguities
	if e2lib.isdir(destination) then
	  destdir = destination
	  destname = nil
	else
	  destdir = string.format("%s/%s/%s", buildpath, sourcename,
								fcdirname)
	  destname = fcbasename
	  if not e2lib.mkdir(destdir, "-p") then
	    e2lib.abort(string.format(
			"can't create destination directory: %s", destdir))
	  end
	end
	local rc, re = cache.fetch_file(info.cache, file.server, file.location, 
							destdir, destname, {})
	if not rc then
	  return false, e:cat(re)
	end
      else
	e2lib.abort(string.format("missing destiny for file %s (%s)", 
						file.location, file.server))
      end
    end
  end
  return true, nil
end

--- create a table of lines for display
-- @param info the info structure
-- @param sourcename string
-- @return a table, nil on error
-- @return an error string on failure
function files.display(info, sourcename)
  local rc, e
  rc, e = files.validate_source(info, sourcename)
  if not rc then
    return false, e
  end
  local src = info.sources[sourcename]
  local display = {}
  display[1] = string.format("type       = %s", src.type)
  local i = 2
  for _,f in pairs(src.file) do
    display[i] = string.format("file       = %s:%s", f.server, f.location)
    i = i + 1
  end
  for _,l in ipairs(src.licences) do
    display[i] = string.format("licence    = %s", l)
    i = i + 1
  end
  if src.sourceid then
    display[i] = string.format("sourceid   = %s", src.sourceid)
    i = i + 1
  end	
  return display
end

--- calculate an id for a source
-- @param info
-- @param sourcename
-- @param sourceset
-- @return string: the source id, nil on error
-- @return an error string on error
function files.sourceid(info, sourcename, sourceset)
	local rc, e
	rc, e = files.validate_source(info, sourcename)
	if not rc then
		return false, e
	end
	local src = info.sources[sourcename]
	if src.sourceid then
		return src.sourceid
	end
	-- sourceset is ignored for files sources
	local hc = hash.hash_start()
	hash.hash_line(hc, src.name)
	hash.hash_line(hc, src.type)
	for _,l in ipairs(src.licences) do
		hash.hash_line(hc, l)
		local licenceid, re = e2tool.licenceid(info, l)
		if not licenceid then
			return nil, re
		end
		hash.hash_line(hc, licenceid)
	end
	for _,f in ipairs(src.file) do
		f.hash, e = e2tool.read_hash_file(info, f.server,
							f.checksum_file)
		if not f.hash then
			if f.server ~= info.root_server_name then
				e2lib.warn("WOTHER", string.format(
					"in source %s: " ..
					"checksum file not available",
								src.name))
				e2lib.warn("WOTHER", string.format(
					" file: %s:%s", f.server, f.location))
				e2lib.warn("WOTHER", string.format(
					" checksum_file: %s", f.checksum_file))
			end
			f.hash, e = e2tool.hash_file(info, f.server,
								f.location)
		end
		if not f.hash then
			return nil, e
		end
		hash.hash_line(hc, f.checksum_file)
		hash.hash_line(hc, f.location)
		hash.hash_line(hc, f.hash)
		hash.hash_line(hc, f.server)
		hash.hash_line(hc, tostring(f.unpack))
		hash.hash_line(hc, tostring(f.patch))
		hash.hash_line(hc, tostring(f.copy))
	end
	e2lib.log(4, string.format("hash data for source %s\n%s", src.name, 
								hc.data))
	src.sourceid = hash.hash_finish(hc)
	return src.sourceid
end

-- export the source to a result structure
function files.toresult(info, sourcename, sourceset, directory)
	local rc, re
	local e = new_error("converting result failed")
	rc, re = files.validate_source(info, sourcename)
	if not rc then
		return false, e:cat(re)
	end
	local s = info.sources[sourcename]
	local makefile = "makefile" -- name of the makefile
	local source = "source"     -- directory to store source files in
	local fname = string.format("%s/%s", directory, makefile)
	local f, msg = io.open(fname, "w")
	if not f then
		return false, e:cat(msg)
	end
	f:write(string.format(
		".PHONY:\tplace\n\n"..
		"place:\n"))
	for _,file in ipairs(s.file) do
		e2lib.log(4, string.format("export file: %s", file.location))
		local destdir = string.format("%s/%s", directory, source)
		local destname = nil
		e2lib.mkdir(destdir, "-p")
		local rc, re = cache.fetch_file(info.cache, file.server,
					file.location, destdir, destname, {})
		if not rc then
			return false, e:cat(re)
		end
		local c = e2lib.howtounpack(
			string.format("%s/%s", destdir,
						e2lib.basename(file.location)),
			string.format("%s/%s", source,
						e2lib.basename(file.location)),
			string.format("$(BUILD)"))
		if c then
			f:write(string.format("\t%s\n", c))
		end
		if file.unpack then
			f:write(string.format(
			"\tln -s %s $(BUILD)/%s\n", file.unpack, sourcename))
		end
		if file.copy then
			f:write(string.format(
			"\tmkdir -p \"$(BUILD)/%s\"\n"..
			"\tcp \"%s/%s\" \"$(BUILD)/%s/%s\"\n",
			sourcename,
			source, e2lib.basename(file.location), sourcename,
								file.copy))
		end
		if file.patch then
			f:write(string.format(
			"\tpatch -p%s -d \"$(BUILD)/%s\" "..
			"-i \"$(shell pwd)/%s/%s\"\n",
			file.patch, sourcename, source,
			e2lib.basename(file.location)))
		end
		-- write licences
		local destdir = string.format("%s/licences", directory)
		local fname = string.format("%s/%s.licences", destdir,
						e2lib.basename(file.location))
		local licence_list = table.concat(file.licences, "\n") .. "\n"
		rc, re = e2lib.mkdir(destdir, "-p")
		if not rc then
			return false, e:cat(re)
		end
		rc, re = e2lib.write_file(fname, licence_list)
		if not rc then
			return false, e:cat(re)
		end
		e2lib.log(4, string.format("export file: %s done",
							file.location))
	end
	f:close()
	return true, nil
end

function files.check_workingcopy(info, sourcename)
	return true, nil
end

e2scm.register("files", files)
