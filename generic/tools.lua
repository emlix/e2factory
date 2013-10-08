--- External Tools Support.
-- @module generic.tools

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

local tools = {}
local e2lib = require("e2lib")
local strict = require("strict")
local buildconfig = require("buildconfig")

local initialized = false

local toollist = {
    curl = { name = "curl", flags = "", optional = false },
    ssh = { name = "ssh", flags = "", optional = false },
    scp = { name = "scp", flags = "", optional = false },
    rsync = { name = "rsync", flags = "", optional = false },
    git = { name = "git", flags = "", optional = false },
    cvs = { name = "cvs", flags = "", optional = true },
    svn = { name = "svn", flags = "", optional = true },
    man = { name = "man", flags = "-l", optional = true },
    cp = { name = "cp", flags = "", optional = false },
    mv = { name = "mv", flags = "", optional = false },
    tar = { name = "tar", flags = "", optional = false },
    sha1sum = { name = "sha1sum", flags = "", optional = false },
    md5sum = { name = "md5sum", flags = "", optional = false },
    cat = { name = "cat", flags = "", optional = false },
    touch = { name = "touch", flags = "", optional = false },
    uname = { name = "uname", flags = "", optional = false },
    patch = { name = "patch", flags = "", optional = false },
    gzip = { name = "gzip", flags = "", optional = false },
    bzip2 = { name = "bzip2", flags = "", optional = false },
    unzip = { name = "unzip", flags = "", optional = false },
    ["e2-su-2.2"] = { name = buildconfig.PREFIX .. "/bin/e2-su-2.2",
    flags = "", optional = false },
}

--- Get a absolute tool command.
-- @param name Tool name (string).
-- @return Tool command or false on error.
-- @return Error object on failure.
function tools.get_tool(name)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end
    return toollist[name].path
end

--- Get tool flags.
-- @param name Tool name (string).
-- @return Tool flags as a string, potentially empty - or false on error.
-- @return Error object on failure.
function tools.get_tool_flags(name)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end
    return toollist[name].flags or ""
end

--- Get tool name.
-- @param name Tool name (string).
-- @return Tool name field (string) used to find tool in PATH or false on error.
-- @return Error object on failure.
function tools.get_tool_name(name)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end
    return toollist[name].name
end

--- Set a tool command and flags.
-- @param name Tool name (string).
-- @param value Tool command (string). May also be an absolute command.
-- @param flags Tool flags (string). Optional.
-- @return True on success, false on error.
-- @return Error object on failure.
function tools.set_tool(name, value, flags)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end
    if type(value) == "string" then
        toollist[name].name = value
    end
    if type(flags) == "string" then
        toollist[name].flags = flags
    end
    e2lib.logf(3, "setting tool: %s=%s flags=%s", name, toollist[name].name,
        toollist[name].flags)
    return true
end

--- Add a new tool.
-- @param name Tool name (string).
-- @param value Tool command, may contain absolute path (string).
-- @param flags Tool flags (string). May be empty.
-- @param optional Whether the tool is required (true) or optional (false).
-- @return True on success, false on error.
-- @return Error object on failure.
function tools.add_tool(name, value, flags, optional)
    if toollist[name] then
        return false, err.new("tool '%s' already registered in tool list", name)
    end

    if type(name) ~= "string" or type(value) ~= "string" or
        type(flags) ~= "string" or type(optional) ~= "boolean" then
        return false,
            err.new("one or more parameters wrong while adding tool %s",
                tostring(name))
    end

    toollist[name] = {
        name = value,
        flags = flags,
        optional = optional,
    }

    local t = toollist[name]
    e2lib.logf(3, "adding tool: %s=%s flags=%s optional=%s", name, t.name,
        t.flags, tostring(t.optional))

    return true
end

--- Check if a tool is available.
-- @param name string a valid tool name
-- @return True if tool exists, otherwise false. False may also indicate an
--         error, if the second return value is not nil.
-- @return Error object on failure.
function tools.check_tool(name)
    local tool, which, p
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end

    tool = toollist[name]
    if not tool.path then
        which = string.format("which \"%s\"", tool.name)
        p = io.popen(which, "r")
        tool.path = p:read()
        p:close()
        if not tool.path then
            return false
        end
    end
    return true
end

--- Initialize the tools library. Must be called before the tools library can
-- be used. Logs a warning about missing optional tools.
-- @return True on success (all required tools have been found), false on error.
-- @return Error object on failure.
function tools.init()
    local rc, re

    for tool, t in pairs(toollist) do
        rc, re = tools.check_tool(tool)
        if not rc and re then
            return false, re
        end
        if not rc then
            if t.optional then
                e2lib.warnf("optional tool is not available: %s", tool)
            else
                return false, err.new("required tool is missing: %s", tool)
            end
        end
    end

    initialized = true

    return true
end

--- Check whether the tools library is initialized. There is no error condition.
-- @return True or false.
function tools.isinitialized()
    return initialized
end

return strict.lock(tools)

-- vim:sw=4:sts=4:et:
