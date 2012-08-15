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

local e2option = {}
local e2lib = require("e2lib")
require("e2util")
local plugin = require("plugin")
local err = require("err")

-- Parsing of command-line options

local options = {}
local optionlist = {}
local commands = {}
local program_name = arg[0]


-- Option declaration
--
--   documentation -> STRING
--
--     Holds a general description string of the currently executing
--     tool.
--
--   flag(NAME, [DOC, [FUNCTION]])
--
--     Declares a "flag" option (an option without argument) with the given
--     name (a string), documentation string (defaults to "") and a function
--     that will be called when the option is given on the command line.
--
--   option(NAME, [DOC, [DEFAULT, [FUNCTION, [ARGUMENTNAME]]]])
--
--     Declares an option with argument. DEFAULT defaults to "true".
--     ARGUMENTNAME will be used in the generated usage information
--     (see "usage()").
--
--   alias(NAME, OPTION)
--
--     Declares an alias for another option.

-- TODO: Remove from the e2option table, should only be setable through a
-- function
e2option.documentation = "<no documentation available>"

local aliases = {}

--- register a flag option
-- @param name string: option name
-- @param doc string: documentation string
-- @param func a function to call when this option is specified
-- @param category string: category name
-- @return nil
function e2option.flag(name, doc, func, category)
    if options[name] then
        return false, err.new("option exists: %s", name)
    end
    options[name] = {type = "flag", documentation = doc or "", name = name,
    proc=func, default = true,
    category = category}
    table.insert(optionlist, name)
end

--- register an option with argument
-- @param name string: option name
-- @param doc string: documentation string
-- @param default string: default value
-- @param func a function to call when this option is specified
-- @param argname string: argument name used in documentation (optional)
-- @return nil
function e2option.option(name, doc, default, func, argname)
    if options[name] then
        return false, err.new("option exists: %s", name)
    end
    options[name] = {type = "option", documentation = doc or "", name = name,
    proc=func, default=default or true,
    argumentname=argname or "ARGUMENT"}
    table.insert(optionlist, name)
end

--- XXX command(): undocumented, never called. Remove?
function e2option.command(name, doc, func)
    commands[name] = {documentation=doc, command=func, name=name}
end

--- register an alias for an option
-- @param alias string: alias name
-- @param option string: name of the option to register the alias for
-- @return nil
function e2option.alias(alias, option)
    if aliases[alias] then
        e2lib.warn("alias `", alias, "' for option `", option, "' already exists")
    end
    aliases[alias] = option
end


-- Option parsing
--
--   parse(ARGUMENTS) -> TABLE
--
--     Parses the arguments given in ARGUMENTS (usually obtained via "arg")
--     and returns a table with an entry for each option. The entry is stored
--     under the optionname with the value given by the FUNCTION or DEFAULT
--     arguments from the associated option declaration call ("flag()"
--     or "option()"). The result table with additionally contain
--     and entry named "arguments" holding an array of all non-option arguments.
--
--   usage([CODE])
--
--     Prints usage information on io.stdout and either signals an error
--     (if interactive) or exits with status code CODE (defaults to 0).

--- option_table holding options keyed by option name.
-- The special key "arguments" holds a list of non-option command line
-- arguments
-- @class table
-- @name option_table
-- @field arguments list of additional arguments

--- parse options
-- @param args table: command line arguments (usually the arg global variable)
-- @return table: option_table
function e2option.parse(args)
    local function defaultoptions()
        local category = "Verbosity Control Options"
        e2option.option("e2-config", "specify configuration file", nil,
        function(arg)
            e2lib.sete2config(arg)
        end,
        "FILE")
        e2option.flag("quiet", "disable all log levels",
        function()
            e2lib.setlog(1, false)
            e2lib.setlog(2, false)
            e2lib.setlog(3, false)
            e2lib.setlog(4, false)
            return true
        end,
        category)
        e2option.flag("verbose", "enable log levels 1-2",
        function()
            e2lib.setlog(1, true)
            e2lib.setlog(2, true)
            return true
        end,
        category)
        e2option.flag("debug", "enable log levels 1-3",
        function()
            e2lib.setlog(1, true)
            e2lib.setlog(2, true)
            e2lib.setlog(3, true)
            return true
        end,
        category)
        e2option.flag("tooldebug", "enable log levels 1-4",
        function()
            e2lib.setlog(1, true)
            e2lib.setlog(2, true)
            e2lib.setlog(3, true)
            e2lib.setlog(4, true)
            return true
        end,
        category)
        e2option.flag("vall", "enable all log levels",
        function()
            e2lib.setlog(1, true)
            e2lib.setlog(2, true)
            e2lib.setlog(3, true)
            e2lib.setlog(4, true)
            return true
        end,
        category)
        e2option.flag("v1", "enable log level 1 (minimal)",
        function()
            e2lib.setlog(1, true)
            return true
        end,
        category)
        e2option.flag("v2", "enable log level 2 (verbose)",
        function()
            e2lib.setlog(2, true)
            return true
        end,
        category)
        e2option.flag("v3", "enable log level 3 (show user debug information)",
        function()
            e2lib.setlog(3, true)
            return true
        end,
        category)
        e2option.flag("v4", "enable log level 4 (show tool debug information)",
        function()
            e2lib.setlog(4, true)
            return true
        end,
        category)
        e2option.flag("log-debug", "enable logging of debugging output",
        function()
            e2lib.globals.log_debug = true
            return true
        end,
        category)
        e2option.flag("Wall", "enable all warnings")
        e2option.flag("Wdefault", "warn when default values are applied")
        e2option.flag("Wdeprecated", "warn if deprecated options are used")
        e2option.flag("Wnoother",
        "disable all warnings not mentioned above (enabled by default)")
        e2option.flag("Wpolicy", "warn when hurting policies")
        e2option.flag("Whint", "enable hints to the user")
        category = "General Options"
        e2option.flag("help", "show usage information",
        function()
            e2option.usage()
        end,
        category)
        e2option.flag("version", "show version number",
        function()
            print(buildconfig.VERSIONSTRING)
            plugin.print_descriptions()
            e2lib.finish(0)
        end,
        category)
        e2option.flag("licence", "show licence information",
        function()
            print(e2lib.globals._version)
            print()
            print(e2lib.globals._licence)
            e2lib.finish(0)
        end,
        category)
    end

    local function userdefaultoptions()
        local home = e2lib.globals.homedir
        if not home then return end
        local file = home .. "/.e2/e2rc"
        if not e2util.exists(file) then
            return
        end
        local e2rc = {}
        local rc, e = e2lib.dofile_protected(file,
        { e2rc = function(t) e2rc = t end })
        if not rc then
            e2lib.abort(e)
        end
        for _,p in pairs(e2rc) do
            local n=p[1]
            local v=p[2]
            if options[n] then
                if options[n].type == "flag" and v then
                    e2lib.abort("argument given for flag: " .. n)
                elseif options[n].type == "option" and not v then
                    e2lib.abort("argument missing for option: " .. n)
                end
                local proc = options[n].proc
                proc(v)
            else
                e2lib.abort("unknown option in user defaults: " .. n)
            end
        end
    end

    defaultoptions()
    userdefaultoptions()
    local vals = {}
    local opts={ arguments=vals }
    local i = 1
    while i <= #args do		-- we may modify args
        local v = args[i]
        local s, e, opt, val = string.find(v, "^%-%-?([^= ]+)=(.*)$")
        if s then
            opt = aliases[opt] or opt
            if options[opt] then
                local proc = options[opt].proc
                if proc then val = proc(val) end
                opts[opt] = val
            else e2option.usage(1)
            end
        else
            s, e, opt = string.find(v, "^%-%-?(.*)$")
            if s then
                opt = aliases[opt] or opt
                if options[opt] then
                    local proc = options[opt].proc
                    if options[opt].type == "option" then
                        if i == #args then
                            e2lib.abort("argument missing for option: " .. opt)
                        end
                        if proc then
                            opts[opt] = proc(args[i + 1])
                        else
                            opts[opt] = args[i + 1]
                        end
                        i = i + 1
                    else
                        if proc then
                            opts[opt] = proc()
                        else
                            opts[opt] = options[opt].default
                        end
                    end
                else
                    local set = {}
                    for i = 1, string.len(opt) do
                        table.insert(set, string.sub(opt, i, i))
                    end

                    for k, v in pairs(set) do
                        if not options[v] then
                            e2lib.abort(string.format("invalid option: %s\n"..
                            "Try the --help option for usage information.", opt))
                        else
                            table.insert(args, "-" .. v)
                        end
                    end
                end
            else
                table.insert(vals, v)
            end
        end
        i = i + 1
    end
    if opts["Wdefault"] or opts["Wall"] then
        e2lib.globals.warn_category.WDEFAULT = true
    end
    if opts["Wdeprecated"] or opts["Wall"] then
        e2lib.globals.warn_category.WDEPRECATED = true
    end
    if opts["Wnoother"] then
        e2lib.globals.warn_category.WOTHER = false
    end
    if opts["Wpolicy"] or opts["Wall"] then
        e2lib.globals.warn_category.WPOLICY = true
    end
    if opts["Whint"] or opts["Wall"] then
        e2lib.globals.warn_category.WHINT = true
    end
    e2option.opts = opts
    return opts, vals
end

--- display builtin option documentation and exit
-- @param rc number: return code, passed to e2lib.finish()
-- @return nil
function e2option.usage(rc)
    print(e2lib.globals._version)
    print([[
Copyright (C) 2007-2009 by Gordon Hecker and Oskar Schirmer, emlix GmbH
Copyright (C) 2007-2008 by Felix Winkelmann, emlix GmbH

This program comes with ABSOLUTELY NO WARRANTY; This is free software,
and you are welcome to redistribute it under certain conditions.
Type e2 --licence for more information.
]])
    print(e2option.documentation)
    local category = nil
    for _, n in ipairs(optionlist) do
        local opt = options[n]
        if category ~= opt.category then
            print()
            category = opt.category
            if category then
                print(category .. ":")
            end
        end
        io.write("  -")
        if #n > 1 then io.write("-") end
        io.write(n)
        if opt.type == "option" then
            io.write("=", opt.argumentname)
        elseif #n < 4 then
            io.write("\t")
        end
        print("\t" .. opt.documentation)
    end
    print()
    for k, v in pairs(commands) do
        io.write(" ", k, command.documentation)
        print()
    end
    e2lib.finish(rc)
end

return e2option

-- vim:sw=4:sts=4:et:
