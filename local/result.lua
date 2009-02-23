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

-- result.lua -*- Lua -*-

-- Documentation: stored result filesystem format version 1:
-- path/metadata	file containing an integer version number

-- Required metadata
-- - version, just to be extensible
-- - timestamp, to find old results
-- - human readable timestamp, for convenience
-- - path to the result files, relative to the metadata file
-- - list of files, to allow copying a result via transports that don't
--   understand recursion (e.g. http)
--
-- Metadata ist stored in a file named "metadata"
--
-- Format of the metadata file
-- <version>
-- <timestamp>
-- <timestamp_human>
-- <files path>
-- <space><f1>
-- <space>
-- <space><fn>
--
-- Fetching a stored result:
--  1. fetch the metadata
--  2. read the list of files
--  3. fetch the files
--
-- Pushing a stored result:
--  1. create the remote directory
--  2. push the metadata
--  3. push the files

-- Stored Result data structure
-- General:
-- 	sr.metadata_file file that holds the version number
-- Version 1:
--      sr.version      integer version number (1)
--      sr.files_path   location of the result files in the filesystem
--      sr.files	table of files that make up the result

local result_autoconvert = true

--- create a new stored result data structure
--  @return the stored result data structure
--  @return nil and an error string on error
function new()
	--- stored result data structure
	-- @class table
	-- @name sr
	-- @field version version number
	-- @field metadata_file name of the metadata file
	-- @field files_path path to the result files relative to the meta
	--        data file
	-- @field files table of result file tables, to be included in the 
	--        metadata file for stupid transports
	-- @field new new()
	-- @field read read()
	-- @field get_files get_files()
	-- @field update_timestamp update_timestamp()
	local sr = {}

	-- variables
	sr.version = 1
	sr.metadata_file = "metadata"
	sr.files_path = "files"
	sr.files = {}

	-- functions
	sr.new = new
	sr.store = store
	sr.fetch = fetch
	sr.fetchfiles = fetchfiles
	sr.read = read
	sr.write = write
	sr.get_files = get_files
	sr.get_filelist = get_filelist
	sr.add_file = add_file
	sr.update_timestamp = update_timestamp

	sr:update_timestamp()
	return sr
end

--- update the timestamp
--  @return void this function always succeeds
function update_timestamp(sr)
	sr.timestamp = os.date("%s")
	sr.timestamp_human = os.date("%c", sr.timestamp)
end

--- convert results from the old format (plain directory with files in it)
--  to version 1 (with metadata file)
-- @param path path to the result
-- @return the stored result on success, or nil on error
-- @return nil, an error string on error
function convert0_1(path)
	local sr, e
	sr = result.new()
	local f = io.open(path .. "/" .. sr.metadata_file, "r")
	if f then
		f:close()
		e2lib.abort("can't convert result: unknown version: " .. path)
	end
	local test = string.format("test -d %s/", path)
	if e2lib.callcmd_capture(test) ~= 0 then
		return false, "result does not exist: " .. path
	end
	e2lib.log(1, "converting result: " .. path)
	local ls = string.format("ls %s", path)
	local lsp = io.popen(ls, "r")
	if not lsp then
		e2lib.abort("can't list result files: " .. ls)
	end
	while true do
		local l = lsp:read()
		if not l then
			break
		end
		local file = {}
		file.name = l
		file.sha1 = nil
		table.insert(sr.files, file)
	end
	lsp:close()
	if #sr.files == 0 then
		return false, "result with no files, treating as absent."
	end
	local mkdir, mv
	mkdir = string.format("mkdir %s/%s", path, sr.files_path)
	if e2lib.callcmd_capture(mkdir) ~= 0 then
		return false, "result conversion failed: " .. mkdir
	end
	for _, file in pairs(sr.files) do
		mv = string.format("mv %s/%s %s/%s/%s", 
			path, file.name, path, sr.files_path, file.name)
		if e2lib.callcmd_capture(mv) ~= 0 then
			return false, "result conversion failed: " .. mv
		end
	end
	sr:update_timestamp()
	sr:write(path)
	return true
end

--- read metadata
--  @param path
--  @return the stored result description table, nil on error
--  @return nil, an error string on error
function read(path)
	e2lib.log(4, string.format("result.read(): %s", tostring(path)))
	local sr = result.new()
	if not (type(path) == "string") then
		return nil, "wrong argument type: path"
	end
	local f = io.open(path .. "/" .. sr.metadata_file, "r")
	if not f and result_autoconvert then
		local r, e = result.convert0_1(path)
		-- don't care if this succeeded. The next open will succeed
		-- or not and error checking is in place.
		f = io.open(path .. "/" .. sr.metadata_file, "r")
	end
	if not f then
		return nil, "can't open version file: " .. sr.metadata_file
	end
	local version = f:read()
	if not version or
	   not type(version) == "string" or not version:match("(%d+)") then
		return nil, "can't parse metadata file: " .. sr.metadata_file
	end
	sr.version = tonumber(version)
	if sr.version == 1 then
		sr.timestamp = tonumber(f:read())
		sr.timestamp_human = f:read()
		sr.files_path = f:read()
		while true do
			local line, fname
			line = f:read()
			if not line then 
				break
			end
			fname = line:match("%s(.+)")
			if not fname then
				break
			end
			local file = {}
			file.name = fname
			file.sha1 = nil
			table.insert(sr.files, file)
		end
	else
		return nil, "unknown stored result version:" .. sr.version
	end
	f:close()
	if not ( sr.timestamp >= 1 ) or
	   not ( type(sr.timestamp_human) == "string" ) or
	   not ( type(sr.files_path) == "string" ) then
		return nil, "can't parse result metadata file: " ..
					sr.metadata_file
	end
	return sr, nil
end

--- write metadata file
-- @param sr stored result data structure
-- @param path filesystem path to the stored result
-- @return the sr structure on success, nil
-- @return an error string on error, nil otherwise
function write_metadata1(sr, path)
	local f, success, rc
	f = io.open(path .. "/" .. sr.metadata_file, "w")
	if not f then
		return nil, "can't open metadata file: " .. sr.metadata_file
	end
	local metadata = string.format(
				"%d\n" .. -- version
				"%d\n" .. -- timestamp
				"%s\n" .. -- timestamp_human
				"%s\n",   -- files_path
		sr.version, sr.timestamp, sr.timestamp_human, sr.files_path)
	success = f:write(metadata)
	if not success then
		return nil, 
			"can't write to metadata file: " .. sr.metadata_file
	end
	for _,fn in pairs(sr.files) do
		if not f:write(string.format(" %s\n", fn.name)) then
			return nil, "can't write to metadata file: " ..	
					sr.metadata_file
		end
	end
	f:close()
	return sr, nil
end

--- write metadata
--  @param  sr stored result data structure
--  @param  path path to the stored result in the filesystem
--  @param  create bool newly create the structure in the filesystem?
--  @return the sr structure on success
--  @return nil and an error string on failure
function write(sr, path, create)
	if not sr or not path then
		return nil, "missing argument"
	end
	if sr.version == 1 then
		local rc, e
		rc, e = write_metadata1(sr, path)
		if not rc then
			return nil, e
		end
		local dir = string.format("%s/%s", path, sr.files_path)
		if create then
			if os.execute("mkdir " .. dir) ~= 0 then
				return nil, "can't create files directory: " 
						.. dir
			end
		end
		return sr, nil
	end
	return nil, "unknown stored result version:" .. sr.version
end

--- get the directory holding the result files for a stored result
--  @param  sr stored result data structure
--  @return the location of the result files inside the result structure
--  @return nil and an error string on failure
function get_files(sr)
	if not sr then
		return nil, "missing argument"
	end
	if sr.version == 1 then
		return sr.files_path, nil
	end	
	return nil, "unknown stored result version:" .. sr.version
end

--- result file table, holds file names relativ to the path to the result,
-- e.g.
-- { name="metadata", sha1="abcdef..." } or
-- { sourcefile="/tmp/file1.tar.gz", name="files/file1.tar.gz", 
-- sha1="abc123..." }
-- @class table
-- @name file
-- @field sourcefile path to sourcefile
-- @field name filename
-- @field sha1 sha1 checksum, may be nil

--- get_filelist_flags
-- @class table
-- @name get_filelist_flags
-- @field all include all files
-- @field metadata inlude metadata files
-- @field result_files include result files

--- return a table of files that make up the result. 
-- @param sr stored result table
-- @param flags table of flags (all, metadata, result_files)
-- @return table of file tables, or nil
-- @return nil, or error string
function get_filelist(sr, flags)
	if not sr then
		return nil, "missing argument"
	end
	flags.metadata = flags.metadata or flags.all
	flags.result_files = flags.result_files or flags.all
	if sr.version == 1 then
		local t = {}
		for _,f in pairs(sr.files) do
			local file = {}
			file.sourcefile = f.sourcefile
			file.name = string.format("%s/%s", 
							sr.files_path, f.name)
			file.sha1 = f.sha1
			if flags.result_files then
				table.insert(t, file)
			end
		end
		local file = {}
		file.name = sr.metadata_file
		file.sha1 = nil
		file.sourcefile = nil
		if flags.metadata then
			table.insert(t, file)
		end
		return t, nil
	end
	return nil, "unknown stored result version:" .. sr.version
end

--- add a new result file to the stored result table
-- @param sr stored result table
-- @param path string
-- @param class file class (optional, for internal use)
-- @return bool
-- @return nil, or an error string
function add_file(sr, path, class)
	if (not sr) or (not path) then
		return nil, "missing argument"
	end
	if not class then
		class = "result"
	end
	local file = {}
	file.class = class
	file.sourcefile = path
	file.name = e2lib.basename(path)
	file.sha1 = nil			--XXX ignoring sha
	table.insert(sr.files, file)
	return true
end

--- store a result to a server
-- @param sr stored result table
-- @param c table: cache
-- @param server string: server name
-- @param baselocation string: location
-- @param tocache bool: store to cache
-- @param toserver bool: store to server
-- @return bool
-- @return an error object on failure
function store(sr, c, server, baselocation, tocache, toserver)
	local rc, re
	local e = new_error("storing result failed")
	-- write metadata to a temporary directory
	local tmp = e2lib.mktempdir()
	rc, re = sr:write(tmp)
	if not rc then
		return false, e:cat(re)
	end
	-- set cache flags
	local cache_flags = {}
	-- push metadata to its locations
	local flags = { metadata=true }
	for _,f in pairs(sr:get_filelist(flags)) do
		local sfile = string.format("%s/%s", tmp, f.name)
		local dlocation = string.format("%s/%s", baselocation, f.name)
		rc, re = cache.push_file(c, sfile, server, dlocation,
								cache_flags)
		if not rc then
			return false, e:cat(re)
		end
	end
	e2lib.rmtempdir(tmp)
	-- push result files to their locations
	local flags = { result_files=true }
	for _,f in pairs(sr:get_filelist(flags)) do
		local sfile = f.sourcefile
		local dlocation = string.format("%s/%s", baselocation, f.name)
		rc, re = cache.push_file(c, sfile, server, dlocation,
								cache_flags)
		if not rc then
			return false, e:cat(re)
		end
	end
	return true, nil
end

--- cache a result. Return true if the result is in the cache, or false
-- if it is not, or the cache is disabled.
-- @param sr stored result table
-- @param c table: cache
-- @param server string: server name
-- @param baselocation string: location
-- @return bool
-- @return an error object on failure
function fetch(c, server, baselocation)
	local e = new_error("caching result failed")
	local rc, re
	local mp, rp, sr
	local location1 = string.format("%s/metadata", baselocation)
	local cache_flags
	if not cache.cache_enabled(c, server) then
	  return false, new_error("cache disabled")
	end
	if cache.file_in_cache(c, server, location1) then
	  -- result is available
	  return true, nil
	end
	-- try to get the metadata file
	cache_flags = {}
	rc, re = cache.cache_file(c, server, location1, cache_flags)
	if not rc then
	  return false, e:cat(re)
	end
	mp, re = cache.file_path(c, server, location1, cache_flags)
	if not mp then
	  -- result is not available
	  e:append("result is not available")
	  return false, e:cat(re)
	end
	-- metadata file is ready
	rp = e2lib.dirname(mp)
	sr, re = result.read(rp)
	if not sr then
	  return false, e:cat(re)
	end
	-- cache the result files
	local flags = { result_files = true }
	for _,file in pairs(sr:get_filelist(flags)) do
	  location1 = string.format("%s/%s", baselocation, file.name)
	  rc, re = cache.cache_file(c, server, location1, cache_flags)
	  if not rc then
	     return false, e:cat(re)
	  end
	end
	-- result was fetched. OK.
	return true, nil
end

function available_local(c, server, baselocation)
	local location = string.format("%s/metadata", baselocation)
	return cache.file_local(c, server, location)
end

--- fetchfiles fetch result files to a directory
-- @param c table: cache
-- @param server string: server name
-- @param baselocation string: location
-- @return a sr object, nil on failure
-- @return an error object on failure
function fetchfiles(c, server, baselocation, destdir)
	local cache_flags = { check_only=true, }
	local e = new_error("result not available: %s:%s", server, 
							baselocation)
	local rc, re = cache.file_path(c, server, baselocation, cache_flags)
	if not rc then
		return false, e:cat(re)
	end
	local path, re = cache.file_path(c, server, baselocation, cache_flags)
	if not path then
		return false, e:cat(re)
	end
	local sr = result.read(path)
	if not sr then
		return false, e:cat(re)
	end
	local flags = { result_files = true }
	for _,f in pairs(sr:get_filelist(flags)) do
		local cache_flags = { chmod = "644", }
		local location = string.format("%s/%s", baselocation, f.name)
		rc, re = cache.fetch_file(c, server, location, destdir, nil,
								cache_flags)
		if not rc then
			e = new_error("incomplete result")
			return false, e:cat(re)
		end
	end
	return true, nil
end

---function test()
--	local sr
--	sr, e = result.read("foo")
--	if not sr then
--		print(e)
--		return nil
--	end
--	sr:write("bar", true)
--	sr.timestamp = sr.timestamp + 30
--	sr.files = { "f1", "f2", "f3" }
--	sr:write("bar", false)
--end

-- stored result object
result = {}

-- functions
result.convert0_1 = convert0_1
result.new = new
result.store = store
result.fetch = fetch
result.available_local = available_local
result.fetchfiles = fetchfiles
result.read = read
result.write = write
result.get_files = get_files
result.add_file = add_file
result.get_filelist = get_filelist
result.update_timestamp = update_timestamp
