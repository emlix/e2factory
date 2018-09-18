--- e2-fetch-project command
-- @module global.e2-fetch-project

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

local e2lib = require("e2lib")
local e2option = require("e2option")
local eio = require("eio")
local generic_git = require("generic_git")
local cache = require("cache")
local err = require("err")
local buildconfig = require("buildconfig")

local function e2_fetch_project(arg)
    local rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local e = err.new("fetching project failed")

    -- e2-install-e2 (called below) uses the same arg vector. Update
    -- e2-install-e2 to ignore any options specific to e2-fetch-project.
    e2option.option("branch", "retrieve a specific project branch")
    e2option.option("tag", "retrieve a specific project tag")

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    rc, re = e2lib.init2()
    if not rc then
        error(re)
    end

    local config, re = e2lib.get_global_config()
    if not config then
        error(e:cat(re))
    end

    -- setup cache
    rc, re = cache.setup_cache(config)
    if not rc then
        error(e:cat(re))
    end

    cache.cache(rc)

    rc, re = cache.setup_cache_apply_opts(cache.cache())
    if not rc then
        error(e:cat(re))
    end

    -- standard global tool setup finished

    if #arguments < 1 then
        error(err.new("specify path to a project to fetch"))
    end
    if #arguments > 2 then
        error(err.new("too many arguments"))
    end

    local sl, re = e2lib.parse_server_location(arguments[1],
        e2lib.globals.default_projects_server)
    if not sl then
        error(e:cat(re))
    end

    local p = {}
    p.server = sl.server
    p.location = sl.location
    p.name = e2lib.basename(p.location)
    if arguments[2] then
        p.destdir = arguments[2]
    else
        p.destdir = p.name
    end

    -- Make destdir an absolute path.
    if string.sub(p.destdir, 1, 1) ~= "/" then
        rc, re = e2lib.cwd()
        if not rc then
            error(e:cat(re))
        end

        p.destdir = e2lib.join(rc, p.destdir)
    end

    if opts["branch"] then
        p.branch = opts["branch"]
    else
        p.branch = nil
    end
    if opts["tag"] then
        p.tag = opts["tag"]
    else
        p.tag = nil
    end

    -- fetch project descriptor file
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        error(re)
    end

    local location = string.format("%s/version", p.location)
    local rc, re = cache.fetch_file(cache.cache(), p.server, location, tmpdir, nil,
        { cache = false })
    if not rc then
        error(e:cat(re))
    end

    -- read the version from the first line
    local version_file = string.format("%s/version", tmpdir)
    local line, re = eio.file_read_line(version_file)
    if not line then
        error(e:cat(re))
    end
    e2lib.rmtempdir()

    local v = tonumber(line:match("[0-9]+"))
    if not v or v < 1 or v > 2 then
        error(e:append("unhandled project version"))
    end

    -- version is 1 or 2

    -- clone the git repository
    local location = string.format("%s/proj/%s.git", p.location, p.name)
    local skip_checkout = false
    local rc, re = generic_git.git_clone_from_server(cache.cache(), p.server, location,
        p.destdir, skip_checkout)
    if not rc then
        error(e:cat(re))
    end

    -- checkout the desired branch, if a branch was given
    if p.branch then
        local id
        local e = e:append("checking out branch failed: %s", p.branch)

        -- Because the repository is freshly cloned, we can assume that when a
        -- ref for the requested branch exists, HEAD is at that branch.
        rc, re, id = generic_git.lookup_id(e2lib.join(p.destdir, ".git"),
            false, "refs/heads/" .. p.branch)
        if not rc then
            error(e:cat(re))
        end
        if not id then
            rc, re = generic_git.git_branch_new1(p.destdir, true, p.branch,
                "origin/" .. p.branch)
            if not rc then
                error(e:cat(re))
            end

            -- checkout prefixes branch with "refs/heads/" on its own,
            -- creates detached branch for full ref(!!)
            rc, re = generic_git.git_checkout1(p.destdir, p.branch)
            if not rc then
                error(e:cat(re))
            end
        end
    end

    -- checkout the desired tag, if a tag was given
    if p.tag then
        local e = e:append("checking out tag failed: %s", p.tag)
        if p.branch then
            -- branch and tag were specified. The working branch was created above.
            -- Warn and go on checking out the tag...
            e2lib.warnf("WOTHER",
            "switching to tag '%s' after checking out branch '%s'",
            p.tag, p.branch)
        end

        rc, re = generic_git.git_checkout1(p.destdir, "refs/tags/" .. p.tag)
        if not rc then
            error(e:cat(re))
        end
    end

    -- write project location file
    local plf = e2lib.join(p.destdir, e2lib.globals.project_location_file)
    local data = string.format("%s\n", p.location)
    rc, re = eio.file_write(plf, data)
    if not rc then
        error(e:cat(re))
    end

    -- write version file
    local givf = e2lib.join(p.destdir, e2lib.globals.global_interface_version_file)
    rc, re = eio.file_write(givf, string.format("%d\n", v))
    if not rc then
        error(e:cat(re))
    end

    local e2_install_e2 =
        { buildconfig.LUA, e2lib.join(buildconfig.TOOLDIR, "e2-install-e2") }

    -- pass flags and options to e2-install-e2, but skip the arguments.
    for _,v in ipairs(arg) do
        for _,a in ipairs(arguments) do
            if v == a then
                v = nil
                break
            end
        end

        if v then
            table.insert(e2_install_e2, v)
        end
    end

    -- call e2-install-e2
    rc, re = e2lib.callcmd_log(e2_install_e2, p.destdir)
    if not rc or rc ~= 0 then
        local e = err.new("installing local e2 failed")
        error(e:cat(re))
    end
end

local pc, re = e2lib.trycall(e2_fetch_project, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
