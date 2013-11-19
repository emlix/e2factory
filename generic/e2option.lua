--- Option Parser
-- @module generic.e2option

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

-- Parsing of command-line options

local e2option = {}
local e2lib = require("e2lib")
local plugin = require("plugin")
local err = require("err")
local strict = require("strict")
local tools = require("tools")
local buildconfig = require("buildconfig")

local options = {}
local aliases = {}
local optionlist = {} -- ordered list of option names

e2option.opts = {}

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
    e2option.flag("help", "show manpage",
    function()
        local rc, re = e2option.showtoolmanpage()
        if not rc then
            e2lib.abort(re)
        end

        e2lib.finish(0)
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

local function userdefaultoptions(opts)
    local home = e2lib.globals.homedir
    if not home then
        return true
    end

    local file = home .. "/.e2/e2rc"
    if not e2lib.exists(file) then
        return true
    end

    local e2rc = {}
    local rc, e = e2lib.dofile2(file, { e2rc = function(t) e2rc = t end }, false)
    if not rc then
        return false, e
    end

    for _,tbl in pairs(e2rc) do
        if type(tbl) ~= "table" then
            return false, err.new("could not parse user defaults.\n"..
                "'%s' is not in the expected format.", file)
        end

        local opt=tbl[1]
        local val=tbl[2]

        if type(opt) ~= "string" or string.len(opt) == 0 then
            return false, err.new("could not parse user defaults.\n"..
                "'%s' has a malformed option", file)
        end

        opt = aliases[opt] or opt

        if not options[opt] then
            return false, err.new("unknown option in user defaults: %s", opt)
        end

        if options[opt].type == "flag" and val then
            return false, err.new(
                "user default option '%s' does not take an argument ", opt)
        elseif options[opt].type == "option" and not val then
            return false,
                err.new("argument missing for user default option: %s", opt)
        end

        if options[opt].proc then
            if  options[opt].type == "flag" then
                opts[opt] = options[opt].proc()
            else
                opts[opt] = options[opt].proc(val)
            end
        elseif options[opt].default then
            opts[opt] = options[opt].default
        else
            return false, err.new("user default option has no effect")
        end
    end

    return true
end

--- fill in defaults, parse user defauls and parse normal options
-- @param args table: command line arguments (usually the arg global variable)
-- @return table: option_table or false on error.
-- @return table of unparsed arguments (everything not identified as an option)
-- or an error object on failure.
function e2option.parse(args)
    defaultoptions()
    local opts = {}
    local vals = {}
    local rc, re

    rc, re = userdefaultoptions(opts)
    if not rc then
        return false, re
    end

    local i = 1
    while i <= #args do		-- we may modify args
        local v = args[i]
        local s, e, opt, val = string.find(v, "^%-%-?([^= ]+)=(.*)$")
        if s then
            opt = aliases[opt] or opt
            if options[opt] then
                if options[opt].type == "flag" then
                    return false, err.new(
                        "option '%s' does not take an argument\n"..
                        "Try the --help option for usage information.", opt)
                end

                local proc = options[opt].proc
                if proc then
                    val = proc(val)
                end

                opts[opt] = val
            else
                return false, err.new("unknown option: %s\n"..
                "Try the --help option for usage information.", opt)
            end
        else
            s, e, opt = string.find(v, "^%-%-?(.*)$")
            if s then
                opt = aliases[opt] or opt
                if options[opt] then
                    local proc = options[opt].proc
                    if options[opt].type == "option" then
                        if i == #args then
                            return false,
                                err.new("argument missing for option: %s", opt)
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
                            return false, err.new("unknown option: %s\n"..
                                "Try the --help option for usage information.",
                                opt)
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

--- Construct tool name from argument vector.
-- @return Tool name (string)
local function toolname()
   local tool = e2lib.basename(arg[0])
   local toolnm

   if tool == 'e2' and
       arg[1] and string.sub(arg[1], 1, 1) ~= '-' then
       toolnm = string.format('%s-%s', tool, arg[1])
   else
       toolnm = tool
   end

   return toolnm
end

--- Display message how to get help and exit.
-- If the exit code is 0, stdout will be used for the message.
-- Otherwise stderr is used.
-- @param rc program exit code (number).
-- @return This function does not return.
function e2option.usage(rc)
    local out
    if rc == 0 then
        out = io.stdout
    else
        out = io.stderr
    end

    local m = string.format("usage: %s --help for more information\n",
        toolname())
    out:write(m)
    e2lib.finish(rc)
end

--- Show the manpage of the current tool and exit the process.
-- @return This function does not return.
function e2option.showtoolmanpage()
    local tool = toolname()
    local mpage = e2lib.join('man', 'man1', string.format('%s.1', tool))
    local prefix

    if e2lib.islocaltool(tool) then
        local dir = e2lib.locate_project_root()
        if dir then
            prefix = e2lib.join(dir, '.e2', 'doc')
        else
            e2lib.warn("WOTHER",
                "Could not locate project root, showing global help")
            prefix = e2lib.join(buildconfig.PREFIX, 'share')
        end
    elseif e2lib.isglobaltool(tool) then
        prefix = e2lib.join(buildconfig.PREFIX, 'share')
    else
        local file = e2lib.join(buildconfig.BINDIR, tool)
        if e2lib.isfile(file) then
            prefix = e2lib.join(buildconfig.PREFIX, 'share')
        else
            return false, err.new('tool "%s" does not exist', tool)
        end
    end

    mpage = e2lib.join(prefix, mpage)
    if not e2lib.isfile(mpage) then
        return false, err.new('manual page for "%s" does not exist (%s)',
            tool, mpage)
    end

    if not tools.isinitialized() then
        local rc, re = tools.init()
        if not rc then
            return false, re
        end
    end

    local cmd = {}
    for _,s in ipairs({"man"}) do
        local viewer, viewerflags

        viewer = tools.get_tool(s)
        viewerflags = tools.get_tool_flags(s)
        if viewer then
            table.insert(cmd, e2lib.shquote(viewer))
            if viewerflags then
                viewerflags = table.concat(viewerflags, " ")
            end
            if viewerflags ~= "" then
                table.insert(cmd, viewerflags)
            end

            break
        end
    end

    if #cmd < 1 then
        return false, err.new("Could not find manual viewer to display help")
    end

    table.insert(cmd, e2lib.shquote(mpage))

    os.execute(table.concat(cmd, ' '))

    return true
end

return strict.lock(e2option)

-- vim:sw=4:sts=4:et:
