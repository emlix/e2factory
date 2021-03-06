--- Option Parser
-- @module generic.e2option

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

-- Parsing of command-line options

local e2option = {}
local buildconfig = require("buildconfig")
local console = require("console")
local e2lib = require("e2lib")
local plugin = require("plugin")
local err = require("err")
local strict = require("strict")
local tools = require("tools")
local cache = require("cache")

local options = {}
local aliases = {}

--- e2option.parse() result is stored in this table for later reference.
-- @table opts
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
    options[name] = {
        type = "flag",
        documentation = doc or "",
        name = name,
        proc = func,
        default = true,
        category = category
    }
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
    options[name] = {
        type = "option",
        documentation = doc or "", name = name,
        proc = func,
        default = default,
        argumentname=argname or "ARGUMENT"
    }
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

--- Sets up default options for all commands.
local function defaultoptions()
    local category = "Verbosity Control Options"
    e2option.option("e2-config", "specify configuration file", nil,
    function(arg)
        e2lib.globals.e2config = arg
    end,
    "FILE")

    local function disable_writeback(server)
        cache.set_writeback(nil, server, false)
    end

    e2option.option("disable-writeback", "disable writeback for server", nil,
        disable_writeback, "SERVER")

    local function enable_writeback(server)
        cache.set_writeback(nil, server, true)
    end
    e2option.option("enable-writeback", "enable writeback for server", nil,
        enable_writeback, "SERVER")

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

    e2option.flag("log-debug", "enable debugging of log levels and warnings",
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

        e2lib.finish(rc)
    end,
    category)

    e2option.flag("version", "show version number",
    function()
        console.infonl(buildconfig.VERSIONSTRING)
        plugin.print_descriptions()
        e2lib.finish(0)
    end,
    category)

    e2option.flag("licence", "show licence information",
    function()
        console.infonl(e2lib.globals._version)
        console.infonl()
        console.infonl(e2lib.globals._licence)
        e2lib.finish(0)
    end,
    category)
end

--- Load user default options if set in $HOME/.e2/e2rc
local function userdefaultoptions(opts)
    local home = e2lib.globals.osenv["HOME"]
    if not home then
        return true
    end

    local file = home .. "/.e2/e2rc"
    if not e2lib.exists(file) then
        return true
    end

    local e2rc = {}
    local rc, e = e2lib.dofile2(file, { e2rc = function(t) e2rc = t end })
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
        elseif val and options[opt].type == "option" then
            opts[opt] = val
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
                        local optarg

                        if i == #args then
                            if options[opt].default == nil then
                                return false,
                                    err.new("argument missing for option: %s",
                                        opt)
                            else
                                optarg = options[opt].default
                            end
                        else
                            optarg =  args[i + 1]
                        end

                        if proc then
                            opts[opt] = proc(optarg)
                        else
                            opts[opt] = optarg
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

    local t = {}
    for k,v in pairs(opts) do
        if type(k) == "string" then
            table.insert(t, string.format("[%s]=%q", k, tostring(v)))
        end
    end
    for k,v in ipairs(vals) do
        table.insert(t, string.format("[%d]=%q", k, v))
    end
    e2lib.logf(4, "e2option.parse(): %s", table.concat(t, ", "))

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
    local m = string.format("usage: %s --help for more information\n",
        toolname())

    if rc == 0 then
        console.info(m)
    else
        console.eout(m)
    end

    e2lib.finish(rc)
end

--- Show the manpage for the current tool
-- @return Return code of man viewer, or false on error.
-- @return Error object on failure.
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

    local cmd = tools.get_tool_flags_argv("man")
    if not cmd then
        return false, err.new("Could not find manual viewer to display help")
    end

    table.insert(cmd, mpage)

    local rc, re = e2lib.callcmd(cmd, {})
    if not rc then
        return false, re
    end

    return rc
end

return strict.lock(e2option)

-- vim:sw=4:sts=4:et:
