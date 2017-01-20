--- Source base class. Implements the base source class and config loader.
-- @module local.source

-- Copyright (C) 2007-2017 emlix GmbH, see file AUTHORS
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

local source = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local environment = require("environment")
local err = require("err")
local licence = require("licence")
local projenv = require("projenv")
local sl = require("sl")
local strict = require("strict")

--- Dictionary indexed by source type, derived source class.
local source_types = {}

--- Source base class.
-- @type basic_source
source.basic_source = class("basic_source")

--- Whether the class is of a Source Code Management type.
-- @return True or false
function source.basic_source.static:is_scm_source_class()
    assertIsTable(self)
    return false
end

--- Whether this class of sources was selected on the command line.
-- @param opts e2option table.
-- @return True or false
function source.basic_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)
    return false
end

--- Source base constructor. Assert error on invalid input.
-- @param rawsrc Source config dict containing at least "name" and "type"
-- attributes.
function source.basic_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and rawsrc.name ~= "")
    assert(type(rawsrc.type) == "string" and rawsrc.type ~= "")

    self._name = rawsrc.name
    self._type = rawsrc.type
    self._licences = false
    self._env = false
end

--- Get name.
-- @return Name of source (Ex: group.result).
function source.basic_source:get_name()
    assert(type(self._name) == "string")
    return self._name
end

--- Get name as directory path.
-- @return Path of source (ex: group/result).
function source.basic_source:get_name_as_path()
    assert(type(self._name) == "string")
    local p = e2tool.src_res_name_to_path(self._name)
    assert(type(p) == "string")
    return p
end

--- Get type of source.
-- @return Type of source (ex: "files", "git", ...)
function source.basic_source:get_type()
    return self._type
end

--- Set licence array.
-- @param licences String list of licence names (sl).
function source.basic_source:set_licences(licences)
    assert(type(licences) == "table" and licences.class.name == "sl")
    self._licences = licences:copy()
end

--- Get licence array. Must be set before calling get_licences(). Note that
-- this returns all licences used in a source. Some sources may have more
-- detailed licensing information which can be accessed by other means.
-- @return String list of licence names (sl).
function source.basic_source:get_licences()
    assert(type(self._licences) == "table")
    return self._licences:copy()
end

--- Set env object.
-- @param env Env object.
function source.basic_source:set_env(env)
    assert(type(env) == "table")
    self._env = env
end

--- Get env object. Must be set before calling get_env().
-- @return Env object.
function source.basic_source:get_env()
    assert(type(self._env) == "table")
    return self._env
end

--- Abstract sourceid method. Every child class must overwrite this
-- method with an implementation. Calling this method throws an error.
-- @param sourceset Source set (ex: "tag", "branch", ...)
-- @return Sourceid string (usually a hash value) or false on error.
-- @return Error object on failure.
function source.basic_source:sourceid(sourceset)
    error(err.new("called sourceid() of source base class, type %s name %s",
        self._type, self._name))
end

--- Abstract display method. Every child class must overwrite this
-- method with an implementation. Calling this method throws an error.
-- @return Array of strings containing free form information about source.
function source.basic_source:display()
    error(err.new("called display() of source base class, type %s name %s",
        self._type, self._name))
end

--- Check whether the working copy is available. Sources that don't have a
-- working copy should return false and an error object. Abstract method.
-- @return True or false.
-- @return Error object on false
function source.basic_source:working_copy_available()
    error(err.new("called working_copy_availabley() of source base class, type %s name %s",
        self._type, self._name))
end

--- @section end

--- Dictionary holding all source objects indexed by their name.
source.sources = {}

--- Gather source paths.
-- @param info Info table.
-- @param basedir Nil or directory from where to start scanning for more
--                sources. Only for recursion.
-- @param sources Nil or table of source paths. Only for recursion.
-- @return Table with source paths, or false on error.
-- @return Error object on failure.
local function gather_source_paths(info, basedir, sources)
    local rc, re
    local currdir, sdir, sconfig, s
    sources = sources or {}

    currdir = e2tool.sourcedir(basedir, e2tool.root())
    for entry, re in e2lib.directory(currdir) do
        if not entry then
            return false, re
        end

        if basedir then
            entry = e2lib.join(basedir, entry)
        end

        sdir = e2tool.sourcedir(entry, e2tool.root())
        sconfig = e2tool.sourceconfig(entry, e2tool.root())
        s = e2lib.stat(sdir)
        if s.type == "directory" then
            if e2lib.exists(sconfig) then
                table.insert(sources, entry)
            else
                -- try sub directory
                rc, re = gather_source_paths(info, entry, sources)
                if not rc then
                    return false, re
                end
            end
        end
    end

    return sources
end

--- Search, load and verify all source configs. On success, all sources
--available as objects in source.sources[] etc.
-- @param info Info table
-- @return True on success, false on error.
-- @return Error object on failure.
function source.load_source_configs(info)
    local rc, re, e
    local g, rawsrc, loadcnt, configs, path, src

    e = err.new("error loading source configuration")

    configs, re = gather_source_paths(info)
    if not configs then
        return false, e:cat(re)
    end

    for _,cfg in ipairs(configs) do
        rc, re = e2tool.verify_src_res_pathname_valid_chars(cfg)
        if not rc then
            e:append("invalid source file name: %s", cfg)
            e:cat(re)
            return false, e
        end

        rawsrc = nil
        loadcnt = 0
        g = {
            e2source = function(data) rawsrc = data loadcnt = loadcnt + 1 end,
            env = projenv.safe_global_res_env_table(),
            string = e2lib.safe_string_table(),
        }

        path = e2tool.sourceconfig(cfg, e2tool.root())
        rc, re = e2lib.dofile2(path, g)
        if not rc then
            return false, e:cat(re)
        end

        if type(rawsrc) ~= "table" then
            return false, e:append("source %q is missing an e2source table", cfg)
        end

        if loadcnt > 1 then
            return false, e:append("duplicate source config in %q", cfg)
        end

        if not rawsrc.name then
            rawsrc.name = e2tool.src_res_path_to_name(cfg)
        end

        if rawsrc.name ~= e2tool.src_res_path_to_name(cfg) then
            return false, e:append(
                "source name %q must match source directory name %q",
                rawsrc.name, e2tool.src_res_path_to_name(cfg))
        end

        rc, re = e2tool.verify_src_res_name_valid_chars(rawsrc.name)
        if not rc then
            e:append("invalid source name: %s", rawsrc.name)
            e:cat(re)
            return false, e
        end

        if source.sources[rawsrc.name] then
            return false, e:append("duplicate source: %s", rawsrc.name)
        end

        -- source with no type field is treated as file source
        if not rawsrc.type then
            rawsrc.type = "files"
        end

        if not source_types[rawsrc.type] then
            return false,
                e:append("don't know how to handle %q source", rawsrc.type)
        end

        src = source_types[rawsrc.type]

        -- src:new(rawsrc)
        rc, re = e2lib.trycall(src.new, src, rawsrc)
        if not rc then
            e = err.new("error in source %q", rawsrc.name)
            return false, e:cat(re)
        end

        src = re
        assert(type(src) == "table")
        source.sources[src:get_name()] = src
    end

    return true
end

--- Register a source class. A type can only be registered once.
-- @param typ Source type name.
-- @param source_class Class derived from basic_source.
-- @return True on success, false on error.
-- @return Error object on failure.
function source.register_source_class(typ, source_class)
    assert(type(typ) == "string" and typ ~= "")
    assert(type(source_class) == "table")

    if source_types[typ] then
        return false, err.new("source %q already registered", typ)
    end

    source_types[typ] = source_class

    return true
end

--- Iterate over registered source classes.
-- @return Iterator function that returns a sorted typ, source class pair.
function source.iterate_source_classes()
    local i, t

    t = {}
    for typ,_ in pairs(source_types) do
        table.insert(t, typ)
    end
    table.sort(t)

    i = 0

    return function ()
        i = i + 1

        if t[i] then
            return t[i], source_types[t[i]]
        end

        return nil
    end
end

--- Validate licences attribute in rawsrc and set licences in src if successful.
-- @param rawsrc e2source config table
-- @param src Object of class basic_source.
-- @return True on success, false on error.
-- @return Error object on failure.
function source.generic_source_validate_licences(rawsrc, src)
    assert(type(rawsrc) == "table" and rawsrc.name and rawsrc.type)
    assert(type(src) == "table")

    local rc, re, licences

    licences = sl.sl:new()

    --[[if not rawsrc.licences and rawsrc.licence then
        e2lib.warnf("WDEPRECATED", "in source %s:", src.name)
        e2lib.warnf("WDEPRECATED",
        " licence attribute is deprecated. Replace by licences.")
        src.licences = src.licence
    end]]

    if rawsrc.licences == nil then
        e2lib.warnf("WDEFAULT", "in source %s:", rawsrc.name)
        e2lib.warnf("WDEFAULT",
            " licences attribute missing. Defaulting to empty list.")
        rawsrc.licences = {}
    elseif type(rawsrc.licences) == "string" then
        e2lib.warnf("WDEPRECATED", "in source %s:", rawsrc.name)
        e2lib.warnf("WDEPRECATED",
            " licences attribute is not in table format. Converting.")
        rawsrc.licences = { rawsrc.licences }
    end

    if type(rawsrc.licences) ~= "table" then
        return false, err.new("licences attribute must be a table")
    end

    rc, re = e2lib.vrfy_listofstrings(rawsrc.licences, "licences attribute",
        true, false)
    if not rc then
        return false, re
    end

    for _,licencename in ipairs(rawsrc.licences) do
        if not licence.licences[licencename] then
            return false, err.new("unknown licence: %s", licencename)
        end
        licences:insert(licencename)
    end

    src:set_licences(licences)

    return true
end

--- Helper to validate and set env in src.
-- @param rawsrc e2source config table.
-- @param src Source object.
-- @return True on success, false on error.
-- @return Error object on failure.
function source.generic_source_validate_env(rawsrc, src)
    assert(type(rawsrc) == "table" and rawsrc.name and rawsrc.type)
    assert(type(src) == "table")

    local newenv = environment.new()

    if rawsrc.env ~= nil and type(rawsrc.env) ~= "table" then
        return false, err.new("source has invalid `env' attribute")
    end

    if not rawsrc.env then
        rawsrc.env = {}
    end

    for k, v in pairs(rawsrc.env) do
        if type(k) ~= "string" then
            return false, err.new(
                "in `env' dictionary: key is not a string: %s", tostring(k))
        elseif type(v) ~= "string" then
            return false, err.new(
                "in `env' dictionary: value is not a string: %s", tostring(v))
        else
            newenv:set(k, v)
        end
    end

    src:set_env(newenv)

    return true
end

--- Helper to validate server.
-- @param rawsrc e2source config table
-- @param ismandatory Whether rawsrc containing a server attr is mandatory.
-- @return True on success, false on error.
-- @return Error object on failure.
function source.generic_source_validate_server(rawsrc, ismandatory)
    assert(type(rawsrc) == "table" and rawsrc.name and rawsrc.type)
    assert(type(ismandatory) == "boolean")

    local info = e2tool.info()

    if ismandatory and rawsrc.server == nil then
        return false, err.new("source has no `server' attribute")
    end

    if rawsrc.server ~= nil and type(rawsrc.server) ~= "string" then
        return false, err.new("'server' attribute must be a string")
    end

    if rawsrc.server and (not cache.valid_server(info.cache, rawsrc.server)) then
        return false, err.new("invalid server: %s", rawsrc.server)
    end

    return true
end

--- Helper to validate working attribute.
-- @param rawsrc e2source config table
-- @return True on success, false on error.
-- @return Error object on failure.
function source.generic_source_validate_working(rawsrc)
    assert(type(rawsrc) == "table" and rawsrc.name and rawsrc.type)

    if rawsrc.working ~= nil and not type(rawsrc.working) == "string" then
        return false, err.new("'working' attribute must be a string")
    end

    if rawsrc.working == nil then
        rawsrc.working = e2lib.join("in", rawsrc.name)

        e2lib.warnf("WDEFAULT", "in source %s:", rawsrc.name)
        e2lib.warnf("WDEFAULT", " `working' attribute defaults to '%s'.",
            rawsrc.working)
    end

    return true
end

return strict.lock(source)

-- vim:sw=4:sts=4:et:
