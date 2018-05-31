--- External Tools Support.
-- @module generic.tools

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

local tools = {}
local e2lib = require("e2lib")
local err = require("err")
local strict = require("strict")
local buildconfig = require("buildconfig")

local initialized = false

local toollist = {
    -- default tool list in tools.add_default_tools()
}

--- Get absolute path to tool command.
-- @param name Tool name (string).
-- @return Tool path or false on error.
-- @return Error object on failure.
function tools.get_tool_path(name)
    local rc, re

    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end

    if not toollist[name].path then
        rc, re = tools.check_tool(name)
        if not rc and re then
            return rc, re
        end

        if not toollist[name].path then
            return false, err.new("tool '%s' could not be found in path")
        end
    end

    return toollist[name].path
end

--- Get a absolute tool command. Deprecated.
-- @param name Tool name (string).
-- @return Tool command or false on error.
-- @return Error object on failure.
function tools.get_tool(name)
    return tools.get_tool_path(name)
end

--- Split tool flags into a vector of arguments.
-- @param flags Tool flags.
-- @return Vector containing tool arguments or false on error.
-- @return Error object on failure.
local function parse_tool_flags(flags)
    local tokens, c, fields, field, state, esc

    state = 0 -- 0 default, 1 doublequote, 2 singlequote string
    esc = false -- previous character was a escape \ if true
    field = ""
    fields = {}

    for i=1,string.len(flags) do
        c = string.sub(flags, i, i)
        if state == 0 and (c == " " or c == "\t" or c == "\n") then
            if field ~= "" then
                table.insert(fields, field)
                field = ""
            end
            -- skip all IFS
        elseif c == '\\' then
            esc = true
            -- may add \ back later
        elseif not esc and c == '"' and (state == 0 or state == 1) then
            if state == 1 then
                state = 0
            else
                state = 1
            end
            -- double quotes get removed
        elseif c == "'" and (state == 0 or state == 2) then
            if state == 2 then
                state = 0
            else
                state = 2
            end
            -- single quotes get removed
        else
            if esc and (state == 0 or state == 1) then
                if c == "\\" then
                    field = field .. "\\"
                elseif c == '"' then
                    field = field .. '"'
                elseif c == "'" then
                    field = field .. "'"
                else
                    field = field .. "\\" .. c
                end
                esc = false
            elseif esc and state == 2 then
                -- no escape from the single quote
                field = field .. "\\" .. c
                esc = false
            else
                field = field .. c
            end
        end
    end

    if field ~= "" then
        table.insert(fields, field)
    end

    if state ~= 0 or esc ~= false then
        return false,
            err.new("escape or quoting missmatch in tool flags %q", flags)
    end

    return fields
end

--- Get tool flags.
-- @param name Tool name (string).
-- @return Vector containing tool flags. Vector may be empty for no flags,
--         or false if an error occured.
-- @return Error object on failure.
function tools.get_tool_flags(name)
    local flags, re
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end

    if not toollist[name].flagstbl then
        flags, re = parse_tool_flags(toollist[name].flags)
        if not flags then
            return false, re
        end
        toollist[name].flagstbl = flags
    end


    return toollist[name].flagstbl
end

--- Get tool and flags in one vector
-- @param name Tool name (string).
-- @return Vector containing path to tool binary and its flags if any.
--         False on error.
-- @return Error object on failure.
function tools.get_tool_flags_argv(name)
    local rc, re, new

    rc, re = tools.get_tool_path(name)
    if not rc then
        return false, re
    end

    new = { rc }

    rc, re = tools.get_tool_flags(name)
    if not rc then
        return false, re
    end

    for _,flag in ipairs(rc) do
        table.insert(new, flag)
    end

    return new
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

--- Set a tool command and flags. Value, flags and enable are optional.
-- @param name Tool name (string).
-- @param value Tool command (string). May also be an absolute command.
-- @param flags Tool flags (string). Optional.
-- @param enable Should the tool be used? Optional.
-- @return True on success, false on error.
-- @return Error object on failure.
function tools.set_tool(name, value, flags, enable)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end

    if type(value) == "string" then
        toollist[name].name = value
        toollist[name].path = nil -- reset
    elseif value ~= nil then
        return false, err.new("tool '%s' value invalid", name)
    end

    if type(flags) == "string" then
        toollist[name].flags = flags
        toollist[name].flagstbl = nil -- reset
    elseif flags ~= nil then
        return false, err.new("tool '%s' flags invalid", name)
    end

    if type(enable) == "boolean" then
        toollist[name].enable = enable
    elseif enable ~= nil then
        return false, err.new("tool '%s' enable invalid", name)
    end

    e2lib.logf(4, "setting tool: %s=%s flags=%s", name, toollist[name].name,
        toollist[name].flags, toollist[name].enable)
    return true
end

--- Add a new tool.
-- @param name Tool name (string).
-- @param value Tool command, may contain absolute path (string).
-- @param flags Tool flags (string). May be empty.
-- @param optional Whether the tool is required (true) or optional (false).
-- @param enable Whether the tool should be used or not.
--               Only makes sense if optional. Defaults to true if not optional.
-- @return True on success, false on error.
-- @return Error object on failure.
function tools.add_tool(name, value, flags, optional, enable)
    if type(name) ~= "string" or
        (value ~= nil and type(value) ~= "string") or
        (flags ~= nil and type(flags) ~= "string") or
        (optional ~= nil and type(optional) ~= "boolean") or
        (enable ~= nil and type(enable) ~= "boolean") then
        return false,
            err.new("one or more parameters wrong while adding tool %s",
                tostring(name))
    end

    if toollist[name] then
        return false, err.new("tool '%s' already registered in tool list", name)
    end

    if value == nil then
        value = name
    end

    if flags == nil then
        flags = ""
    end

    if optional == nil then
        optional = false
    end

    if enable == nil then
        if optional then
            enable = false
        else
            enable = true
        end
    end

    toollist[name] = {
        name = value,
        -- path,
        flags = flags,
        -- flagstbl,
        optional = optional,
        enable = enable,
    }

    local t = toollist[name]
    e2lib.logf(4, "adding tool: %s=%s flags=%s optional=%s enable=%s", name,
        t.name, t.flags, tostring(t.optional), tostring(t.enable))

    return true
end

--- Populate the tools module with the default tools.
function tools.add_default_tools()
    local rc, re
    local defaults = {
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
        patch = { name = "patch", flags = "", optional = false },
        gzip = { name = "gzip", flags = "", optional = false },
        unzip = { name = "unzip", flags = "", optional = false },
        ["e2-su-2.2"] = { name = buildconfig.BINDIR .. "/e2-su-2.2",
        flags = "", optional = false },
    }

    for name, t in pairs(defaults) do
        rc, re = tools.add_tool(name, t.name, t.flags, t.optional, t.enable)
        if not rc then
            e2lib.abort(re)
        end
    end
end


--- Check if a tool is available and resolve its absolute path.
-- @param name string a valid tool name
-- @return True if tool exists, otherwise false. False may also indicate an
--         error, if the second return value is not nil.
-- @return Error object on failure.
function tools.check_tool(name)
    local rc, re, which, p, out
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end

    if not toollist[name].path then
        if string.sub(toollist[name].name, 1, 1) == "/" then
            p = toollist[name].name
        else
            -- relative path
            out = {}
            local function capture(msg)
                table.insert(out, msg)
            end

            which = { "which", toollist[name].name }
            rc, re = e2lib.callcmd_capture(which, capture)
            if not rc then
                return false, re
            elseif rc ~= 0 then
                return false
            end

            p = string.sub(table.concat(out), 1, -2)
        end

        if not e2lib.exists(p, true) then
            return false,
                err.new("tool %q not found at %q", tool.name, p)
        end

        toollist[name].path = p
    end

    return true
end

--- Query whether an optional tool is enabled or not.
-- @param name Tool name.
-- @return True if enabled, false on error or if not enabled.
-- @return Error object on failure, nil if tool is disabled.
function tools.enabled(name)
    if not toollist[name] then
        return false, err.new("tool '%s' is not registered in tool list", name)
    end
    assertIsBoolean(toollist[name].enable)
    return toollist[name].enable
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
                e2lib.warnf("WHINT", "optional tool is not available: %s", tool)
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
