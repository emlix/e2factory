--- URL Parser.
-- @module generic.url


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

local url = {}
local e2lib = require("e2lib")
local strict = require("strict")

--- parse
-- @param url the url to parse
-- @return a table holding all parsed parts of the url, or nil on error
-- @return nil, or an error string on error
function url.parse(url)
    assert(type(url) == "string" and string.len(url) > 0)

    --- URL object holding all URL parts. Any part but 'url' and
    -- 'transport' is optional and may be nil.
    -- @class table
    -- @name url
    -- @field url Original URL string before parsing.
    -- @field transport Transport (protocol) type as a string eg. http, ssh.
    -- @field server The server part in the form: server, server:port,
    --        user@server, user:pass@server, etc.
    -- @field path Path component of URL. All leading slashes are removed.
    -- @field servername Server name without any other components.
    -- @field user User name from the server part.
    -- @field pass Password from the server part.
    -- @field port Server port.
    local u = strict.lock({})

    local url_members = {
        "url",
        "transport",
        "server",
        "path",
        "servername",
        "user",
        "pass",
        "port"
    }

    strict.declare(u, url_members)

    u.url = url

    -- parse: transport://server/path
    u.transport, u.server, u.path = u.url:match("(%S+)://([^/]*)(.*)")
    if not u.transport then
        return nil, string.format("can't parse url: %s", url)
    end

    -- remove leading slashes from the path
    u.path = u.path:match("^[/]*(.*)")

    -- parse the server part
    if u.server:match("(%S+):(%S+)@(%S+)") then
        -- user:pass@host
        u.user, u.pass, u.servername = u.server:match("(%S+):(%S+)@(%S+)")
    elseif u.server:match("(%S+)@(%S+)") then
        -- user@host
        u.user, u.servername = u.server:match("(%S+)@(%S+)")
    else
        u.servername = u.server
    end

    if u.server:match(":(%d+)$") then
        u.port = u.server:match(":(%d+)$")
        -- Remove port from server string.
        u.server = string.gsub(u.server, ":%d+$","")
        -- Remove port from server string.
        u.servername = string.gsub(u.servername, ":%d+$","")
    end

    return u
end

--- Returns a file path from an URL object.
-- @param u URL object.
-- @param transport Transport of URL object must match this transport. Optional.
-- @param relative Return a relative path if true, otherwise absolute. Optional.
-- @return Path on success, false on error.
-- @return Error object on failure.
function url.to_file_path(u, transport, relative)
    if transport and u.transport ~= transport then
        return false, err.new("converting URL to file path: transport mismatch")
    end

    if type(u.path) ~= "string" then
        return false,
            err.new("converting URL to file path: path component in URL empty")
    end

    if relative then
        return u.path
    end

    return e2lib.join("/", u.path)
end

return strict.lock(url)

-- vim:sw=4:sts=4:et:
