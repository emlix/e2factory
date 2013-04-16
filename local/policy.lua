--- Policy
-- @module local.policy

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

local policy = {}
local e2lib = require("e2lib")
local err = require("err")
local e2option = require("e2option")
local strict = require("strict")
local hash = require("hash")

--- source_set_* get the source set identifier
-- @class function
-- @name policy.source_set_*
-- @param none
-- @return string: the source set identifier
local function source_set_lazytag()
    return "lazytag"
end

local function source_set_tag()
    return "tag"
end

local function source_set_branch()
    return "branch"
end

local function source_set_working_copy()
    return "working-copy"
end

--- Get release server and location.
-- @param location Project location (e.g. customer/project) (string).
-- @param release_id Release Id (string).
-- @return Server name (string).
-- @return Location path to store results in (string).
local function storage_release(location, release_id)
    return "results", string.format("%s/release/%s", location, release_id)
end

--- Get results server and location.
-- @param location Project location (e.g. customer/project) (string).
-- @param release_id Release Id (string).
-- @return Server name (string).
-- @return Location path to store results in (string).
local function storage_default(location, release_id)
    return "results", string.format("%s/shared", location)
end

--- Get local server and location.
-- @param location Project location (e.g. customer/project) (string).
-- @param release_id Release Id (string).
-- @return Server name (string).
-- @return Location path to store results in (string).
local function storage_local(location, release_id)
    return "." , string.format("out")
end

--- Get deploy server and location.
-- @param location Project location (e.g. customer/project) (string).
-- @param release_id Release Id (string).
-- @return Server name (string).
-- @return Location path to store results in (string).
local function deploy_storage_default(location, release_id)
    return "releases", string.format("%s/archive/%s", location, release_id)
end

--- dep_set_*
-- @class function
-- @name policy.dep_set_*
-- @param buildid the buildid
-- @return the buildid
local function dep_set_buildid(buildid)
    return buildid
end

local function dep_set_last(buildid)
    return "last"
end

--- buildid_* get the buildid for a build
-- @class function
-- @name policy.buildid_*
-- @param buildid the buildid
-- @return the buildid
local function buildid_buildid(buildid)
    return buildid
end

local buildid_scratch_cache = {}

local function buildid_scratch(buildid)
    --- XXX: Always returning a fixed buildid string does not work when
    -- the scratch results gets used by results not in scratch mode.
    -- eg. if we have a result graph like this: root->tag->wc-mode->tag
    -- the final tag would only be built once and then cached globally.
    --
    -- Ideally we would use the hash of the wc-mode result.tar (and making sure
    -- that its checksum is stable), but getting it requires some bigger
    -- changes that are currently not possible.
    --
    -- Next best thing is to generate a random buildid. However, since
    -- buildid_scratch() is called multiple times, we need to cache the result
    -- to make the new buildid stable.

    -- calculate buildid only once to make stable.
    if buildid_scratch_cache[buildid] then
        return buildid_scratch_cache[buildid]
    end

    local rfile, msg, rstr
    local hc, newbuildid

    rfile, msg = io.open("/dev/urandom")
    if not rfile then
        e2lib.abort(msg)
    end

    rstr = rfile:read(16)
    if not rstr or string.len(rstr) ~= 16 then
        e2lib.abort("could not get 16 bytes of entrophy")
    end

    rfile:close()

    hc = hash.hash_start()
    hash.hash_append(hc, buildid)
    hash.hash_append(hc, rstr)

    newbuildid = hash.hash_finish(hc)
    newbuildid = "scratch-" .. newbuildid
    buildid_scratch_cache[buildid] = newbuildid

    return buildid_scratch_cache[buildid]
end

function policy.init(info)
    local e = err.new("checking policy")

    -- check if all required servers exist
    local storage = {
        storage_release,
        storage_default,
        storage_local,
        deploy_storage_default,
    }

    for _,s in ipairs(storage) do
        local location = "test/test"
        local release_id = "release-id"
        local server, location = s(location, release_id)
        local se = err.new("checking server configuration for '%s'", server)
        local ce, re = info.cache:ce_by_server(server)
        if not ce then
            se:cat(re)
        elseif not ce.flags.writeback then
            e2lib.warnf("WPOLICY",
            "Results will not be pushed to server: '%s'"..
            " (Writeback disabled)", server)
        end
        if ce and not (ce.flags.cache or ce.flags.islocal) then
            se:append(
            "Building needs local access to build results. "..
            "Enable cache.")
        elseif ce and not (ce.flags.writeback or ce.flags.cache) then
            se:append(
            "Cannot store results. "..
            "Enable cache or writeback.")
        end
        if se:getcount() > 1 then
            e:cat(se)
        end
    end
    if e:getcount() > 1 then
        return false, e
    end
    return true, nil
end

function policy.register_commandline_options()
    e2option.option("build-mode", "set build mode to calculate buildids")
    e2option.flag("tag", "set build mode to 'tag' (default)")
    e2option.flag("branch", "set build mode to 'branch'")
    e2option.flag("working-copy", "set build mode to 'working-copy'")
    e2option.flag("release", "set build mode to 'release'")
    e2option.flag("check-remote",[[
    Verify that remote resources are available
    Enabled by default in 'release' mode]])
    e2option.flag("check",[[
    Perform all checks to make sure that a build is
    reproducible except checking for remote resources
    Enabled by default in 'release' mode.]])
end

function policy.handle_commandline_options(opts, use_default)
    local default_build_mode_name = "tag"
    local nmodes = 0
    local mode = false

    if opts["build-mode"] then
        nmodes = nmodes + 1
    end
    if opts["tag"] then
        opts["build-mode"] = "tag"
        nmodes = nmodes + 1
    end
    if opts["release"] then
        opts["build-mode"] = "release"
        nmodes = nmodes + 1
    end
    if opts["branch"] then
        opts["build-mode"] = "branch"
        nmodes = nmodes + 1
    end
    if opts["working-copy"] then
        opts["build-mode"] = "working-copy"
        nmodes = nmodes + 1
    end
    if nmodes > 1 then
        return false, err.new("multiple build modes are not supported")
    end
    if not opts["build-mode"] and use_default then
        e2lib.warnf("WDEFAULT", "build-mode defaults to '%s'",
            default_build_mode_name)
        opts["build-mode"] = default_build_mode_name
    end

    if opts["build-mode"] then
        if policy.default_build_mode(opts["build-mode"]) then
            mode = policy.default_build_mode(opts["build-mode"])
        else
            return false, err.new("invalid build mode")
        end
        if opts["build-mode"] == "release" then
            opts["check-remote"] = true
            opts["check"] = true
        end
    end

    if not mode then
        return false, err.new("no build mode given")
    end

    return mode
end

function policy.default_build_mode(mode)
    if mode == "lazytag" then
        return {
            source_set = source_set_lazytag,
            dep_set = dep_set_buildid,
            buildid = buildid_buildid,
            storage = storage_default,
            deploy = false,
        }
    elseif mode == "tag" then
        return {
            source_set = source_set_tag,
            dep_set = dep_set_buildid,
            buildid = buildid_buildid,
            storage = storage_default,
            deploy = false,
        }
    elseif mode == "release" then
        return {
            source_set = source_set_tag,
            dep_set = dep_set_buildid,
            buildid = buildid_buildid,
            storage = storage_release,
            deploy = true,
            deploy_storage = deploy_storage_default,
        }
    elseif mode == "branch" then
        return {
            source_set = source_set_branch,
            dep_set = dep_set_buildid,
            buildid = buildid_buildid,
            storage = storage_default,
            deploy = false,
        }
    elseif mode == "working-copy" then
        return {
            source_set = source_set_working_copy,
            dep_set = dep_set_last,
            buildid = buildid_scratch,
            storage = storage_local,
            deploy = false,
        }
    else
        return nil
    end
end

return strict.lock(policy)

-- vim:sw=4:sts=4:et:
