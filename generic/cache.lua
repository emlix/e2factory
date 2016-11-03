--- Cache
-- @module generic.cache

-- Copyright (C) 2007-2016 emlix GmbH, see file AUTHORS
--
-- This file is part of e2factory, the emlix embedded build system.
-- For more information see http://www.e2factory.org
--
-- e2factory is a registered trademark of emlix GmbH.
--
-- e2factory is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
-- more details.

local cache = {}
package.loaded["cache"] = cache -- stop module loading loop

local e2lib = require("e2lib")
local err = require("err")
local strict = require("strict")
local transport = require("transport")
local url = require("url")

--- Vector for keeping delayed flag options,
-- set to false once options are processed.
-- @field table containing the following fields:
-- @field server server name, validated later
-- @field flag operation name, currently only "writeback"
-- @field value value for operation
-- @see cache.setup_cache_apply_opts
-- @see cache.set_writeback
local _opts = {
    -- { server=.., flag=.., value=.. },
    -- ...
}

--- Internal representation of a cache. This table is locked.
-- @table cache
-- @field _name Human readable name.
-- @field _url Cache base url.
-- @field _ce Cache entries dict, indexed by server name.
-- @see cache_entry

--- Cache entry. Represents a server or alias. This table is locked.
-- @table cache_entry
-- @field server Server name, like "projects".
-- @field remote_url Remote server URL.
-- @field cache_url Cache URL (must be a file:/// url), or false if no cache.
-- @field flags default flags for this cache entry

--- flags influencing the caching behaviour
-- @class table
-- @name flags
-- @field cachable treat a server as cachable?

--- Create a new cache.
-- @param name Cache name.
-- @param url base url for this cache, must use file transport
-- @return a cache table
local function new_cache(name, url)
    local c = {}
    c._name = name
    c._url = url
    c._ce = {}

    e2lib.logf(4, "Cache: %s", c._name)
    e2lib.logf(4, " url: %s", c._url)

    return strict.lock(c)
end

--- Setup cache from the global server configuration
-- @param config global config table
-- @return a cache object
-- @return an error object on failure
function cache.setup_cache(config)
    assertIsTable(config)

    local e = err.new("setting up cache failed")

    if type(config.cache) ~= "table" or type(config.cache.path) ~= "string" then
        return false, e:append("invalid cache configuration: config.cache.path")
    end

    local replace = { u = e2lib.globals.osenv["USER"] }
    local cache_path = e2lib.format_replace(config.cache.path, replace)
    local cache_url = string.format("file://%s", cache_path)
    local c, re = new_cache("local cache", cache_url)
    if not c then
        return false, e:cat(re)
    end
    for name,server in pairs(config.servers) do
        local flags = {}
        flags.cachable = server.cachable
        flags.cache = server.cache
        flags.islocal = server.islocal
        flags.writeback = server.writeback
        flags.push_permissions = server.push_permissions
        local rc, re = cache.new_cache_entry(c, name, server.url, flags)
        if not rc then
            return false, e:cat(re)
        end
    end

    -- It would make sense to check for the required global servers here.
    -- Required meaning servers to fetch a project.

    return c
end

--- Add local servers to the cache configuration. As the name implies,
-- this function should not be called from a global context.
-- @param c cache object
-- @param project_root path to the local project root
-- @param project_location location of the project relative to "upstream".
-- @return True on success, false on error
-- @return Error object on failure.
function cache.setup_cache_local(c, project_root, project_location)
    assertIsTable(c)
    assertIsStringN(project_root)
    assertIsString(project_location)

    local rc, re
    local servers

    servers = cache.server_names()

    rc, re = cache.new_cache_entry(c, servers.dot,
        "file://" .. project_root, { writeback=true },  nil, nil)
    if not rc then
        return false, re
    end

    rc, re = cache.new_cache_entry(c, servers.proj_storage,
        nil, nil, servers.projects, project_location)
    if not rc then
        return false, re
    end

    -- Check for required local servers here. These tests are currently
    -- spread out, but mainly live in policy.init()

    return true
end

--- Apply delayed commandline options once cache is set up and disable
-- the delayed mechanism
-- @param c cache object
-- @return True on success, false on error
-- @return Error object on failure
function cache.setup_cache_apply_opts(c)
    local rc, re, opts

    opts = _opts
    _opts = false -- stop delayed processing

    for _, opt in ipairs(opts) do
        if opt.flag == "writeback" then
            rc, re = cache.set_writeback(c, opt.server, opt.value)
            if not rc then
                return false, re
            end
        else
            return false,
                err.new("unknown delayed option: %s", opt.flag)
        end
    end

    return true
end

local _server_names = strict.lock({
    dot = ".",
    -- the proj_storage server is equivalent to
    --  projects:info.project-locaton
    proj_storage = "proj-storage",
    projects = "projects",
    upstream = "upstream",
    results = "results",
    releases = "releases",
})

--- Return a table of fixed server names whose existence we rely on
-- throughout the program. The table is locked.
-- @return Locked dictionary with fixed server names.
function cache.server_names()
    return _server_names
end

--- get a sorted list of servers
-- @param c a cache table
-- @return table: a list of servers
function cache.servers(c)
    local l = {}
    for server, ce in pairs(c._ce) do
        table.insert(l, server)
    end
    table.sort(l)
    return l
end

local function assertFlags(flags)
    local known = {
        cachable = "boolean",
        cache = "boolean",
        islocal = "boolean",
        push_permissions = "string",
        try_hardlink = "boolean",
        writeback = "boolean",
    }

    assertIsTable(flags)
    for key in pairs(flags) do
        if known[key] == "string" then
            assertIsString(flags[key])
        elseif known[key] == "boolean" then
            assertIsBoolean(flags[key])
        else
            error(err.new("unknown field: flags.%s value: %q type: %s",
                key, tostring(flags[key]), type(flags[key])))
        end
    end
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
    local cache_url = false

    if c._ce[server] then
        return false, e:append("cache entry for server %q exists", server)
    end

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
        cache_url = string.format("%s/%s", c._url, server)
    end
    ru, re = url.parse(remote_url)
    if not ru then
        return false, e:cat(re)
    end
    ce.server = server
    ce.remote_url = ru.url

    assertFlags(flags)

    ce.flags = {}
    ce.flags.cachable = flags.cachable
    ce.flags.cache = flags.cache and flags.cachable
    ce.flags.push_permissions = flags.push_permissions
    ce.flags.writeback = flags.writeback or false
    if flags.islocal ~= nil then
        ce.flags.islocal = flags.islocal
    elseif ru.transport == "file" then
        ce.flags.islocal = true
    else
        ce.flags.islocal = false
    end
    if ce.flags.cache then
        ce.cache_url = cache_url
    else
        ce.cache_url = false
    end

    if c._ce[server] then
        return false, e:append("cache entry for server exists")
    end
    c._ce[server] = strict.lock(ce)
    e2lib.logf(4, "cache entry: %s (%s)", ce.server, c._name)
    e2lib.logf(4, " remote url: %s", ce.remote_url)
    if ce.cache_url then
        e2lib.logf(4, " cache url:  %s", ce.cache_url)
    end
    for k,v in pairs(ce.flags) do
        e2lib.logf(4, " flags:      %-20s = %s", k, tostring(v))
    end
    return true
end

--- get cache entry by url
-- @param c the cache table
-- @param url the server url
-- @return the cache entry table, false on error
-- @return an error object on failure
function cache.ce_by_url(c, url)
    for _,ce in pairs(c.ce) do
        if ce.remote_url == url then
            return ce
        end
    end
    return false, err.new("no cache entry for url: %s", url)
end

--- Get cache entry by server.
-- @param c the cache table
-- @param server the server name
-- @return the cache entry table, false on error
-- @return an error object on failure
function cache.ce_by_server(c, server)
    if c._ce[server] then
        return  c._ce[server]
    end

    return false, err.new("no cache entry for server: %s", server)
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
-- @return the remote url, false on error
-- @return an error object on failure
function cache.remote_url(c, server, location)
    assert(type(c) == "table", "cache invalid")
    assert(type(server) == "string" and server ~= "", "server invalid")
    assert(type(location) == "string" and location ~= "", "location invalid")

    local ce, e = cache.ce_by_server(c, server)
    if not ce then
        return false, e
    end
    local url = string.format("%s/%s", ce.remote_url, location)
    return url
end

--- check if a cache is enabled
-- @param c a cache table
-- @param server the server name
-- @param flags optional flags table
-- @return bool
-- @return an error object on failure
function cache.cache_enabled(c, server, flags)
    assertIsTable(c)
    assertIsStringN(server)
    flags = flags or {}
    assertFlags(flags)

    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end

    if flags.cache == true then
        return true
    elseif ce.flags.cache == true and flags.cache ~= false then
        return true
    end

    return false
end

--- Check if a file is available in the cache
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @param flags optional flags table
-- @return True if file is in cache, false otherwise
-- @return Error object on failure
-- @return Absolute filepath if it is in cache
local function file_in_cache(c, server, location, flags)
    assertIsTable(c)
    assertIsStringN(server)
    assertIsStringN(location)
    flags = flags or {}
    assertFlags(flags)

    if not cache.cache_enabled(c, server, flags) then
        return false
    end

    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end
    local ceurl, re = url.parse(ce.cache_url)
    if not ceurl then
        return false, re
    end
    local cf = e2lib.join("/", ceurl.path, location)
    local rc, re = e2lib.stat(cf)
    if not rc then
        return false
    end
    return true, nil, cf
end

--- Check whether islocal is enabled or not.
-- @param c cache table.
-- @param server server name.
-- @param flags cache flags.
-- @return True if local, false if not.
-- @return Error object on error.
function cache.islocal_enabled(c, server, flags)
    assertIsTable(c)
    assertIsStringN(server)
    flags = flags or {}
    assertFlags(flags)

    local rc, re, ce

    ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end

    if flags.islocal == true then
        return true
    elseif ce.flags.islocal == true and flags.islocal ~= false then
        return true
    end

    return false
end


local function file_is_local(c, server, location, flags)
    assertIsTable(c)
    assertIsStringN(server)
    assertIsStringN(location)
    flags = flags or {}
    assertFlags(flags)

    local rc, re
    local ce, u, filepath

    if not cache.islocal_enabled(c, server, flags) then
        return false
    end

    ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, re
    end

    u, re = url.parse(ce.remote_url)
    if not u then
        return false, re
    end

    if u.transport == "file" then
        filepath = e2lib.join("/", u.path, location)
        rc, re = e2lib.stat(filepath)
        if not rc then
            return false
        end

        return true, nil, filepath
    end

    return false
end

--- cache a file
-- @param c the cache data structure
-- @param server the server to fetch the file from
-- @param location the location on the server
-- @param flags
-- @return bool
-- @return an error object on failure
local function cache_file(c, server, location, flags)
    e2lib.logf(4, "called cache_file from here: %s", debug.traceback("", 2))
    local e = err.new("caching file failed: %s:%s", server, location)
    local rc, re
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end
    assertFlags(flags)

    if not cache.cache_enabled(c, server, flags) then
        return false, e:append("caching is disabled")
    end

    local ceurl, re = url.parse(ce.cache_url)
    if not ceurl then
        return false, e:cat(re)
    end
    local avail, re = file_in_cache(c, server, location)
    if re then
        return false, e:cat(re)
    end
    if not avail then
        local destdir = e2lib.join("/", ceurl.path, e2lib.dirname(location))
        -- fetch the file to the cache
        rc, re = transport.fetch_file(ce.remote_url, location,
            destdir, e2lib.basename(location))
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- fetch a file from a server, with caching in place
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @param destdir where to store the file locally
-- @param destname filename of the fetched file (optional)
-- @param flags table of flags (optional)
-- @return bool
-- @return an error object on failure
function cache.fetch_file(c, server, location, destdir, destname, flags)
    assertIsTable(c)
    assertIsStringN(server)
    assertIsStringN(location)
    assertIsStringN(destdir)
    destname = destname or e2lib.basename(location)
    assertIsStringN(destname)
    flags = flags or {}
    assertFlags(flags)

    local rc, re
    local e = err.new("cache: fetching file failed")
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end

    if cache.cache_enabled(c, server, flags) then
        -- cache is enabled:
        -- fetch from source to cache and from cache to destination
        rc, re = cache_file(c, server, location, flags)
        if not rc then
            return false, e:cat(re)
        end
        rc, re = transport.fetch_file(ce.cache_url, location, destdir, destname)
        if not rc then
            return false, e:cat(re)
        end
    else
        -- cache is disabled:
        -- fetch from source to destination
        rc, re = transport.fetch_file(ce.remote_url, location, destdir, destname)
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- Return file path to requested file. The pathname may either point to
-- the cache, local server or to a temporary file. Do not modify the file!
-- If the filepath points to a temporary copy, the third return value
-- is true.
-- @param c a cache table
-- @param server the server name
-- @param location location relative to the server url
-- @param flags table of flags (optional)
-- @return filepath to requested file or false on error
-- @return error object on failure
-- @return true if temporary file, nil otherwise
function cache.fetch_file_path(c, server, location, flags)
    assertIsTable(c)
    assertIsStringN(server)
    assertIsStringN(location)
    flags = flags or {}
    assertFlags(flags)

    local rc, re, e
    local ce, filepath

    e = err.new("fetching file to provide file path failed")
    ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end

    -- If you enabled the cache, you probably prefer files from there
    if cache.cache_enabled(c, server, flags) then
        rc, re = cache_file(c, server, location, flags)
        if not rc then
            return false, e:cat(re)
        end

        rc, re, filepath = file_in_cache(c, server, location, flags)
        if not rc and re then
            return false, e:cat(re)
        end

        assertTrue(rc)
        assertIsNil(re)
        assertIsStringN(filepath)
        return filepath
    end

    -- Second choice, the local filesystem
    rc, re, filepath = file_is_local(c, server, location, flags)
    if not rc and re then
        return false, e:cat(re)
    elseif rc then
        assertIsNil(re)
        assertIsStringN(filepath)
        return filepath
    end

    -- OK, we're getting a copy for you.
    filepath, re = e2lib.mktempdir()
    if not filepath then
        return false, e:cat(re)
    end
    -- preserve the original name for file suffix info etc.
    filepath = e2lib.join(filepath, e2lib.basename(location))

    rc, re = cache.fetch_file(c, server, location, e2lib.dirname(filepath),
        e2lib.basename(filepath), flags)
    if not rc then
        return false, e:cat(re)
    end

    return filepath, nil, true
end

--- Check whether file exists in cache, locally or remote. Please note
-- error detection doesn't work in all cases, eg. it's difficult to
-- determine whether a file doesn't exists or there's just a connection problem.
-- @param c cache
-- @param server server name
-- @param location path on server
-- @param flags table of flags (optional)
-- @return true if file exists, false otherwise
-- @return error object if there was an detectable error
function cache.file_exists(c, server, location, flags)
    assertIsTable(c)
    assertIsStringN(server)
    assertIsStringN(location)
    flags = flags or {}
    assertFlags(flags)

    local rc, re, e
    local ce

    e = err.new("cache: file_exists failed")
    ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end

    if cache.cache_enabled(c, server, flags) then
        rc, re = file_in_cache(c, server, location, flags)
        if re then
            return false, e:cat(re)
        end

        if rc then
            return true
        end
    end

    rc, re = transport.file_exists(ce.remote_url, location)
    if re then
        return false, e:cat(re)
    end

    return rc
end

--- writeback a cached file
-- @param c the cache data structure
-- @param server Server to write the file back to.
-- @param location Path to the file in cache and on the server.
-- @param flags
-- @return bool
-- @return an error object on failure
local function cache_writeback(c, server, location, flags)
    local e = err.new("writeback failed")
    local rc, re
    assertFlags(flags)

    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end

    local ceurl, re = url.parse(ce.cache_url)
    if not ceurl then
        return false, e:cat(re)
    end

    if cache.writeback_enabled(c, server, flags) == false then
        return true
    end

    local sourcefile = string.format("/%s/%s", ceurl.path, location)
    rc, re = transport.push_file(sourcefile, ce.remote_url, location,
        ce.flags.push_permissions, flags.try_hardlink)
    if not rc then
        return false, e:cat(re)
    end
    return true
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
    flags = flags or {}
    assertFlags(flags)

    local rc, re
    local e = err.new("error pushing file to cache/server")
    local ce, re = cache.ce_by_server(c, server)
    if not ce then
        return false, e:cat(re)
    end

    if cache.cache_enabled(c, server, flags) then
        -- cache is enabled:
        -- push the file from source to cache and from cache to
        -- destination
        rc, re = transport.push_file(sourcefile, ce.cache_url,
            location, nil, flags.try_hardlink)
        if not rc then
            return false, e:cat(re)
        end

        rc, re = cache_writeback(c, server, location, flags)
        if not rc then
            return false, e:cat(re)
        end
    else
        -- cache is disabled
        -- push the file from source to destination immediately
        rc, re = transport.push_file(sourcefile, ce.remote_url,
            location, ce.flags.push_permissions, flags.try_hardlink)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true
end

--- Query whether writeback is true for this particular server and flags
-- combination. Returns true if writeback is on, false otherwise.
-- Throws an error on failure.
-- @param c Cache.
-- @param server Server name.
-- @param flags Flags table.
-- @return Boolean state of writeback.
function cache.writeback_enabled(c, server, flags)
    assert(type(c) == "table", "invalid cache")
    assert(type(server) == "string" and server ~= "", "invalid server")
    flags = flags or {}
    assertFlags(flags)

    local ce, re

    ce, re = cache.ce_by_server(c, server)
    if not ce then
        error(re)
    end

    if flags.writeback == false then
        return false
    elseif ce.flags.writeback == false and flags.writeback ~= true then
        return false
    end

    return true
end

--- enable/disable writeback for a server
-- @param c the cache data structure or nil when the cache is not yet set up
-- @param server the server where the file is located
-- @param value boolean: the new setting
-- @return boolean
-- @return an error object on failure
function cache.set_writeback(c, server, value)

    if _opts then
        e2lib.logf(3, "delaying cache.set_writeback(%s, %s, %s)",
            tostring(c), tostring(server), tostring(value))
        table.insert(_opts,
            { flag = "writeback", server = server, value = value })

        return true
    end

    assertIsTable(c)

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
    return true
end

return strict.lock(cache)

-- vim:sw=4:sts=4:et:
