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

e2policy = e2lib.module("e2policy")

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


local results_server = "results"
local release_server = "releases"
local local_server = "."
local function storage_release(location, release_id)
	return release_server, string.format("%s/release/%s", location,
								release_id)
end
local function storage_default(location, release_id)
	return results_server, string.format("%s/shared", location)
end
local function storage_local(location, release_id)
	return local_server, string.format("out")
end


local function dep_set_buildid(buildid)
	return buildid
end
local function dep_set_last(buildid)
	return "last"
end


local function buildid_buildid(buildid)
	return buildid
end
local function buildid_scratch(buildid)
	return "scratch"
end

--- set a policy mode to a value
-- @class function
-- @name policy.set
-- @param id string: the policy identifier: storage, source_set, dep_set, 
-- 			buildid
-- @param val the function to use : storage_*, source_set_*, etc.
-- @return nil
local function set(mode, id, val)
	if not id or not val then
		print(id)
		print(val)
		e2lib.abort("trying to set nil value in policy.set()")
	end
	mode[id] = val
	return nil
end

--- get a policy function
-- @class function
-- @name policy.get
-- @param id string: the policy identifier: storage, source_set, dep_set, 
-- 			buildid
-- @return function: the policy function
local function get(mode, id)
	if type(mode) ~= "table" then
		print(mode, id)
		e2lib.abort("policy.get() mode is not a table")
	end
	return mode[id]
end

--- source_set_* get the source set identifier
-- @class function
-- @name policy.source_set_*
-- @param none
-- @return string: the source set identifier

--- storage_*
-- @class function
-- @name policy.storage_*
-- @param location string: the project location
-- @param release_id string: the release id
-- @return the server to store the result on
-- @return the location to store the result in

--- dep_set_*
-- @class function
-- @name policy.dep_set_*
-- @param buildid the buildid
-- @return the buildid

--- buildid_* get the buildid for a build
-- @class function
-- @name policy.buildid_*
-- @param buildid the buildid
-- @return the buildid

function init(info)
	local e = new_error("checking policy")
	-- check if all required servers exist
	local storage = {
		storage_release,
		storage_default,
		storage_local,
	}
	for i,s in ipairs(storage) do
		local location = "test/test"
		local release_id = "release-id"
		local server, location = s(location, release_id)
		local se = new_error("checking server configuration for '%s'",
									server)
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

function register_commandline_options()
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

function handle_commandline_options(opts, use_default)
	local nmodes = 0
	local mode = nil
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
		e2lib.abort("Error: Multiple build modes are not supported")
	end
	if not opts["build-mode"] and use_default then
		e2lib.warn("WDEFAULT", string.format(
					"build-mode defaults to '%s'",
					policy.default_build_mode_name))
		opts["build-mode"] = policy.default_build_mode_name
	end
	if opts["build-mode"] then
		if policy.default_build_mode[opts["build-mode"]] then
			mode = policy.default_build_mode[opts["build-mode"]]
		else
			e2lib.abort("invalid build mode")
		end
		if opts["build-mode"] == "release" then
			opts["check-remote"] = true
			opts["check"] = true
		end
	end
	return mode
end

policy = {}
policy.init = init
policy.register_commandline_options = register_commandline_options
policy.default_build_mode_name = "tag"
policy.handle_commandline_options = handle_commandline_options
policy.set = set
policy.get = get
policy.source_set_lazytag = source_set_lazytag
policy.source_set_tag = source_set_tag
policy.source_set_branch = source_set_branch
policy.source_set_working_copy = source_set_working_copy
policy.storage_release = storage_release
policy.storage_default = storage_default
policy.storage_local = storage_local
policy.dep_set_buildid = dep_set_buildid
policy.dep_set_last = dep_set_last
policy.buildid_buildid = buildid_buildid
policy.buildid_scratch = buildid_scratch

policy.default_build_mode = {}
policy.default_build_mode["lazytag"] = {
	source_set = policy.source_set_lazytag,
	dep_set = policy.dep_set_buildid,
	buildid = policy.buildid_buildid,
	storage = policy.storage_default,
}

policy.default_build_mode["tag"] = {
	source_set = policy.source_set_tag,
	dep_set = policy.dep_set_buildid,
	buildid = policy.buildid_buildid,
	storage = policy.storage_default,
}

policy.default_build_mode["release"] = {
	source_set = policy.source_set_tag,
	dep_set = policy.dep_set_buildid,
	buildid = policy.buildid_buildid,
	storage = policy.storage_release,
}

policy.default_build_mode["branch"] = {
	source_set = policy.source_set_branch,
	dep_set = policy.dep_set_buildid,
	buildid = policy.buildid_buildid,
	storage = policy.storage_default,
}

policy.default_build_mode["working-copy"] = {
	source_set = policy.source_set_working_copy,
	dep_set = policy.dep_set_last,
	buildid = policy.buildid_scratch,
	storage = policy.storage_local,
}

