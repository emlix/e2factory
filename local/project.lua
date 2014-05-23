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
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local strict = require("strict")

local _prj = {}
local _config_loaders = {}

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
    local rc, re, e, info

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
    if not info.chroot_call_prefix[prj.chroot_arch] then
        return false, err.new("chroot_arch is set to an invalid value")
    end
    if prj.chroot_arch == "x86_64" and e2lib.host_system_arch ~= "x86_64" then
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
        env = info.env,
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

return strict.lock(project)

-- vim:sw=4:sts=4:et: