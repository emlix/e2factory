--- Project module. Handle e2project configuration.
-- @module local.project

-- Copyright (C) 2007-2014 emlix GmbH, see file AUTHORS
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

local project = {}
package.loaded["project"] = project

local buildconfig = require("buildconfig")
local cache = require("cache")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local hash = require("hash")
local projenv = require("projenv")
local result = require("result")
local strict = require("strict")

local _prj = {}
local _config_loaders = {}
local _projid_cache = false

--- Check and load e2project callback function signature.
-- @function load_project_config_cb
-- @param prj Unchecked e2project table. Remove all keys that are private
--            to your use.
-- @return True on success, false on error
-- @return Error object on failure.

--- Register a function that gets called when the project config is
-- loaded. Functions get called in order of registration.
-- @param func load_project_config_cb function.
-- @return True on success, false on error.
-- @return Error object on failure.
-- @see load_project_config_cb
function project.register_load_project_config(func)
    assert(type(func) == "function")
    table.insert(_config_loaders, func)

    return true
end

--- Main e2project config check and init callback.
-- @param prj e2project table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function load_prj_cfg(prj)
    local rc, re, e, info, system_arch

    info = e2tool.info()
    assert(info)

    rc, re = e2lib.vrfy_dict_exp_keys(prj, "e2project",
        { "name", "release_id", "deploy_results",
        "default_results", "chroot_arch" })
    if not rc then
        return false, re
    end

    if not prj.release_id then
        return false, err.new("key is not set: release_id")
    end
    if not prj.name then
        return false, err.new("key is not set: name")
    end
    if not prj.default_results then
        e2lib.warnf("WDEFAULT", "in project configuration:")
        e2lib.warnf("WDEFAULT",
            "default_results is not set. Defaulting to empty list.")
        prj.default_results = {}
    end
    rc, re = e2lib.vrfy_listofstrings(prj.deploy_results,
        "deploy_results", true, true)
    if not rc then
        e = err.new("deploy_results is not a valid list of strings")
        e:cat(re)
        return false, e
    end

    rc, re = e2lib.vrfy_listofstrings(prj.default_results,
        "default_results",  true, false)
    if not rc then
        e = err.new("default_results is not a valid list of strings")
        e:cat(re)
        return false, e
    end

    if not prj.chroot_arch then
        e2lib.warnf("WDEFAULT", "in project configuration:")
        e2lib.warnf("WDEFAULT", " chroot_arch defaults to x86_32")
        prj.chroot_arch = "x86_32"
    end

    if prj.chroot_arch ~= "x86_32" and prj.chroot_arch ~= "x86_64" then
        return false, err.new("chroot_arch is set to an unknown architecture")
    end

    -- get host system architecture
    system_arch, re = e2lib.uname_machine()
    if not system_arch then
        return false, re
    end
    if prj.chroot_arch == "x86_64" and system_arch ~= "x86_64" then
        return false,
            err.new("running on x86_32: switching to x86_64 mode is impossible.")
    end

    _prj = prj
    return true
end

--- Initialise the project module, load and check proj/config. Needs to be
-- called before using name() etc.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure.
function project.load_project_config(info)
    local rc, re, e
    local path, prj

    -- register the main e2project load_project_config function last
    rc, re = project.register_load_project_config(load_prj_cfg)
    if not rc then
        return false, re
    end

    path = e2lib.join(info.root, "proj/config")

    prj = nil
    local g = {
        e2project = function(data) prj = data end,
        env = projenv.safe_global_res_env_table(),
        string = e2lib.safe_string_table(),
    }

    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, re
    end

    e = err.new("in project configuration:")

    if type(prj) ~= "table" then
        return false, e:append("Invalid or empty e2project configuration")
    end

    for _,load_project_config_cb in ipairs(_config_loaders) do
        rc, re = load_project_config_cb(prj)
        if not rc then
            return false, e:cat(re)
        end
    end

    return true
end

--- Checks project information for consistancy once results are loaded.
-- @return True on success, false on error.
-- @return Error object on failure.
function project.verify_project_config()
    local rc, re, e
    e = err.new("error in project configuration")

    for r in project.default_results_iter() do
        if not result.results[r] then
            e:append("default_results: No such result: %s", r)
        end
    end
    for r in project.deploy_results_iter() do
        if not result.results[r] then
            e:append("deploy_results: No such result: %s", r)
        end
    end
    if e:getcount() > 1 then
        return false, e
    end

    rc, re = e2tool.dsort()
    if not rc then
        return false, e:cat(re)
    end
    return true
end

--- Get project name.
-- @return Name.
function project.name()
    assert(type(_prj.name) == "string")
    return _prj.name
end

--- Get project ReleaseID.
-- @return ReleaseID as a string.
function project.release_id()
    assert(type(_prj.release_id) == "string")
    return _prj.release_id
end

--- Get chroot architecture. For multi-arch systems.
-- @return Chroot architecture as a string.
function project.chroot_arch()
    assert(type(_prj.chroot_arch) == "string")
    return _prj.chroot_arch
end

function project.chroot_call_prefix()
    local info
    info = e2tool.info()
    assert(info)

    if project.chroot_arch() == "x86_32" then
	return e2lib.join(info.root, ".e2/bin/e2-linux32")
    end

    return ""
end

--- Iterator that returns the deploy results as string.
-- @return Iterator function.
function project.deploy_results_iter()
    assert(type(_prj.deploy_results) == "table")
    local i = 0

    return function ()
        i = i + 1
        return _prj.deploy_results[i]
    end
end

--- Return true if resultname is the list of deploy_results.
-- @param resultname Result name.
-- @return True if result name was found, false otherwise.
function project.deploy_results_lookup(resultname)
    assert(type(_prj.deploy_results) == "table")
    assert(type(resultname) == "string")

    for _,r in ipairs(_prj.deploy_results) do
        if resultname == r then
            return true
        end
    end
    return false
end

--- Iterator that returns the default results as string.
-- @return Iterator function.
function project.default_results_iter()
    assert(type(_prj.default_results) == "table")
    local i = 0

    return function ()
        i = i + 1
        return _prj.default_results[i]
    end
end

--- Calculate the Project ID. The Project ID consists of files in proj/init
-- as well as some keys from proj/config and buildconfig. Returns a cached
-- value after the first call.
-- @return Project ID or false on error.
-- @return Error object on failure
function project.projid(info)
    local re, hc, cs

    if _projid_cache then
        return _projid_cache
    end

    -- catch proj/init/*
    hc = hash.hash_start()

    for f, re in e2lib.directory(e2lib.join(info.root, "proj/init")) do
        if not f then
            return false, re
        end

        local location, file, fileid
        if not e2lib.is_backup_file(f) then
            location = e2lib.join("proj/init", f)
            file = {
                server = cache.server_names().dot,
                location = location,
            }

            fileid, re = e2tool.fileid(info, file)
            if not fileid then
                return false, re
            end

            hash.hash_append(hc, location)   -- the filename
            hash.hash_append(hc, fileid)     -- the file content cs
        end
    end
    hash.hash_append(hc, project.release_id())
    hash.hash_append(hc, project.name())
    hash.hash_append(hc, project.chroot_arch())
    hash.hash_append(hc, buildconfig.VERSION)

    _projid_cache = hash.hash_finish(hc)

    return _projid_cache
end

return strict.lock(project)

-- vim:sw=4:sts=4:et:
