--- Cache
-- @module generic.cache

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

local cache = {}
local e2lib = require("e2lib")
local transport = require("transport")
local url = require("url")
local err = require("err")
local strict = require("strict")

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
function cache.new_cache(name, url)
    local c = {}
    c.name = name
    c.url = url
    c.ce = {}

    e2lib.logf(4, "Cache: %s", c.name)
    e2lib.logf(4, " url: %s", c.url)

    local meta = { __index = cache }
    setmetatable(c, meta)

    return c
end

--- get a sorted list of servers
-- @param c a cache table
-- @return table: a list of servers
function cache.servers(c)
    local l = {}
    for server, ce in pairs(c.ce) do
        table.insert(l, server)
    end
    table.sort(l)
    return l
end

--- create a new cache entry
-- @param c a cache table
-- @param server the remote server name
-- @param remote_url the remote server to cache (server setup)
-- @param flags (server setup)
-- @param alias_server alias server (alias setup)
-- @param alias_location location relative to alias server (alias setup)
-- @return true on success, false on error
-- @return an error object on failure
function cache.new_cache_entry(c, server, remote_url, flags, alias_server,
    alias_location)
    assert(((remote_url and flags) or (alias_server and alias_location))
    and not
    ((remote_url and flags) and (alias_server and alias_location)))
    local ru, cu
    local rc, re
    local e = err.new("error setting up cache entry")
    local ce = {}
    local cache_url = nil
    if not remote_url then
        -- setting up an alias
        local alias_ce, re = cache.ce_by_server(c, alias_server)
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
        cache_url = string.format("%s/%s", c.url, server)
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
    if c.ce[server] then
        return false, e:append("cache entry for server exists")
    end
    c.ce[server] = ce
    e2lib.logf(4, "cache entry: %s (%s)", ce.server, c.name)
    e2lib.logf(4, " remote url: %s", ce.remote_url)
    e2lib.logf(4, " cache url:  %s", tostring(ce.cache_url))
    for k,v in pairs(ce.flags) do
        e2lib.logf(4, " flags:      %-20s = %s", k, tostring(v))
    end
    return true, nil
end

--- get cache entry by url
-- @param c the cache table
-- @param url the server url
-- @return the cache entry table, nil on error
-- @return an error object on failure
function cache.ce_by_url(c, url)
    for _,ce in pairs(c.ce) do
        if ce.remote_url == url then
            return ce, nil
        end
    end
    return nil, err.new("no cache entry for url: %s", url)
end

--- get cache entry by server
-- @param c the cache table
-- @param server the server name
-- @return the cache entry table, nil on error
-- @return an error object on failure
function cache.ce_by_server(c, server)
    for _,ce in pairs(c.ce) do
        if ce.server == server then
            return ce, nil
        end
    end
    return nil, err.new("no cache entry for server: %s", server)
end

--- check if server is valid
-- @param c the cache table
-- @param server the server name
-- @return true if the server is valid, false otherwise
-- @return an error object on failure
function cache.valid_server(c, server)
    if cache.ce_by_server(c, server) then
        return true
    else
        return false, err.new("not a valid server: %s", server)
    end
end

--- get remote url
-- for use in scm implementations where urls need to be handled manually
-- @param c the cache table
-- @param server the server name
-- @param location the location relative to the server
-- @return the remote url, nil on error
-- @return an error object on failure
function cache.remote_url(c, server, location)
    local ce, e = cache.ce_by_server(c, server)
    if not ce then
        return nil, e
    end
    local url = string.format("%s/%s", ce.remote_url, location)
    return url
end

--- check if a cache is enabled
-- @param c a cache table
-- @param server the server name
-- @return bool
-- @return an error object on failure
function cache.cache_enabled(c, server)
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end
    return ce.flags.cache
end

--- check if a file is available in the cache
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @return bool
-- @return an error object on failure
function cache.file_in_cache(c, server, location)
    local ce, re = cache.ce_by_server(c, server)
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
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @return bool
-- @return an error object on failure
function cache.file_local(c, server, location)
    local rc, re = file_in_cache(c, server, location)
    if re then
        return false, re
    end
    if rc then
        return true, nil
    end
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end
    if ce.islocal == false then
        return false
    end
    local path, re = cache.file_path(c, server, location)
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
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @param destdir where to store the file locally
-- @param destname filename of the fetched file
-- @param flags table of flags
-- @return bool
-- @return an error object on failure
function cache.fetch_file(c, server, location, destdir, destname, flags)
    local rc, re
    local e = err.new("cache: fetching file failed")
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end
    if not destname then
        destname = e2lib.basename(location)
    end
    -- fetch the file
    if ce.flags.cache and flags.cache ~= false then
        -- cache is enabled:
        -- fetch from source to cache and from cache to destination
        rc, re = cache.cache_file(c, server, location, flags)
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
        rc, re = e2lib.chmod(e2lib.join(destdir, destname), flags.chmod)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

--- push a file to a server: cache and writeback
-- @param c a cache table
-- @param sourcefile where to store the file locally
-- @param server the server name
-- @param location location relative to the server url
-- @param flags table of flags
-- @return bool
-- @return an error object on failure
function cache.push_file(c, sourcefile, server, location, flags)
    local rc, re
    local e = err.new("error pushing file to cache/server")
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end
    if ce.flags.cache and flags.cache ~= false then
        -- cache is enabled:
        -- push the file from source to cache and from cache to
        -- destination
        rc, re = transport.push_file(sourcefile, ce.cache_url,
        location, nil, flags.try_hardlink)
        if not rc then
            return false, e:cat(re)
        end
        rc, re = cache.writeback(c, server, location, flags)
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
-- @param c the cache data structure
-- @param server the server to fetch the file from
-- @param location the location on the server
-- @param flags
-- @return bool
-- @return an error object on failure
function cache.writeback(c, server, location, flags)
    local e = err.new("writeback failed")
    local rc, re
    local ce, re = cache.ce_by_server(c, server)
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
-- @param c the cache data structure
-- @param server the server to fetch the file from
-- @param location the location on the server
-- @param flags
-- @return bool
-- @return an error object on failure
function cache.cache_file(c, server, location, flags)
    local e = err.new("caching file failed: %s:%s", server, location)
    local rc, re
    local ce, re = cache.ce_by_server(c, server)
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
    local avail, re = cache.file_in_cache(c, server, location)
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
-- @param c the cache data structure
-- @param server the server where the file is located
-- @param location the location on the server
-- @param flags unused parameter
-- @return string the path to the cached file, nil on error
-- @return an error object on failure
function cache.file_path(c, server, location, flags)
    local rc, re
    local e = err.new("providing file path failed")
    -- get the cache entry
    local ce, re = cache.ce_by_server(c, server)
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

--- enable/disable writeback for a server
-- @param c the cache data structure
-- @param server the server where the file is located
-- @param value boolean: the new setting
-- @return boolean
-- @return an error object on failure
function cache.set_writeback(c, server, value)
    if type(value) ~= "boolean" then
        return false, err.new(
        "cache.set_writeback(): value is not boolean")
    end
    local rc, re = cache.valid_server(c, server)
    if not rc then
        return false, re
    end
    local ce, re = cache.ce_by_server(c, server)
    if not rc then
        return false, re
    end
    ce.flags.writeback = value
    return true, nil
end

return strict.lock(cache)

-- vim:sw=4:sts=4:et:
