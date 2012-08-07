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

local url = {}

--- parse
-- @param url the url to parse
-- @return a table holding all parsed parts of the url, or nil on error
-- @return nil, or an error string on error
function url.parse(url)
    local u = {}
    --- url
    -- @class table
    -- @name url
    -- @field url the original url as passed to the parse() function
    -- @field transport the transport type
    -- @field server the server part
    -- @field path the path relative to the server
    -- @field servername the server name from the server part
    -- @field user the user name from the server part (optional)
    -- @field pass the password from the server part (optional)
    -- @field port given server port (optional)
    if not url then
        return nil, "missing parameter: url"
    end
    u.url = url
    -- parse: transport://server/path
    u.transport, u.server, u.path =
    u.url:match("(%S+)://([^/]*)(.*)")
    if not u.transport then
        return nil, string.format("can't parse url: %s", url)
    end
    -- remove leading slashes from the path
    u.path = u.path:match("^[/]*(.*)")
    -- parse the server part
    if u.server:match("(%S+):(%S+)@(%S+)") then
        -- user:pass@host
        u.user, u.pass, u.servername =
        u.server:match("(%S+):(%S+)@(%S+)")
    elseif u.server:match("(%S+)@(%S+)") then
        -- user@host
        u.user, u.servername = u.server:match("(%S+)@(%S+)")
    else
        u.servername = u.server
    end
    if u.server:match(":(%d+)$") then
        u.port = u.server:match(":(%d+)$")
        u.server = string.gsub(u.server, ":%d+$","") -- Remove port from server string.
        u.servername = string.gsub(u.servername, ":%d+$","") -- Remove port from server string.
    end
    return u, nil
end

return url

-- vim:sw=4:sts=4:et:
