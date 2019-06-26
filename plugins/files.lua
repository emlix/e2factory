--- Files Plugin
-- @module plugins.files

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

local files = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2option = require("e2option")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local result = require("result")
local sl = require("sl")
local source = require("source")
local strict = require("strict")
local tools = require("tools")


--------------------------------------------------------------------------------

--- Generates the command to unpack an archive file.
-- @param physpath Current location and filename to be unpacked later.
-- @param virtpath Location and name of the file at the time of unpacking.
-- @param destdir Path where the unpacked files shall be put.
-- @return Tool name (string), or false on error.
-- @return Argument vector table for the tool, or an error object on failure.
local function gen_unpack_command(physpath, virtpath, destdir)

    --- Determine archive type by looking at the file extension.
    -- @param filename File name (string).
    -- @return String constant describing archive,
    -- or false if archive suffix is unknown.
    -- @return Error object on failure.
    local function archive_by_suffix(filename)
        local name = filename:lower() -- case insensitive matching
        local atype

        if name:match("%.tar$") then
            atype = "TAR"
        elseif name:match("%.tgz") or name:match("%.tar%.gz$") then
            atype = "TAR_GZ"
        elseif name:match('%.tar%.bz2$') or name:match('%.tbz2$') then
            atype = "TAR_BZIP2"
        elseif name:match("%.tar%.xz$") then
            atype = "TAR_XZ"
        elseif name:match("%.zip$") then
            atype = "ZIP"
        else
            return false, err.new("can not determine archive type of '%s'",
                filename)
        end

        return atype
    end

    local tool
    local toolargv = {}

    local atype, re = archive_by_suffix(physpath)
    if not atype then
        return false, re
    end

    if atype == "ZIP" then
        tool = "unzip"
        table.insert(toolargv, virtpath)
        table.insert(toolargv, "-d")
        table.insert(toolargv, destdir)
    elseif atype == "TAR" then
        tool = "tar"
        table.insert(toolargv, "-C")
        table.insert(toolargv, destdir)
        table.insert(toolargv, "-xf")
        table.insert(toolargv, virtpath)
    elseif atype == "TAR_GZ" then
        tool = "tar"
        table.insert(toolargv, "-z")
        table.insert(toolargv, "-C")
        table.insert(toolargv, destdir)
        table.insert(toolargv, "-xf")
        table.insert(toolargv, virtpath)
    elseif atype == "TAR_BZIP2" then
        tool = "tar"
        table.insert(toolargv, "-j")
        table.insert(toolargv, "-C")
        table.insert(toolargv, destdir)
        table.insert(toolargv, "-xf")
        table.insert(toolargv, virtpath)
    elseif atype == "TAR_XZ" then
        tool = "tar"
        table.insert(toolargv, "--xz")
        table.insert(toolargv, "-C")
        table.insert(toolargv, destdir)
        table.insert(toolargv, "-xf")
        table.insert(toolargv, virtpath)
    else
        return false, err.new("unhandled archive type")
    end

    return tool, toolargv
end

--- Handle file:copy() in a way that appears intuitive to the user. Returns
-- a directory and filename that can be passed to eg. mkdir -p and cp.
-- @param buildpath Base build path (string).
-- @param sourcename Name of the source (string).
-- @param copypath Directory or file name where the source file should be
-- copied to (string).
-- @param location Soure file location (string).
-- @param dircheck Check for destination (copypath) being an existing directory.
-- "yes" enables checking (default), "no" disables the check, and "isdir"
-- pretends destination is a directory. This flag is useful for collect_project,
-- where we don't build the source, but just look at its config.
-- @return Destination directory (string).
-- @return Destination file name (string).
local function gen_dest_dir_name(buildpath, sourcename, copypath, location,
    dircheck)

    dircheck = dircheck or "yes"
    local destdir, destname
    local destination = e2lib.join(buildpath, sourcename, copypath)

    -- It may look like ending in a file name ("/foo/bar") - but if
    -- bar is a directory, we have to copy the file into the
    -- directory. It's not always possible to check for the destination
    -- directory. dircheck therefore allows to skip the isdir check, so the
    -- reults can still be used for code generation.

    if dircheck == "isdir" or
        (dircheck == "yes" and e2lib.isdir(destination)) then
        destdir = destination
        destname = e2lib.basename(location)
    else
        -- '.' and '..' are not path components as such, but refer
        -- to the current and previous directory instead.
        -- Fixup path by appending a harmless slash, to simplify
        -- the logic below.
        local last = e2lib.basename(destination)
        if last == "." or last == ".." then
            destination = e2lib.join(destination, "")
        end

        if string.sub(destination, -1) == "/" then
            -- destination refers to a directory, indicated by the / at the end
            -- use destname from location.
            destdir = destination
            destname = e2lib.basename(location)
        else
            -- destination (potentially) ends with a file name
            destdir = e2lib.dirname(destination)
            destname = e2lib.basename(destination)
        end
    end

    return destdir, destname
end

--------------------------------------------------------------------------------

files.files_source = class("files_source", source.basic_source)

function files.files_source.static:is_selected_source_class(opts)
    assertIsTable(self)
    assertIsTable(opts)

    if e2tool.current_tool() == "fetch-sources" and opts["files"] then
        return true
    end
    return false
end

function files.files_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and #rawsrc.name > 0)
    assert(type(rawsrc.type) == "string" and rawsrc.type == "files")

    local rc, re, e

    source.basic_source.initialize(self, rawsrc)

    self._files = {}
    self._sourceid = false
    self._orig_licences = false

    rc, re = e2lib.vrfy_dict_exp_keys(rawsrc, "e2source config", {
        "env",
        "file",
        "licences",
        "name",
        "server",
        "type",
    })
    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_licences(rawsrc, self)
    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_env(rawsrc, self)
    if not rc then
        error(re)
    end

    rc, re = source.generic_source_validate_server(rawsrc, false)
    if not rc then
        error(re)
    end

    if type(rawsrc.file) ~= "table" then
        error(err.new("`file' attribute must be a table"))
    end

    -- We extend licences() later as more sub-licences are discovered.
    -- Keep a copy of the original "outer" licences
    self._orig_licences = self:licences():copy()

    e = err.new("error in file list of source")
    for _,f in ipairs(rawsrc.file) do
        local file

        if type(f) ~= "table" then
            error(e:append("`file' attribute must be a table"))
        end

        rc, re = e2lib.vrfy_dict_exp_keys(f, "e2source config",
        {
            "copy",
            "licences",
            "location",
            "patch",
            "server",
            "sha1",
            "sha256",
            "unpack",
        })
        if not rc then
            error(e:cat(re))
        end


        if (not f.server) and rawsrc.server then
            f.server = rawsrc.server
        end

        file = e2tool.file_class:new()

        rc, re = file:validate_set_servloc(f.server, f.location)
        if not rc then
            error(e:cat(re))
        end

        rc, re = file:validate_set_checksums(f.sha1, f.sha256)
        if not rc then
            error(e:cat(re))
        end

        local attrcnt = 0
        for _,attr in ipairs({"unpack", "copy", "patch"}) do
            if f[attr] ~= nil then
                attrcnt = attrcnt + 1

                if type(f[attr]) ~= "string" then
                    error(e:append(
                        "'%s' in file entry of source must be a string", attr))
                end

            end
        end

        if attrcnt == 0 then
            error(e:append("file entry without "..
                "unpack, copy or patch attribute"))
        elseif attrcnt > 1 then
            error(e:append("file entry with conflicting "..
                "unpack, copy or patch attributes"))
        end

        file:unpack(f.unpack)
        file:copy(f.copy)
        file:patch(f.patch)

        -- per file licences --
        file:licences(sl.sl:new())

        local laerr = string.format("%s:%s licences attribute",
            f.server, f.location)

        if f.licences == nil then
            file:licences():insert_sl(self._orig_licences)
        elseif type(f.licences == "table") then
            rc, re = e2lib.vrfy_listofstrings(f.licences, laerr, true, false)
            if not rc then
                error(e:cat(re))
            end

            for _,licencename in ipairs(f.licences) do
                if not licence.licences[licencename] then
                    error(e:append("%s has unknown licence: %q",
                        laerr, licencename))
                end

                -- Make sure the main licences list contains every licence in
                -- the entire source.
                self:licences():insert(licencename)
                file:licences():insert(licencename)
            end
        else
            error(e:append("%s must be a table", laerr))
        end

        table.insert(self._files, file)
    end
end

function files.files_source:file_iter()
    local i = 0

    return function ()
        i = i + 1

        if self._files[i] then
            return self._files[i]:instance_copy()
        end

        return nil
    end
end

function files.files_source:sourceid(sourceset)
    assertIsStringN(sourceset)

    local hc, licences

    if self._sourceid then
        return self._sourceid
    end

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)
    hash.hash_append(hc, self._env:envid())

    -- all licences
    for licencename in self:licences():iter() do
        local lid, re = licence.licences[licencename]:licenceid()
        if not lid then
            return false, re
        end
        hash.hash_append(hc, lid)
    end

    for file in self:file_iter() do
        local fileid, re = file:fileid()
        if not fileid then
            return false, re
        end
        hash.hash_append(hc, fileid)
    end

    self._sourceid = hash.hash_finish(hc)

    e2lib.logf(4, "BUILDID: source=%s sourceid=%s", self._name, self._sourceid)

    return self._sourceid
end

--- create a table of lines for display
-- @return a table
function files.files_source:display(sourceset)
    assertIsStringN(sourceset)

    local s, sid, d, licences

    self:sourceid(sourceset)

    d = {}
    table.insert(d, string.format("type       = %s", self:get_type()))
    table.insert(d, string.format("licences   = %s",
        self:licences():concat(" ")))

    for file in self:file_iter() do
        s = string.format("file       = %s", file:servloc())
        table.insert(d, s)
        table.insert(d, string.format("licences   = %s",
            file:licences():concat(" ")))
    end

    if self._sourceid then
        table.insert(d, string.format("sourceid   = %s", self._sourceid))
    end

    return d
end

function files.files_source:working_copy_available()
    return false, err.new("source %s doesn't require a working copy", self._name)
end

function files.files_source:check_workingcopy()
    return true
end

function files.files_source:fetch_source()
    local rc, re
    local e = err.new("fetching source failed: %s", self._name)

    for file in self:file_iter() do
        if cache.cache_enabled(cache.cache(), file:server()) then
            e2lib.logf(3, "files.fetch_source: caching file %s", file:servloc())
            rc, re = cache.fetch_file_path(cache.cache(), file:server(), file:location())
            if not rc then
                return false, e:cat(re)
            end
        else
            e2lib.logf(3, "not caching %s (stored locally)", file:servloc())
        end
    end

    return true
end

function files.files_source:update_source()
    return true, nil
end

function files.files_source:prepare_source(sourceset, buildpath)
    local rc, re
    local e = err.new("error preparing source: %s", self._name)
    local symlink = nil

    for file in self:file_iter() do
        rc, re = file:checksum_verify()
        if not rc then
            return false, e:cat(re)
        end
        if file:unpack() then
            local path, re = cache.fetch_file_path(cache.cache(),
                file:server(), file:location())
            if not path then
                return false, e:cat(re)
            end

            local rc, re = gen_unpack_command(path, path, buildpath)
            if not rc then
                return false, e:cat(re)
            end

            local tool, toolargv = rc, re
            rc, re = e2lib.call_tool_argv(tool, toolargv)
            if not rc then
                e:cat(err.new("unpacking archive '%s' failed", path))
                return false, e:cat(re)
            end

            local expected_location = e2lib.join(buildpath, file:unpack())
            if not e2lib.stat(expected_location) then
                return false, err.new("expected unpack location '%s' does not exist",
                    expected_location)
            end

            if not symlink then
                symlink = buildpath .. "/" .. self._name
                if file:unpack() ~= self._name then
                    rc, re = e2lib.symlink(file:unpack(), symlink)
                    if not rc then
                        return false, e:cat(re)
                    end


                end
            end
        else
            if not symlink then
                symlink = buildpath .. "/" .. self._name
                rc, re = e2lib.mkdir_recursive(symlink)
                if not rc then
                    return false, e:cat(re)
                end
            end
            if file:patch() then
                local path, re = cache.fetch_file_path(cache.cache(),
                    file:server(), file:location())
                if not path then
                    return false, e:append(re)
                end
                local argv = { "-p", file:patch(), "-d", symlink, "-i", path }
                rc, re = e2lib.call_tool_argv("patch", argv)
                if not rc then
                    e:append("applying patch: \"%s\"", file:servloc())
                    return false, e:cat(re)
                end
            elseif file:copy() then
                local destdir, destname
                destdir, destname = gen_dest_dir_name(buildpath, self._name,
                    file:copy(), file:location())

                rc, re = e2lib.mkdir_recursive(destdir)
                if not rc then
                    re = err.new("creating directory failed: %s", re)
                    return false, e:cat(re)
                end

                local rc, re = cache.fetch_file(cache.cache(), file:server(),
                    file:location(), destdir, destname, {})
                if not rc then
                    return false, e:cat(re)
                end
            else
                return false, err.new("missing destination for file %s (%s)",
                    file:location(), file:server())
            end
        end
    end
    return true, nil
end

--------------------------------------------------------------------------------

--- Create a source result containing the generated Makefile and files
-- belonging to the source, for use with collect_project.
-- Result refers to a collection of files to recreate an e2source for
-- collect_project in this context.
-- @param src Source object.
-- @param sourceset Unused.
-- @param directory Name of the source directory (string).
-- @return Boolean, true on success.
-- @return An error object on failure.
local function files_to_result(src, sourceset, directory)
    local rc, re, out
    local e = err.new("converting result failed")
    local source = "source"     -- directory to store source files in
    local BUILDq = e2lib.shquote("$(BUILD)")  -- pre-quoted _make_ variable
    local makefile = e2lib.join(directory, "Makefile")

    out = { ".PHONY: place\n\nplace:\n" }
    for file in src:file_iter() do
        rc, re = file:checksum_verify()
        if not rc then
            return false, e:cat(re)
        end

        local destdir = string.format("%s/%s", directory, source)
        local destname = e2lib.basename(file:location())

        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end

        if e2lib.stat(e2lib.join(destdir, destname)) then
            return false,
                e:cat("can not convert source %q due to multiple files named %q",
                src:get_name(), destname)
        end

        rc, re = cache.fetch_file(cache.cache(), file:server(), file:location(),
            destdir, destname, {})
        if not rc then
            return false, e:cat(re)
        end
        if file:sha1() then
            local filename = e2lib.basename(file:location())
            local checksum_file = string.format("%s/%s.sha1",
                destdir, filename)
            rc, re = eio.file_write(checksum_file,
                string.format("%s  %s", file:sha1(), filename))
            if not rc then
                return false, e:cat(re)
            end
            table.insert(out, string.format("\tcd source && sha1sum -c '%s'\n",
                e2lib.basename(checksum_file)))
        end
        if file:unpack() then
            local physpath = e2lib.join(destdir, e2lib.basename(file:location()))
            local virtpath = e2lib.join(source, e2lib.basename(file:location()))
            local rc, re = gen_unpack_command(physpath, virtpath, "$(BUILD)") -- BUILD quoting ok
            if not rc then
                e:cat("unable to generate unpack command")
                return false, e:cat(re)
            end

            local tool, toolargv = rc, re
            local toolname, re = tools.get_tool_name(tool)
            if not toolname then
                return false, e:cat(re)
            end

            table.insert(out, string.format("\t%s", toolname))
            for _,v in ipairs(toolargv) do
                table.insert(out, string.format(" %s", e2lib.shquote(v)))
            end
            table.insert(out, "\n")

            if file:unpack() ~= src:get_name() then
                table.insert(out, string.format("\tln -s %s %s/%s\n",
                    e2lib.shquote(file:unpack()), BUILDq,
                    e2lib.shquote(src:get_name())))
            end
        end
        if file:copy() then
            local to, from
            from = e2lib.shquote(
                e2lib.join(source, e2lib.basename(file:location())))

            local destdir, destname = gen_dest_dir_name("/", src:get_name(),
                file:copy(), file:location(), "isdir")
            --
            -- is a directory?
            --
            to = string.format("%s%s", BUILDq, e2lib.shquote(destdir))
            table.insert(out, string.format('\tif [ -d %s ]; then \\\n', to))

            to = string.format('%s%s', BUILDq,
                e2lib.shquote(e2lib.join(destdir, destname)))
            table.insert(out, string.format('\t\tcp %s %s; \\\n', from, to))
            table.insert(out, string.format('\telse \\\n'))
            --
            -- not a directory
            --
            destdir, destname = gen_dest_dir_name("/", src:get_name(), file:copy(),
                file:location(), "no")

            to = string.format('%s%s', BUILDq, e2lib.shquote(destdir))
            table.insert(out, string.format('\t\tmkdir -p %s; \\\n', to))

            to = string.format('%s%s', BUILDq,
                e2lib.shquote(e2lib.join(destdir, destname)))
            table.insert(out, string.format('\t\tcp %s %s; \\\n', from, to))
            table.insert(out, '\tfi\n')
        end
        if file:patch() then
            local to = e2lib.shquote(e2lib.join(source, e2lib.basename(file:location())))
            table.insert(out, string.format(
                "\tpatch -p%s -d %s/%s -i %s/%s\n",
                file:patch(), BUILDq, e2lib.shquote(src:get_name()),
                e2lib.shquote("$(shell pwd)"), to))
        end
        -- write licences
        local destdir = string.format("%s/licences", directory)
        local fname = string.format("%s/%s.licences", destdir,
            e2lib.basename(file:location()))
        local licence_list = file:licences():concat("\n") .. "\n"
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end
        rc, re = eio.file_write(fname, licence_list)
        if not rc then
            return false, e:cat(re)
        end
        e2lib.logf(4, "export file: %s done", file:location())
    end

    rc, re = eio.file_write(makefile, table.concat(out))
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--------------------------------------------------------------------------------

plugin_descriptor = {
    description = "Files SCM Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("files", files.files_source)
        if not rc then
            return false, re
        end

        if e2tool.current_tool() == "fetch-sources" then
            e2option.flag("files", "select files sources")
        end

        for typ, theclass in result.iterate_result_classes() do
            if typ == "collect_project" then
                theclass:add_source_to_result_fn("files", files_to_result)
                break
            end
        end

        return true
    end,
    exit = function (ctx)
        local rc, re

        for typ, theclass in result.iterate_result_classes() do
            if typ == "collect_project" then
                theclass:remove_source_to_result_fn("files", files_to_result)
                break
            end
        end

        rc, re = source.deregister_source_class("files", files.files_source)
        if not rc then
            return false, re
        end

        return true
    end,
    depends = {
        "collect_project.lua",
    }
}


strict.lock(files)

-- vim:sw=4:sts=4:et:
