--- Files Plugin
-- @module plugins.files

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

local files = {}
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local eio = require("eio")
local err = require("err")
local hash = require("hash")
local licence = require("licence")
local scm = require("scm")
local sl = require("sl")
local source = require("source")
local strict = require("strict")
local tools = require("tools")


plugin_descriptor = {
    description = "Files SCM Plugin",
    init = function (ctx)
        local rc, re

        rc, re = source.register_source_class("files", files.files_source)
        if not rc then
            return false, re
        end

        rc, re = scm.register("files", files)
        if not rc then
            return false, re
        end

        return true
    end,
    exit = function (ctx) return true end,
}

files.files_source = class("files_source", source.basic_source)

function files.files_source:initialize(rawsrc)
    assert(type(rawsrc) == "table")
    assert(type(rawsrc.name) == "string" and #rawsrc.name > 0)
    assert(type(rawsrc.type) == "string" and rawsrc.type == "files")

    local rc, re, e, info

    source.basic_source.initialize(self, rawsrc)

    self._files = {}
    self._sourceid = false

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

    e = err.new("error in file list of source")
    for _,f in ipairs(rawsrc.file) do
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
            "unpack",
        })
        if not rc then
            error(e:cat(re))
        end


        if (not f.server) and rawsrc.server then
            f.server = rawsrc.server
        end

        info = e2tool.info()

        if not f.server then
            error(e:append("file entry without `server' attribute"))
        end
        if f.server and (not cache.valid_server(info.cache, f.server)) then
            error(e:append("invalid server: %s", f.server))
        end
        if not f.location then
            error(e:append("file entry without `location' attribute"))
        end
        if f.server ~= info.root_server_name and not f.sha1 then
            error(e:append("file entry for remote file without "..
            "`sha1` attribute"))
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

        assert(type(f.location) == "string" and f.location ~= "")
        assert(type(f.server) == "string" and f.server ~= "")
        assert(f.sha1 == nil or (type(f.sha1) == "string" and #f.sha1 == 40))

        -- per file licences --
        local laerr = string.format("%s:%s licences attribute",
            f.server, f.location)
        local llist, licences

        if f.licences == nil then
            f.licences = self:get_licences():copy()
        elseif type(f.licences == "table") then
            rc, re = e2lib.vrfy_listofstrings(f.licences, laerr, true, false)
            if not rc then
                error(e:cat(re))
            end

            licences = self:get_licences()
            llist = sl.sl:new(false, true)

            for _,licencename in ipairs(f.licences) do
                if not licence.licences[licencename] then
                    error(e:append("%s has unknown licence: %q",
                        laerr, licencename))
                end

                -- Make sure the _licences list contains every licence in the
                -- entire source. Duplicates are rejected by unique string list.
                licences:insert(licencename)
                assert(llist:insert(licencename))
            end

            self:set_licences(licences)
            f.licences = llist
        else
            error(e:append("%s must be a table", laerr))
        end

        if f.unpack then
            assert(type(f.unpack) == "string")

            table.insert(self._files, {
                location=f.location,
                server=f.server,
                sha1=f.sha1,
                unpack=f.unpack,
                licences=f.licences,
            })
        elseif f.copy then
            assert(type(f.copy) == "string")

            table.insert(self._files, {
                location=f.location,
                server=f.server,
                sha1=f.sha1,
                copy=f.copy,
                licences=f.licences,
            })
        elseif f.patch then
            assert(type(f.patch) == "string")

            table.insert(self._files, {
                location=f.location,
                server=f.server,
                sha1=f.sha1,
                patch=f.patch,
                licences=f.licences,
            })
        else
            assert("internal error" == true)
        end
    end
end

function files.files_source:file_iter()
    local i = 0

    return function ()
        i = i + 1

        if self._files[i] then
            -- return a copy so nobody can mess with the internals
            local f = {
                location = self._files[i].location,
                server = self._files[i].server,
                sha1 = self._files[i].sha1,
                licences = self._files[i].licences:copy()
            }
            for _,attr in ipairs({ "copy", "unpack", "patch" }) do
                if self._files[i][attr] then
                    f[attr] = self._files[i][attr]
                    break
                end
            end
            return f
        end

        return nil
    end
end

function files.files_source:sourceid(sourceset --[[always ignored for files]])
    local hc, info, licences

    if self._sourceid then
        return self._sourceid
    end

    info = e2tool.info()
    assert(info)

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)
    hash.hash_append(hc, self._type)
    hash.hash_append(hc, self._env:id())

    for f in self:file_iter() do
        local fileid, re = e2tool.fileid(info, f)
        if not fileid then
            return false, re
        end
        hash.hash_append(hc, fileid)
        hash.hash_append(hc, f.location)
        hash.hash_append(hc, f.server)
        hash.hash_append(hc, tostring(f.unpack))
        hash.hash_append(hc, tostring(f.patch))
        hash.hash_append(hc, tostring(f.copy))

        -- per file licence list
        for licencename in f.licences:iter_sorted() do
            local lid, re = licence.licences[licencename]:licenceid(info)
            if not lid then
                return false, re
            end
            hash.hash_append(hc, lid)
        end
    end

    self._sourceid = hash.hash_finish(hc)

    return self._sourceid
end

--- create a table of lines for display
-- @return a table
function files.files_source:display()
    local s, sid, d, licences

    self:sourceid()

    d = {}
    table.insert(d, string.format("type       = %s", self:get_type()))

    for f in self:file_iter() do
        s = string.format("file       = %s:%s", f.server, f.location)
        table.insert(d, s)
        table.insert(d, string.format("licence    = %s", f.licences:concat_sorted(", ")))
    end

    if self._sourceid then
        table.insert(d, string.format("sourceid   = %s", self._sourceid))
    end

    return d
end

--- cache files for a source
-- @param info the info structure
-- @param sourcename name of the source
-- @return bool
-- @return nil, an error string on error
function files.cache_source(info, sourcename)
    local rc, re
    local src = source.sources[sourcename]

    -- cache all files for this source
    for f in src:file_iter() do
        e2lib.logf(4, "files.cache_source: caching file %s:%s", f.server,
            f.location)
        local flags = { cache = true }
        if f.server ~= info.root_server_name then
            rc, re = cache.cache_file(info.cache, f.server, f.location, flags)
            if not rc then
                return false, re
            end
        else
            e2lib.logf(4, "not caching %s:%s (stored locally)", f.server,
                f.location)
        end
    end
    return true
end

function files.fetch_source(info, sourcename)
    local rc, re
    local e = err.new("fetching source failed: %s", sourcename)
    local rc, re = files.cache_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

function files.working_copy_available(info, sourcename)
    return false
end

function files.has_working_copy(info, sourcename)
    return false
end

--- Handle file.copy in a way that appears intuitive to the user. Returns
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
        -- '.' and '..' or not path components as such, but refer
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
    elseif name:match("%.tar%.bz2$") then
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

--- Generates the command to unpack an archive file.
-- @param physpath Current location and filename to be unpacked later.
-- @param virtpath Location and name of the file at the time of unpacking.
-- @param destdir Path where the unpacked files shall be put.
-- @return Tool name (string), or false on error.
-- @return Argument vector table for the tool, or an error object on failure.
local function gen_unpack_command(physpath, virtpath, destdir)
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

--- Call the patch command
-- @param argv Vector of arguments supplied to patch tool.
-- @return True on success, false on error.
-- @return Error object on failure.
local function patch_tool(argv)
    return e2lib.call_tool_argv("patch", argv)
end

--- Prepare a files source.
-- @param info The info table.
-- @param sourcename The source name (string)
-- @param sourceset Unused.
-- @param buildpath Base path of the build directory ($T/build) (string).
-- @see toresult
-- @return bool
-- @return nil, maybe an error string on error
function files.prepare_source(info, sourcename, sourceset, buildpath)
    local rc, re
    local e = err.new("error preparing source: %s", sourcename)
    local symlink = nil
    local src = source.sources[sourcename]

    for file in src:file_iter() do
        if file.sha1 then
            rc, re = e2tool.verify_hash(info, file.server, file.location, file.sha1)
            if not rc then
                return false, e:cat(re)
            end
        end
        if file.unpack then
            local cache_flags = { cache = true }
            local rc, re = cache.cache_file(info.cache, file.server,
                file.location, cache_flags)
            if not rc then
                return false, e:cat(re)
            end
            local path, re = cache.file_path(info.cache, file.server, file.location)
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

            local expected_location = e2lib.join(buildpath, file.unpack)
            if not e2lib.stat(expected_location, true) then
                return false, err.new("expected unpack location '%s' does not exist",
                    expected_location)
            end

            if not symlink then
                symlink = buildpath .. "/" .. sourcename
                if file.unpack ~= sourcename then
                    rc, re = e2lib.symlink(file.unpack, symlink)
                    if not rc then
                        return false, e:cat(re)
                    end


                end
            end
        else
            if not symlink then
                symlink = buildpath .. "/" .. sourcename
                rc, re = e2lib.mkdir_recursive(symlink)
                if not rc then
                    return false, e:cat(re)
                end
            end
            if file.patch then
                local cache_flags = { cache = true }
                local rc, re = cache.cache_file(info.cache, file.server,
                    file.location, cache_flags)
                if not rc then
                    return false, e:cat(re)
                end
                local path, re = cache.file_path(info.cache, file.server, file.location)
                if not path then
                    return false, e:append(re)
                end
                local argv = { "-p", file.patch, "-d", symlink, "-i", path }
                rc, re = patch_tool(argv)
                if not rc then
                    e:append("applying patch: \"%s:%s\"", file.server, file.location)
                    return false, e:cat(re)
                end
            elseif file.copy then
                local destdir, destname
                destdir, destname = gen_dest_dir_name(buildpath, sourcename,
                    file.copy, file.location)

                rc, re = e2lib.mkdir_recursive(destdir)
                if not rc then
                    re = err.new("creating directory failed: %s", re)
                    return false, e:cat(re)
                end

                local rc, re = cache.fetch_file(info.cache, file.server,
                    file.location, destdir, destname, {})
                if not rc then
                    return false, e:cat(re)
                end
            else
                return false, err.new("missing destination for file %s (%s)",
                    file.location, file.server)
            end
        end
    end
    return true, nil
end

--- Create a source result containing the generated Makefile and files
-- belonging to the source, for use with collect_project.
-- Result refers to a collection of files to recreate an e2source for
-- collect_project in this context.
-- @param info The info table.
-- @param sourcename Source name (string).
-- @param sourceset Unused.
-- @param directory Name of the source directory (string).
-- @return Boolean, true on success.
-- @return An error object on failure.
function files.toresult(info, sourcename, sourceset, directory)
    local rc, re, out
    local e = err.new("converting result failed")
    local src = source.sources[sourcename]
    local source = "source"     -- directory to store source files in
    local makefile = e2lib.join(directory, "Makefile")

    out = { ".PHONY: place\n\nplace:\n" }
    for file in src:file_iter() do
        e2lib.logf(4, "export file: %s", file.location)
        local destdir = string.format("%s/%s", directory, source)
        local destname = nil

        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end
        rc, re = cache.fetch_file(info.cache, file.server, file.location,
            destdir, destname, {})
        if not rc then
            return false, e:cat(re)
        end
        if file.sha1 then
            local filename = e2lib.basename(file.location)
            local checksum_file = string.format("%s/%s.sha1",
                destdir, filename)
            rc, re = eio.file_write(checksum_file,
                string.format("%s  %s", file.sha1, filename))
            if not rc then
                return false, e:cat(re)
            end
            table.insert(out, string.format("\tcd source && sha1sum -c '%s'\n",
                e2lib.basename(checksum_file)))
        end
        if file.unpack then
            local physpath = e2lib.join(destdir, e2lib.basename(file.location))
            local virtpath = e2lib.join(source, e2lib.basename(file.location))
            local rc, re = gen_unpack_command(physpath, virtpath, "$(BUILD)")
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

            if file.unpack ~= sourcename then
                table.insert(out, string.format("\tln -s %s $(BUILD)/%s\n",
                    file.unpack, sourcename))
            end
        end
        if file.copy then
            local to, from
            from = e2lib.shquote(
                e2lib.join(source, e2lib.basename(file.location)))

            local destdir, destname = gen_dest_dir_name("/", sourcename,
                file.copy, file.location, "isdir")
            --
            -- is a directory?
            --
            to = string.format('"$(BUILD)"%s', e2lib.shquote(destdir))
            table.insert(out, string.format('\tif [ test -d %s ]; then \\\n', to))

            to = string.format('"$(BUILD)"%s',
                e2lib.shquote(e2lib.join(destdir, destname)))
            table.insert(out, string.format('\t\tcp %s %s; \\\n', from, to))
            table.insert(out, string.format('\telse \\\n'))
            --
            -- not a directory
            --
            destdir, destname = gen_dest_dir_name("/", sourcename, file.copy,
                file.location, "no")

            to = string.format('"$(BUILD)"%s', e2lib.shquote(destdir))
            table.insert(out, string.format('\t\tmkdir -p %s; \\\n', to))

            to = string.format('"$(BUILD)"%s',
                e2lib.shquote(e2lib.join(destdir, destname)))
            table.insert(out, string.format('\t\tcp %s %s; \\\n', from, to))
            table.insert(out, '\tfi\n')
        end
        if file.patch then
            table.insert(out, string.format(
                "\tpatch -p%s -d \"$(BUILD)/%s\" -i \"$(shell pwd)/%s/%s\"\n",
                file.patch, sourcename, source, e2lib.basename(file.location)))
        end
        -- write licences
        local destdir = string.format("%s/licences", directory)
        local fname = string.format("%s/%s.licences", destdir,
            e2lib.basename(file.location))
        local licence_list = file.licences:concat_sorted("\n") .. "\n"
        rc, re = e2lib.mkdir_recursive(destdir)
        if not rc then
            return false, e:cat(re)
        end
        rc, re = eio.file_write(fname, licence_list)
        if not rc then
            return false, e:cat(re)
        end
        e2lib.logf(4, "export file: %s done", file.location)
    end

    rc, re = eio.file_write(makefile, table.concat(out))
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- Check for working copy availability.
-- @param info The info table.
-- @param sourcename The name of the source (string).
-- @return Boolean, true on success.
-- @return An error object on failure.
function files.check_workingcopy(info, sourcename)
    return true, nil
end

--- Update the source.
-- @param info The info table.
-- @param sourcename The name of the source (string).
-- @return Boolean, true on success.
-- @return An error object on failure.
function files.update(info, sourcename)
    return true, nil
end

strict.lock(files)

-- vim:sw=4:sts=4:et:
