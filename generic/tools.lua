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
require("buildconfig")

local toollist = {
    which = { name = "which", flags = "", optional = false },
    curl = { name = "curl", flags = "", optional = false },
    ssh = { name = "ssh", flags = "", optional = false },
    scp = { name = "scp", flags = "", optional = false },
    rsync = { name = "rsync", flags = "", optional = false },
    git = { name = "git", flags = "", optional = false },
    cvs = { name = "cvs", flags = "", optional = true },
    svn = { name = "svn", flags = "", optional = true },
    mktemp = { name = "mktemp", flags = "", optional = false },
    rm = { name = "rm", flags = "", optional = false },
    mkdir = { name = "mkdir", flags = "", optional = false },
    rmdir = { name = "rmdir", flags = "", optional = false },
    cp = { name = "cp", flags = "", optional = false },
    ln = { name = "ln", flags = "", optional = false },
    mv = { name = "mv", flags = "", optional = false },
    tar = { name = "tar", flags = "", optional = false },
    sha1sum = { name = "sha1sum", flags = "", optional = false },
    md5sum = { name = "md5sum", flags = "", optional = false },
    chown = { name = "chown", flags = "", optional = false },
    chmod = { name = "chmod", flags = "", optional = false },
    test = { name = "test", flags = "", optional = false },
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

--- get a tool command
-- @param name string: the tool name
-- @return string: the tool command, nil on error
function tools.get_tool(name)
    if not toollist[name] then
        e2lib.bomb("looking up invalid tool: " .. tostring(name))
    end
    return toollist[name].path
end

--- get tool flags
-- @param name string: the tool name
-- @return string: the tool flags
function tools.get_tool_flags(name)
    if not toollist[name] then
        e2lib.bomb("looking up flags for invalid tool: " ..
        tostring(name))
    end
    return toollist[name].flags or ""
end

--- set a tool command and flags
-- @param name string: the tool name
-- @param value string: the new tool command
-- @param flags string: the new tool flags. Optional.
-- @return bool
-- @return nil, an error string on error
function tools.set_tool(name, value, flags)
    if not toollist[name] then
        return false, "invalid tool setting"
    end
    if type(value) == "string" then
        toollist[name].name = value
    end
    if type(flags) == "string" then
        toollist[name].flags = flags
    end
    e2lib.logf(3, "setting tool: %s=%s flags=%s", name, toollist[name].name,
        toollist[name].flags)
    return true, nil
end

--- add a new tool
-- @param name string: the tool name
-- @param value string: the new tool command
-- @param flags string: the new tool flags.
-- @param optional bool: wheter the tool is optional or not
-- @return bool
-- @return nil, an error string on error
function tools.add_tool(name, value, flags, optional)
    if toollist[name] then
        e2lib.bomb("trying to add a tool that already exists: " ..
        tostring(name))
    end

    if type(name) ~= "string" or type(value) ~= "string" or
        type(flags) ~= "string" or type(optional) ~= "boolean" then
        print("error in add_tool")
        e2lib.bomb("one or more parameters wrong while adding tool " ..
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

    return true, nil
end

--- check if a tool is available
-- @param name string a valid tool name
-- @return bool
-- @return nil, an error string on error
function tools.check_tool(name)
    local tool = toollist[name]
    if not tool.path then
        local which = string.format("which \"%s\"", tool.name)
        local p = io.popen(which, "r")
        tool.path = p:read()
        p:close()
        if not tool.path then
            e2lib.logf(3, "tool not available: %s", tool.name)
            return false, "tool not available"
        end
    end
    e2lib.logf(4, "tool available: %s (%s)", tool.name, tool.path)

    return true
end

--- initialize the library
-- @return bool
function tools.init()
    local error = false
    for tool,t in pairs(toollist) do
        local rc = tools.check_tool(tool)
        if not rc then
            local warn = "Warning"
            if not t.optional then
                error = true
                warn = "Error"
            end
            e2lib.logf(1, "%s: tool is not available: %s", warn, tool)
        end
    end
    if error then
        return false, "missing mandatory tools"
    end
    return true, nil
end

return strict.lock(tools)

-- vim:sw=4:sts=4:et:
