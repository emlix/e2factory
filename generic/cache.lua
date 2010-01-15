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

module("cache", package.seeall)

--- cache
-- @class table
-- @name cache
-- @field name a human readable name
-- @field url cache base url
-- @field ce cache entries

--- cache entry
-- @class table
-- @name cache entry
-- @field server the server name
-- @field remote_url the remote server url
-- @field cache_url the cache url (must be a file:/// url)
-- @field flags default flags for this cache entry

--- flags influencing the caching behaviour
-- @class table
-- @name flags
-- @field cachable treat a server as cachable?
-- @field refresh refresh a cached file?
-- @field check_only check if a file is in the cache, without fetching

--- create a new cache table
-- @param name a cache name
-- @param url base url for this cache, must use file transport
-- @return a cache table
function new_cache(name, url)
	local debug = false
	local c = {}
	c.name = name
	c.url = url
	c.ce = {}
	e2lib.log(4, "Cache: " .. c.name)
	e2lib.log(4, " url: " .. c.url)
	if debug then 
		for k,v in pairs(c) do
			print(k,v)
		end
	end
	local meta = { __index = cache }
	setmetatable(c, meta)
	return c
end

--- create a new cache entry
-- @param cache a cache table
-- @param server the remote server name
-- @param remote_url the remote server to cache (server setup)
-- @param flags (server setup)
-- @param alias_server alias server (alias setup)
-- @param alias_location location relative to alias server (alias setup)
-- @return true on success, false on error
-- @return an error object on failure
function new_cache_entry(cache, server, remote_url, flags, alias_server,
								alias_location)
	assert(((remote_url and flags) or (alias_server and alias_location))
		and not
		((remote_url and flags) and (alias_server and alias_location)))
	local ru, cu
	local rc, re
	local e = new_error("error setting up cache entry")
	local ce = {}
	local cache_url = nil
	if not remote_url then
		-- setting up an alias
		local alias_ce, re = ce_by_server(cache, alias_server)
		if not alias_ce then
			return false, e:cat(re)
		end
		remote_url = string.format("%s/%s", alias_ce.remote_url,
							alias_location)
		if alias_ce.cache_url then
			cache_url = string.format("%s/%s", alias_ce.cache_url,
							alias_location)
		end
		flags = alias_ce.flags
	else
		cache_url = string.format("%s/%s", cache.url, server)
	end
	ru, re = url.parse(remote_url)
	if not ru then
		return false, e:cat(re)
	end
	ce.server = server
	ce.remote_url = ru.url
	ce.flags = {}
	ce.flags.cachable = flags.cachable
	ce.flags.cache = flags.cache and flags.cachable
	ce.flags.push_permissions = flags.push_permissions
	if flags.islocal ~= nil then
		ce.flags.islocal = flags.islocal
	elseif ru.transport == "file" then
		ce.flags.islocal = true
	else
		ce.flags.islocal = false
	end
	if flags.writeback ~= nil then
		ce.flags.writeback = flags.writeback
	end
	if ce.flags.cache then
		ce.cache_url = cache_url
	end
	if cache.ce[server] then
		return false, e:append("cache entry for server exists")
	end
	cache.ce[server] = ce
	e2lib.logf(4, "cache entry: %s (%s)", ce.server, cache.name)
	e2lib.logf(4, " remote url: %s", ce.remote_url)
	e2lib.logf(4, " cache url:  %s", tostring(ce.cache_url))
	for k,v in pairs(ce.flags) do
		e2lib.logf(4, " flags:      %-20s = %s", k, tostring(v))
	end
	return true, nil
end

--- get cache entry by url
-- @param cache the cache table
-- @param url the server url
-- @return the cache entry table, nil on error
-- @return an error object on failure
function ce_by_url(cache, url)
	for _,ce in pairs(cache.ce) do
		if ce.remote_url == url then
			return ce, nil
		end
	end
	return nil, new_error("no cache entry for url: %s", url)
end

--- get cache entry by server
-- @param cache the cache table
-- @param server the server name
-- @return the cache entry table, nil on error
-- @return an error object on failure
function ce_by_server(cache, server)
	for _,ce in pairs(cache.ce) do
		if ce.server == server then
			return ce, nil
		end
	end
	return nil, new_error("no cache entry for server: %s", server)
end

function valid_server(cache, server)
	if ce_by_server(cache, server) then
		return true
	else
		return false, new_error("not a valid server: %s", server)
	end
end

--- get remote url
-- for use in scm implementations where urls need to be handled manually
-- @param cache the cache table
-- @param server the server name
-- @param location the location relative to the server
-- @return the remote url, nil on error
-- @return an error object on failure
function remote_url(cache, server, location)
  local ce, e = ce_by_server(cache, server)
  if not ce then
    return nil, e
  end
  local url = string.format("%s/%s", ce.remote_url, location)
  return url
end

--- check if a cache is enabled
-- @param cache a cache table
-- @param server the server name
-- @return bool
-- @return an error object on failure
function cache_enabled(c, server)
	e2lib.log(4, "cache.file_in_cache(%s,%s,%s)", tostring(c),
							tostring(server))
	local ce, re = ce_by_server(c, server)
	if not ce then
		return false, re
	end
	return ce.flags.cache
end

--- check if a file is available in the cache
-- @param cache a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @return bool
-- @return an error object on failure
function file_in_cache(c, server, location)
	e2lib.logf(4, "cache.file_in_cache(%s,%s,%s)", tostring(c),
					tostring(server), tostring(location))
	local ce, re = ce_by_server(c, server)
	if not ce then
		return false, re
	end
	local ceurl, re = url.parse(ce.cache_url)
	if not ceurl then
		return false, re
	end
	local cf = string.format("/%s/%s", ceurl.path, location)
	local rc, re = e2lib.isfile(cf)
	if not rc then
		return false
	end
	e2lib.log(4, "file is in cache")
	return true
end

--- check if a file is available locally
-- @param cache a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @return bool
-- @return an error object on failure
function file_local(c, server, location)
	e2lib.logf(4, "file_local(%s,%s,%s)", tostring(c), tostring(server),
							tostring(location))
	local rc, re = file_in_cache(c, server, location)
	if re then
		return false, re
	end
	if rc then
		return true, nil
	end
	local ce, re = ce_by_server(c, server)
	if not ce then
		return false, re
	end
	if ce.islocal == false then
		return false
	end
	local path, re = file_path(c, server, location)
	if re then
		return false, re
	end
	if not path then
		return false
	end
	if not e2lib.isfile(path) then
		return false
	end
	e2lib.log(4, "file is on local server")
	return true
end

--- fetch a file from a server, with caching in place
-- @param cache a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @param destdir where to store the file locally
-- @param destname filename of the fetched file
-- @param flags table of flags
-- @return bool
-- @return an error object on failure
function fetch_file(cache, server, location, destdir, destname, flags)
	e2lib.log(4, string.format("%s: %s, %s, %s, %s, %s", "fetch_file()", 
		tostring(server), tostring(location), tostring(destdir), 
		tostring(destname), tostring(flags)))
	local rc, re
	local e = new_error("cache: fetching file failed")
	local ce, re = ce_by_server(cache, server)
	if not ce then
		return false, e:cat(re)
	end
	if not destname then
		destname = e2lib.basename(location)
	end
	-- fetch the file
	if ce.flags.cache then
		-- cache is enabled:
		-- fetch from source to cache and from cache to destination
		rc, re = cache_file(cache, server, location, flags)
		if not rc then
			return false, e:cat(re)
		end
		rc, re = transport.fetch_file(ce.cache_url, location,
				destdir, destname, flags)
		if not rc then
			return false, e:cat(re)
		end
	else
		-- cache is disabled:
		-- fetch from source to destination
		rc, re = transport.fetch_file(ce.remote_url, location,
				destdir, destname, flags)
		if not rc then
			return false, e:cat(re)
		end
	end
	if flags.chmod then
		local f = string.format("%s/%s", destdir, destname)
		rc, re = e2lib.chmod(flags.chmod, f)
		if not rc then
			return false, e:cat(re)
		end
	end
	return true, nil
end

--- push a file to a server: cache and writeback
-- @param cache a cache table
-- @param sourcefile where to store the file locally
-- @param server the server name
-- @param location location relative to the server url
-- @param flags table of flags
-- @return bool
-- @return an error object on failure
function push_file(cache, sourcefile, server, location, flags)
	local rc, re
	local e = new_error("error pushing file to cache/server")
	e2lib.log(4, string.format("%s: %s, %s, %s", "push_file()", 
						sourcefile, server, location))
	local ce, re = ce_by_server(cache, server)
	if not ce then
		return false, e:cat(re)
	end
	if ce.flags.cache then
		-- cache is enabled:
		-- push the file from source to cache and from cache to
		-- destination
		rc, re = transport.push_file(sourcefile, ce.cache_url,
					location, nil, flags.try_hardlink)
		if not rc then
			return false, e:cat(re)
		end
		rc, re = writeback(cache, server, location, flags)
		if not rc then
			return false, e:cat(re)
		end
	else
		-- cache is disabled
		-- push the file from source to destination immediately
		rc, re = transport.push_file(sourcefile, ce.remote_url,
					location, ce.flags.push_permissions,
					flags.try_hardlink)
		if not rc then
			return false, e:cat(re)
		end
	end
	return true, nil
end

--- writeback a cached file
-- @param cache the cache data structure
-- @param server the server to fetch the file from
-- @param location the location on the server
-- @return bool
-- @return an error object on failure
function writeback(cache, server, location, flags)
	e2lib.log(4, string.format("writeback(): %s %s %s", cache.name, 
						server, location))
	local e = new_error("writeback failed")
	local rc, re
	local ce, re = ce_by_server(cache, server)
	if not ce then
		return false, e:cat(re)
	end
	local ceurl, re = url.parse(ce.cache_url)
	if not ceurl then
		return false, e:cat(re)
	end
	if flags.writeback == false or
	   (ce.flags.writeback == false and flags.writeback ~= true) then
		return true, nil
	end
	local sourcefile = string.format("/%s/%s", ceurl.path, location)
	rc, re = transport.push_file(sourcefile, ce.remote_url, location,
						ce.flags.push_permissions,
						flags.try_hardlink)
	if not rc then
		return false, e:cat(re)
	end
	return true, nil
end

--- cache a file
-- @param cache the cache data structure
-- @param server the server to fetch the file from
-- @param location the location on the server
-- @return bool
-- @return an error object on failure
function cache_file(cache, server, location, flags)
	e2lib.log(4, string.format("cache_file(): %s %s %s %s",
		tostring(cache), tostring(server), tostring(location), 
		tostring(flags)))
	local e = new_error("caching file failed")
	local rc, re
	local ce, re = ce_by_server(cache, server)
	if not ce then
		return false, e:cat(re)
	end
	if not ce.flags.cache then
		return true, nil
	end
	local ceurl, re = url.parse(ce.cache_url)
	if not ceurl then
		return false, e:cat(re)
	end
	local avail, re = file_in_cache(cache, server, location)
	if avail and flags.check_only then
		-- file is in the cache and just checking was requested
		return true, nil
	end
	if avail and not flags.refresh then
		-- file is in the cache and no refresh requested
		return true, nil
	end
	local destdir = string.format("/%s/%s", ceurl.path, 
					e2lib.dirname(location))
	-- fetch the file to the cache
	rc, re = transport.fetch_file(ce.remote_url, location, destdir, nil)
	if not rc then
		return false, e:cat(re)
	end
	return true, nil
end

--- get path to a cached file or a file on a local server
-- The user must cache the file first using cache.cache_file()
-- @param cache the cache data structure
-- @param server the server where the file is located
-- @param location the location on the server
-- @return string the path to the cached file, nil on error
-- @return an error object on failure
function file_path(cache, server, location, flags)
	e2lib.log(4, string.format("file_path(): %s %s %s", 
					cache.name, server, location))
	local rc, re
	local e = new_error("providing file path failed")
	-- get the cache entry
	local ce, re = ce_by_server(cache, server)
	if not ce then
		return nil, e:cat(re)
	end
	if ce.flags.cache then
		-- cache enabled. cache the file and return path to cached
		-- file
		local path, re = transport.file_path(ce.cache_url, location)
		if not path then
			return nil, e:cat(re)
		end
		return path, nil
	end
	-- try if the transport delivers a path directly (works for file://)
	local path, re = transport.file_path(ce.remote_url, location)
	if not path then
		e:append("Enable caching for this server.")
		return nil, e:cat(re)
	end
	return path, nil
end
