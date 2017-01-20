--- Result class. Implements the base result class and config loader.
-- @module local.result

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

local result = {}
package.loaded["result"] = result

local buildconfig = require("buildconfig")
local cache = require("cache")
local chroot = require("chroot")
local class = require("class")
local e2build = require("e2build")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local environment = require("environment")
local err = require("err")
local hash = require("hash")
local project = require("project")
local projenv = require("projenv")
local sl = require("sl")
local source = require("source")
local strict = require("strict")

--- Dictionary holding all result objects indexed by their name.
result.results = {}

--- Array holding all results objects in alphabetical order.
result.results_sorted = {}

--- Vector of result type detector functions.
local type_detection_fns = {}

--- Dictionary holding class objects indexed by type
local result_types = {}

--------------------------------------------------------------------------------
--- Result base class.
--@type basic_result
result.basic_result = class("basic_result")

--- Result base constructor. Assert error on invalid input.
-- @param rawres Result config dict containing at least "name" and "type"
-- attributes.
-- @return Nil on success, throws exception on failure.
function result.basic_result:initialize(rawres)
    assertIsTable(rawres)
    assertIsStringN(rawres.name)
    assertIsStringN(rawres.type)

    self._name = rawres.name
    self._type = rawres.type
end

--- Constructor that's called by load_result_configs() after all results
-- have been created. Put consistency checks between results in here.
-- return True on success, false on error.
-- return Error object on failure.
function result.basic_result:post_initialize()
    return true -- default is no action
end

--- Get name.
-- @return Name of result (Ex: group.result).
function result.basic_result:get_name()
    assertIsStringN(self._name)
    return self._name
end

--- Get type.
-- @return Type (string) of result config.
function result.basic_result:get_type()
    assertIsStringN(self._type)
    return self._type
end

--- Get name as directory path.
-- @return Path of result (ex: group/result).
function result.basic_result:get_name_as_path()
    assertIsStringN(self._name)
    local p = e2tool.src_res_name_to_path(self._name)
    assertIsStringN(p)
    return p
end

--- Project-wide build id for this result and all of its depdencies.
function result.basic_result:buildid()
    error(err.new("called buildid() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return a string list of depdenant results.
-- @return String list of dependency names.
function result.basic_result:depends_list()
    error(err.new("called depends_list() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return a string list of sources.
-- @return String list of source names.
function result.basic_result:sources_list()
    error(err.new("called sources_list() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return the complete and merged environment for this result.
-- Does NOT include the builtin environment from build_config.
-- @return Environment object
function result.basic_result:merged_env()
    error(err.new("called merged_env() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return the list of chroot groups for this result.
-- @return string list of required chroot groups.
function result.basic_result:chroot_list()
    error(err.new("called chroot_list() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return locked build_config table
-- @return build_config table (locked) or false on error
-- @return error object.
function result.basic_result:build_config()
    error(err.new("called build_config() of result base class, type %s name %s",
        self._type, self._name))
end

--- Get/set build_mode table for result. Needs to be set before certain
-- operations, for example anything calculating the buildid.
-- @param bm Optional build mode table to set a new one.
-- @see policy.build_mode
function result.basic_result:build_mode(bm)
    error(err.new("called build_mode() of result base class, type %s name %s",
        self._type, self._name))
end

--- Return the complete and merged environment for this result.
-- @return Environment object
function result.basic_result:merged_env()
    error(err.new("called merged_env() of result base class, type %s name %s",
        self._type, self._name))
end

--- Get the build process to be used for this class
function result.basic_result:build_process()
    error(err.new("called build_process() of result base class, type %s name %s",
        self._type, self._name))
end

--- Get/set the settings class. Settings hold per-result information
-- for the build process. Each result that's passed to a build process needs
-- a valid settings_class
-- @param bs Optional settings_class
function result.basic_result:build_settings(bs)
    error(err.new("called build_settings() of result base class, type %s name %s",
        self._type, self._name))
end

--- Textual free-form representation of the result.
-- Returns a table in the form
-- { { "sources", "a", "b", "c" }, { "depends", "d", "e" }, ... }.
-- Informative only, output/order may change at any time!
-- @param flagt Optional table with keys enabling additional attributes. At the
-- moment 'chroot' and 'env' are known.
-- @return A vector filled with attribute tables.
function result.basic_result:attribute_table(flagt)
    assert(flagt == nil or type(flagt) == "table")
    error(err.new("called attribute_table() of result base class, type %s name %s",
        self._type, self._name))
end

--------------------------------------------------------------------------------
--- Result class (standard).
-- @type result_class
result.result_class = class("result_class", result.basic_result)

---
function result.result_class:initialize(rawres)
    assertIsTable(rawres)
    assertIs(rawres.type, "result")

    result.basic_result.initialize(self, rawres)

    self._depends_list = sl.sl:new()
    self._buildid = false
    self._sources_list = sl.sl:new()
    self._chroot_list = sl.sl:new()
    self._env = environment.new()
    self._build_mode = false
    self._build_settings = false

    local e = err.new("in result %s:", self._name)
    local rc, re, info

    rc, re = e2lib.vrfy_dict_exp_keys(rawres, "e2result config", {
        "chroot",
        "depends",
        "env",
        "name",
        "sources",
        "type",
    })
    if not rc then
        error(e:cat(re))
    end

    if rawres.sources == nil then
        rawres.sources = {}
    elseif type(rawres.sources) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", self._name)
        e2lib.warnf("WDEPRECATED", " sources attribute is string. "..
            "Converting to list")
        rawres.sources = { rawres.sources }
    end

    rc, re = e2lib.vrfy_listofstrings(rawres.sources, "sources", true, false)
    if not rc then
        e:append("source attribute:")
        e:cat(re)
    else
        for _,sourcename in ipairs(rawres.sources) do
            if not source.sources[sourcename] then
                e:append("source does not exist: %s", sourcename)
            end

            self._sources_list:insert(sourcename)
        end
    end


    if rawres.depends == nil then
        rawres.depends = {}
    elseif type(rawres.depends) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", self._name)
        e2lib.warnf("WDEPRECATED", " depends attribute is string. "..
        "Converting to list")
        rawres.depends = { rawres.depends }
    end
    rc, re = e2lib.vrfy_listofstrings(rawres.depends, "depends", true, false)
    if not rc then
        e:append("dependency attribute:")
        e:cat(re)
    else
        for _,depname in ipairs(rawres.depends) do
            -- Delay depends checking until all results are loaded.
            self._depends_list:insert(depname)
        end
    end

    if rawres.chroot == nil then
        rawres.chroot = {}
    elseif type(rawres.chroot) == "string" then
        e2lib.warnf("WDEPRECATED", "in result %s:", self._name)
        e2lib.warnf("WDEPRECATED", " chroot attribute is string. "..
            "Converting to list")
        rawres.chroot = { rawres.chroot }
    end
    rc, re = e2lib.vrfy_listofstrings(rawres.chroot, "chroot", true, false)
    if not rc then
        e:append("chroot attribute:")
        e:cat(re)
    else
        -- apply default chroot groups
        for _,g in ipairs(chroot.groups_default) do
            table.insert(rawres.chroot, g)
        end
        -- The list may have duplicates now. Unify.
        rc, re = e2lib.vrfy_listofstrings(rawres.chroot, "chroot", false, true)
        if not rc then
            e:append("chroot attribute:")
            e:cat(re)
        end
        for _,g in ipairs(rawres.chroot) do
            if not chroot.groups_byname[g] then
                e:append("chroot group does not exist: %s", g)
            end

            self:chroot_list():insert(g)
        end
    end


    info = e2tool.info()

    if rawres.env and type(rawres.env) ~= "table" then
        e:append("result has invalid `env' attribute")
    else
        if not rawres.env then
            rawres.env = {}
        end

        for k,v in pairs(rawres.env) do
            if type(k) ~= "string" then
                e:append("in `env' dictionary: "..
                "key is not a string: %s", tostring(k))
            elseif type(v) ~= "string" then
                e:append("in `env' dictionary: "..
                "value is not a string: %s", tostring(v))
            else
                self._env:set(k, v)
            end
        end
    end

    local build_script =
        e2tool.resultbuildscript(self:get_name_as_path(), e2tool.root())
    if not e2lib.isfile(build_script) then
        e:append("build-script does not exist: %s", build_script)
    end

    if e:getcount() > 1 then
        error(e)
    end

end

---
function result.result_class:post_initialize()
    local e

    for depname in self:depends_list():iter() do
        if not result.results[depname] then
            e = e or err.new("in result %s:", self:get_name())
            e:append("dependency does not exist: %s", depname)
        end
    end

    if e then
        return false, e
    end

    return true
end

---
function result.result_class:depends_list()
    return self._depends_list:copy()
end

---
function result.result_class:sources_list()
    return self._sources_list
end

---
function result.result_class:chroot_list()
    return self._chroot_list
end

---
function result.result_class:build_config()
    local rc, re, e, buildid, bc, tmpdir, builddir, info

    info = e2tool.info()
    assertIsTable(info)
    e = err.new("preparing build config for %s failed", self:get_name())

    buildid, re = self:buildid()
    if not buildid then
        return false, e:cat(re)
    end

    bc = {}
    tmpdir = string.format("%s/e2factory-%s.%s.%s-build/%s",
        e2lib.globals.tmpdir, buildconfig.MAJOR, buildconfig.MINOR,
        buildconfig.PATCHLEVEL, e2lib.globals.osenv["USER"])
    builddir = "tmp/e2"

    bc.base = e2lib.join(tmpdir, project.name(), self:get_name())
    bc.c = e2lib.join(bc.base, "chroot")
    bc.chroot_marker = e2lib.join(bc.base, "e2factory-chroot")
    bc.chroot_lock = e2lib.join(bc.base, "e2factory-chroot-lock")
    bc.T = e2lib.join(bc.c, builddir)
    bc.Tc = e2lib.join("/", builddir)
    bc.r = self:get_name()
    bc.chroot_call_prefix = project.chroot_call_prefix()
    bc.buildlog = string.format("%s/log/build.%s.log", e2tool.root(), self:get_name())
    bc.scriptdir = "script"
    bc.build_driver_file = "build-driver"
    bc.buildrc_file = "buildrc"
    bc.buildrc_noinit_file = "buildrc-noinit"
    bc.profile = "/tmp/bashrc"

    bc.builtin_env = environment.new()
    bc.builtin_env:set("E2_TMPDIR", bc.Tc)
    bc.builtin_env:set("E2_RESULT", self:get_name())
    bc.builtin_env:set("E2_RELEASE_ID", project.release_id())
    bc.builtin_env:set("E2_PROJECT_NAME", project.name())
    bc.builtin_env:set("E2_BUILDID", buildid)
    bc.builtin_env:set("T", bc.Tc)
    bc.builtin_env:set("r", self:get_name())
    bc.builtin_env:set("R", self:get_name())

    return strict.readonly(bc)
end

---
function result.result_class:build_mode(bm)
    if bm then
        assertIsTable(bm)
        self._build_mode = bm
    else
        assertIsTable(self._build_mode)
    end

    return self._build_mode
end

---
function result.result_class:build_settings(bs)
    if bs then
        assertIsTable(bs)
        self._build_settings = bs
    else
        assertIsTable(self._build_settings)
    end

    return self._build_settings
end

---
function result.result_class:merged_env()
    local e = environment.new()

    -- Global env
    e:merge(projenv.get_global_env(), false)

    -- Sources env
    for sourcename in self._sources_list:iter() do
        local src = source.sources[sourcename]
        e:merge(src:get_env(), true)
    end

    -- Global result specific env
    e:merge(projenv.get_result_env(self._name), true)

    -- Result specific env
    e:merge(self._env, true)

    return e
end

--- Get the project-wide buildid for a result, calculating it if required.
-- @return BuildID or false on error.
-- @return Error object on failure.
function result.result_class:buildid()
    local e, rc, re, info, hc, id, build_mode
    build_mode = self:build_mode()

    if self._buildid then
        return build_mode.buildid(self._buildid)
    end

    e = err.new("error calculating BuildID for result: %s", self:get_name())
    info = e2tool.info()
    hc = hash.hash_start()

    -- basic_result
    hash.hash_append(hc, self:get_name())
    hash.hash_append(hc, self:get_type())

    -- sources
    for sourcename in self:sources_list():iter() do
        local src, sourceset

        src = source.sources[sourcename]
        sourceset = build_mode.source_set()
        assertIsStringN(sourceset)
        id, re = src:sourceid(sourceset)
        if not id then
            return false, re
        end

        hash.hash_append(hc, id)
    end

    -- chroot
    for groupname in self:chroot_list():iter() do
        id, re = chroot.groups_byname[groupname]:chrootgroupid(info)
        if not id then
            return false, e:cat(re)
        end
        hash.hash_append(hc, id)
    end

    -- environment
    hash.hash_append(hc, self:merged_env():envid())

    -- buildscript
    local file = e2tool.file_class:new(
        cache.server_names().dot,
        e2tool.resultbuildscript(self:get_name_as_path())
        )

    id, re = file:fileid()
    if not id then
        return false, re
    end
    hash.hash_append(hc, id)


    -- depends
    for depname in self:depends_list():iter() do
        id, re = result.results[depname]:buildid()
        if not id then
            return false, re
        end
        hash.hash_append(hc, id)
    end

    -- project
    id, re = project.projid(info)
    if not id then
        return false, e:cat(re)
    end
    hash.hash_append(hc, id)

    self._buildid = hash.hash_finish(hc)

    return build_mode.buildid(self._buildid)
end

---
function result.result_class:build_process()
    assertIsTable(self._build_mode)
    assertIsTable(self._build_settings)
    return e2build.build_process_class:new()
end

---
function result.result_class:attribute_table(flagt)
    assert(flagt == nil or type(flagt) == "table")

    local t = {}
    flagt = flagt or {}

    table.insert(t, { "sources", self:sources_list():unpack()})
    table.insert(t, { "depends", self:depends_list():unpack()})
    if flagt.chroot then
        table.insert(t, { "chroot", self:chroot_list():unpack()})
    end
    if flagt.env then
        local tenv = { "env" }
        for k, v in self:merged_env():iter() do
            table.insert(tenv, string.format("%s=%s", k, v))
        end
        table.insert(t, tenv)
    end

    return t
end

--------------------------------------------------------------------------------
-- Result loading and plugin hookup
--------------------------------------------------------------------------------
-- @section end

--- Gather result paths.
-- @param info Info table.
-- @param basedir Nil or directory from where to start scanning for more
--                results. Only for recursion.
-- @param results Nil or table of result paths. Only for recursion.
-- @return Table with result paths, or false on error.
-- @return Error object on failure.
local function gather_result_paths(info, basedir, results)
    local rc, re
    local currdir, resdir, resconfig, s

    results = results or {}
    currdir = e2tool.resultdir(basedir, e2tool.root())
    for entry, re in e2lib.directory(currdir) do
        if not entry then
            return false, re
        end

        if basedir then
            entry = e2lib.join(basedir, entry)
        end

        resdir = e2tool.resultdir(entry, e2tool.root())
        resconfig = e2tool.resultconfig(entry, e2tool.root())
        s = e2lib.stat(resdir)
        if s.type == "directory" then
            if e2lib.exists(resconfig) then
                table.insert(results, entry)
            else
                -- try subfolder
                rc, re = gather_result_paths(info, entry, results)
                if not rc then
                    return false, re
                end
            end
        end
    end

    return results
end

---
local function load_rawres(cfg)
    local e, rc, re
    local rawres, loadcnt, g, path, res, info

    e = err.new("error loading result configuration")

    rc, re = e2tool.verify_src_res_pathname_valid_chars(cfg)
    if not rc then
        e:append("invalid result file name: %s", cfg)
        e:cat(re)
        return false, e
    end

    info = e2tool.info()
    rawres = nil
    loadcnt = 0
    g = {
        e2result = function(data) rawres = data loadcnt = loadcnt + 1 end,
        env = projenv.safe_global_res_env_table(),
        string = e2lib.safe_string_table(),
    }

    path = e2tool.resultconfig(cfg, e2tool.root())
    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, e:cat(re)
    end

    if type(rawres) ~= "table" then
        return false, e:append("result %q is missing an e2result table", cfg)
    end

    if loadcnt > 1 then
        return false, e:append("duplicate result config in %q", cfg)
    end

    if not rawres.name then
        rawres.name = e2tool.src_res_path_to_name(cfg)
    end

    if rawres.name ~= e2tool.src_res_path_to_name(cfg) then
        return false, e:append(
            "result name %q must match result directory name %q",
            rawres.name, e2tool.src_res_path_to_name(cfg))
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(rawres.name)
    if not rc then
        e:append("invalid result name: %s", rawres.name)
        e:cat(re)
        return false, e
    end

    if result.results[rawres.name] then
        return false, e:append("duplicate result: %s", rawres.name)
    end

    if rawres.type and type(rawres.type) ~= "string" then
        return false, e:append("invalid result type: %s", tostring(rawres.type))
    end

    return rawres
end

---
local function load_one_config(cfg)
    assertIsStringN(cfg)
    local rc, re, e, rawres, res

    rawres, re = load_rawres(cfg)
    if not rawres then
        return false, re
    end

    assertIsString(rawres.type)
    assertIsString(rawres.name)

    res = result_types[rawres.type]
    rc, re = e2lib.trycall(res.new, res, rawres)
    if not rc then
        e = err.new("error in result %q", rawres.name)
        return false, e:cat(re)
    end

    res = re
    assertIsTable(res)
    result.results[res:get_name()] = res

    return true
end

--- Search, load and verify all result configs. On success, all results are
--available as objects in result.results[].
-- @param info Info table
-- @return True on success, false on error.
-- @return Error object on failure.
function result.load_result_configs(info)
    local rc, re, e, configs, res

    configs, re = gather_result_paths(info)
    if not configs then
        return false, re
    end

    for _,cfg in ipairs(configs) do
        local rawres, obj

        rawres, re = load_rawres(cfg)
        if not rawres then
            return false, re
        end

        obj, re = result.instantiate_object(rawres)
        if not obj then
            return false, re
        end

        assertIsTable(obj)
        result.results[obj:get_name()] = obj
    end

    for resultname,_ in pairs(result.results) do
        table.insert(result.results_sorted, resultname)
    end

    table.sort(result.results_sorted)

    for _,resultname in ipairs(result.results_sorted) do
        res = result.results[resultname]
        rc, re = res:post_initialize()
        if not rc then
            return false, re
        end
    end

    return true
end

--- Create an instance of the outermost result type of rawres.
-- Type detection is expected to have set up the 'type' field properly.
-- @param rawres Raw result table.
-- @return Any result object or false on error
-- @return Error object on failure.
function result.instantiate_object(rawres)
    assertIsTable(rawres)

    local e, rc, re, outertype, theclass, obj

    for _,type_detection in ipairs(type_detection_fns) do
        -- Do not shortcut type detection on success.
        -- Some functions may need to see the raw result even if it
        -- does not match their type.
        rc = type_detection(rawres)
        assert(rc == nil, "type_detection return value is ignored!")
    end

    if type(rawres.type) ~= "string" then
        return false, err.new("no type in result %q detected (plugin missing?)",
            rawres.name)
    end

    if not result_types[rawres.type] then
        return false, err.new(
            "unknown type %q in result %q found (plugin missing?)",
            rawres.type, rawres.name)
    end

    e2lib.logf(3, "instantiating %s of type %s", rawres.name, rawres.type)

    theclass = result_types[rawres.type]
    assertIsTable(theclass)
    rc, re = e2lib.trycall(theclass.new, theclass, rawres)
    if not rc then
        e = err.new("error in result %q", rawres.name)
        return false, e:cat(re)
    end

    obj = re
    assertIsTable(obj)
    return obj
end

--- Registers a function that detects the type of a raw result config table.
-- The registered function is passed a "rawres" table, and must set the "type"
-- field within that table if it recognizes its type.
-- @param func Function in the form function(rawres)...end
function result.register_type_detection(func)
    assertIsFunction(func)
    for _,fn in ipairs(type_detection_fns) do
        assert(fn ~= func, err.new("result type detection already registered"))
    end
    table.insert(type_detection_fns, 1, func)

    return true
end

--- Register a result class. A type can only be registered once.
-- @param typ Source type name.
-- @param result_class Class derived from basic_result.
-- @return True on success, false on error.
-- @return Error object on failure.
function result.register_result_class(typ, result_class)
    assertIsStringN(typ)
    assertIsTable(result_class)
    assert(result_types[typ] == nil,
        err.new("result %q already registered", typ))

    result_types[typ] = result_class

    return true
end

---
local function detect_result(rawres)
    if not rawres.type then
        rawres.type = "result"
    end
end

result.register_result_class("result", result.result_class)
result.register_type_detection(detect_result)

return strict.lock(result)

-- vim:sw=4:sts=4:et:
