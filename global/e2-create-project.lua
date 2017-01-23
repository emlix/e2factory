--- e2-create-project command
-- @module global.e2-create-project

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
local eio = require("eio")
local cache = require("cache")
local generic_git = require("generic_git")
local err = require("err")
local e2option = require("e2option")
local buildconfig = require("buildconfig")
local url = require("url")

--- Create a extensions config.
-- @param extension_config Extension file name.
-- @param extensions Extension table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function write_extension_config(extension_config, extensions)
    local e, rc, re, file, out

    e = err.new("writing extensions config: %s", extension_config)

    out = "extensions {\n"
    for _,ex in ipairs(extensions) do
        out = out .. "  {\n"
        for k,v in pairs(ex) do
            out = out .. string.format("    %s=\"%s\",\n", k, v)
        end
        out = out .. "  },\n"
    end
    out = out .. "}\n"

    rc, re = eio.file_write(extension_config, out)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- Read a template file, located relative to the current template directory.
-- @param path Filename relative to the template directory.
-- @return File contents as a string, or false on error.
-- @return Error object on failure.
local function read_template(path)
    local e, rc, re, file, filename, template, buf
    e = err.new("error reading template file")

    filename = e2lib.join(e2lib.globals.template_path, path)
    file, re = eio.fopen(filename, "r")
    if not file then
        return false, e:cat(re)
    end

    template = ""
    repeat
        buf, re = eio.fread(file, 4096)
        if not buf then
            eio.fclose(file)
            return false, e:cat(re)
        end
        template = template .. buf
    until buf == ""

    rc, re = eio.fclose(file)
    if not rc then
        return false, e:cat(re)
    end

    return template
end

--- Create a new project.
-- @param arg Commandline arguments.
-- @return True on success, false on error.
-- @return Error object on failure.
local function e2_create_project(arg)
    local rc, re, e

    rc, re = e2lib.init()
    if not rc then
        error(re)
    end

    local opts, arguments = e2option.parse(arg)
    if not opts then
        error(arguments)
    end

    rc, re = e2lib.init2()
    if not rc then
        error(re)
    end

    e = err.new("creating project failed")

    local config, re = e2lib.get_global_config()
    if not config then
        error(e:cat(re))
    end

    rc, re = cache.setup_cache(config)
    if not rc then
        error(e:cat(re))
    end

    cache.cache(rc)

    rc, re = cache.setup_cache_apply_opts(cache.cache())
    if not rc then
        error(e:cat(re))
    end

    if #arguments ~= 1 then
        e2option.usage(1)
    end

    local sl, re = e2lib.parse_server_location(arguments[1],
        e2lib.globals.default_projects_server)
    if not sl then
        error(e:cat(re))
    end

    if not cache.writeback_enabled(cache.cache(), sl.server) then
        e2lib.warnf("WOTHER", "enabling writeback for server: %s",
            sl.server)
        rc, re = cache.set_writeback(cache.cache(), sl.server, true)
        if not rc then
            error(e:cat(re))
        end
    end

    local p = {}
    p.version = buildconfig.GLOBAL_INTERFACE_VERSION[1] -- the project version
    p.e2version = string.format("%s %s",
        config.site.e2_branch, config.site.e2_tag)
    p.server = sl.server				-- the server
    p.location = sl.location			-- the project location
    p.name = e2lib.basename(sl.location)		-- the project basename

    -- create the server side structure
    local tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        error(re)
    end

    local version = string.format("%d\n", p.version)
    local empty = ""
    local files = {
        { filename = "version", content=version },
        { filename = "proj/.keep", content=empty },
        { filename = "git/.keep", content=empty },
        { filename = "files/.keep", content=empty },
        { filename = "cvs/.keep", content=empty },
        { filename = "svn/.keep", content=empty },
    }
    for _,f in ipairs(files) do
        local sourcefile, flocation

        sourcefile = e2lib.join(tmpdir, f.filename)

        rc, re = e2lib.mkdir_recursive(e2lib.dirname(sourcefile))
        if not rc then
            error(e:cat(re))
        end

        rc, re = eio.file_write(sourcefile, f.content)
        if not rc then
            error(e:cat(re))
        end

        flocation = e2lib.join(p.location, f.filename)
        rc, re = cache.push_file(cache.cache(), sourcefile, p.server, flocation)
        if not rc then
            error(e:cat(re))
        end
    end
    e2lib.rmtempdir(tmpdir)

    tmpdir, re = e2lib.mktempdir()
    if not tmpdir then
        error(re)
    end

    -- create the initial repository on server side

    local rlocation = string.format("%s/proj/%s.git", p.location, p.name)
    rc, re = generic_git.git_init_db(cache.cache(), p.server, rlocation)
    if not rc then
        error(e:cat(re))
    end

    -- works up to this point

    -- create the initial (git) repository
    local tmp_repo_url, tmp_repo_path

    tmp_repo_url, re = url.parse(string.format("file://%s/.git", tmpdir))
    if not tmp_repo_url then
        error(e:cat(re))
    end
    tmp_repo_path, re = url.to_file_path(tmp_repo_url)
    if not tmp_repo_path then
        error(e:cat(re))
    end

    rc, re = generic_git.git_init_db1(tmp_repo_url.url, false)
    if not rc then
        error(e:cat(re))
    end

    local gitignore, re = read_template("gitignore")
    if not gitignore then
        error(re)
    end
    local chroot, re = read_template("proj/chroot")
    if not chroot then
        error(re)
    end
    local licences, re = read_template("proj/licences")
    if not licences then
        error(re)
    end
    local env, re = read_template("proj/env")
    if not env then
        error(re)
    end
    local pconfig, re = read_template("proj/config")
    if not pconfig then
        error(re)
    end
    pconfig = pconfig:gsub("<<release_id>>", p.name)
    pconfig = pconfig:gsub("<<name>>", p.name)
    local name = string.format("%s\n", p.name)
    local release_id = string.format("%s\n", p.name) -- use the name for now
    local version = string.format("%s\n", p.version)
    local e2version = string.format("%s\n", p.e2version)
    local syntax = string.format("%s\n", buildconfig.SYNTAX[1])
    local empty = ""
    local files = {
        { filename = ".e2/.keep", content=empty },
        { filename = "in/.keep", content=empty },
        { filename = "log/.keep", content=empty },
        { filename = "proj/init/.keep", content=empty },
        { filename = "res/.keep", content=empty },
        { filename = "src/.keep", content=empty },
        { filename = "proj/chroot", content=chroot },
        { filename = "proj/licences", content=licences },
        { filename = "proj/env", content=env },
        { filename = "proj/config", content=pconfig },
        { filename = e2lib.globals.syntax_file, content=syntax },
        { filename = e2lib.globals.e2version_file, content=e2version },
        { filename = ".gitignore", content=gitignore },
    }
    for _,f in ipairs(files) do
        local sourcefile

        sourcefile = e2lib.join(tmpdir, f.filename)
        rc, re = e2lib.mkdir_recursive(e2lib.dirname(sourcefile))
        if not rc then
            error(e:cat(re))
        end
        rc, re = eio.file_write(sourcefile, f.content)
        if not rc then
            error(e:cat(re))
        end
        rc, re = generic_git.git_add(tmp_repo_path, { f.filename })
        if not rc then
            error(e:cat(re))
        end
    end
    local ec = e2lib.join(tmpdir, e2lib.globals.extension_config)
    rc, re = write_extension_config(ec, config.site.default_extensions)
    if not rc then
        error(e:cat(re))
    end
    rc, re = generic_git.git_add(tmp_repo_path,
        { e2lib.globals.extension_config })
    if not rc then
        error(e:cat(re))
    end
    rc, re = generic_git.git_commit(tmp_repo_path, { "-m", "project setup" })
    if not rc then
        error(e:cat(re))
    end

    local refspec = "master:refs/heads/master"
    local rlocation = string.format("%s/proj/%s.git", p.location, p.name)
    rc, re = generic_git.git_push(cache.cache(), tmp_repo_path, p.server,
        rlocation, refspec)
    if not rc then
        error(e:cat(re))
    end

    e2lib.rmtempdir(tmpdir)
end

local pc, re = e2lib.trycall(e2_create_project, arg)
if not pc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
