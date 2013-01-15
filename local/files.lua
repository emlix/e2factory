--- Files Plugin
-- @module local.files

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
local scm = require("scm")
local hash = require("hash")
local err = require("err")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local strict = require("strict")
local tools = require("tools")

plugin_descriptor = {
    description = "Files SCM Plugin",
    init = function (ctx) scm.register("files", files) return true end,
    exit = function (ctx) return true end,
}

--- validate source configuration, log errors to the debug log
-- @param info the info table
-- @param sourcename the source name
-- @return bool
function files.validate_source(info, sourcename)
    local rc1 = true   -- the return value
    local rc, e = scm.generic_source_validate(info, sourcename)
    if not rc then
        return false, e
    end
    e = err.new("in source %s:", sourcename)
    e:setcount(0)
    local src = info.sources[ sourcename ]
    if not src.file then
        e:append("%s: source has no `file' attribute", sourcename)
    end
    if src.file then
        for _,f in pairs(src.file) do
            if type(f) ~= "table" then
                e:append("%s: source has invalid file entry in `file' attribute",
                sourcename)
                break
            end
            -- catch deprecated configuration
            if f.name then
                e:append("source has file entry with `name' attribute")
            end
            if (not f.licences) and src.licences then
                f.licences = src.licences
            end
            if (not f.server) and src.server then
                f.server = src.server
            end
            if not f.licences then
                e:append("source has file entry without `licences' attribute")
            end
            for _,l in ipairs(f.licences) do
                if not info.licences[l] then
                    e:append("invalid licence assigned to file: %s", l)
                end
            end
            if not f.server then
                e:append("source has file entry without `server' attribute")
            end
            if f.server and (not info.cache:valid_server(f.server)) then
                e:append("invalid server: %s", f.server)
            end
            if not f.location then
                e:append("source has file entry without `location' attribute")
            end
            if f.server ~= info.root_server_name and not f.sha1 then
                e:append("source has file entry for remote file without `sha1` "..
                "attribute")
            end
            if not (f.unpack or f.copy or f.patch) then
                e:append("source has file entry without `unpack, copy or patch' " ..
                "attribute")
            end
            if f.checksum_file then
                e2lib.warnf("WDEPRECATED", "in source %s:", sourcename)
                e2lib.warnf("WDEPRECATED",
                " checksum_file attribute is deprecated and no longer used")
                f.checksum_file = nil
            end
        end
    end
    if e:getcount() > 0 then
        return false, e
    end
    return true, nil
end

--- cache files for a source
-- @param info the info structure
-- @param sourcename name of the source
-- @return bool
-- @return nil, an error string on error
function files.cache_source(info, sourcename)
    local rc, e
    rc, e = files.validate_source(info, sourcename)
    if not rc then
        return false, e
    end
    local s = info.sources[sourcename]
    -- cache all files for this source
    for i,f in pairs(s.file) do
        e2lib.log(4, string.format("files.cache_source: caching file %s:%s",
        f.server, f.location))
        local flags = { cache = true }
        if f.server ~= info.root_server_name then
            local rc, e = info.cache:cache_file(f.server, f.location, flags)
            if not rc then
                return false, e
            end
        else
            e2lib.log(4, string.format("not caching %s:%s (stored locally)",
            f.server, f.location))
        end
    end
    return true, nil
end

function files.fetch_source(info, sourcename)
    local rc, re
    local e = err.new("fetching source failed: %s", sourcename)
    rc, re = files.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    local rc, re = files.cache_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    return true, nil
end

function files.working_copy_available(info, sourcename)
    local rc, e
    rc, e = files.validate_source(info, sourcename)
    if not rc then
        return false, e
    end
    return false
end

function files.has_working_copy(info, sourcename)
    local rc, e
    rc, e = files.validate_source(info, sourcename)
    if not rc then
        return false, e
    end
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
    rc, re = files.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    local symlink = nil
    e2lib.log(4, string.format("prepare source: %s", sourcename))
    local s = info.sources[sourcename]
    for _,file in ipairs(info.sources[sourcename].file) do
        if file.sha1 then
            rc, re = e2tool.verify_hash(info, file.server, file.location, file.sha1)
            if not rc then
                return false, e:cat(re)
            end
        end
        if file.unpack then
            local cache_flags = { cache = true }
            local rc, re = info.cache:cache_file(file.server, file.location,
            cache_flags)
            if not rc then
                return false, e:cat(re)
            end
            local path, re = info.cache:file_path(file.server, file.location,
            cache_flags)
            if not path then
                return false, e:cat(re)
            end

            local rc, re = e2lib.howtounpack(path, path, buildpath)
            if not rc then
                return false, e:cat(re)
            end

            local tool, toolargv = rc, re
            rc, re = e2lib.call_tool_argv(tool, toolargv)
            if not rc then
                e:cat(err.new("unpacking archive '%s' failed", path))
                return false, e:cat(re)
            end

            if not symlink then
                symlink = buildpath .. "/" .. sourcename
                if file.unpack ~= sourcename then
                    if not e2util.symlink(file.unpack, symlink) then
                        return false, e:append("cannot create symlink: %s -> %s", symlink,
                        file.unpack)
                    end
                end
            end
        else
            if not symlink then
                symlink = buildpath .. "/" .. sourcename
                local rc, re = e2lib.mkdir(symlink, "-p")
                if not rc then
                    return false, e:cat(re)
                end
            end
            if file.patch then
                local cache_flags = { cache = true }
                local rc, re = info.cache:cache_file(file.server, file.location,
                cache_flags)
                if not rc then
                    return false, e:cat(re)
                end
                local path, re = info.cache:file_path(file.server,
                file.location, cache_flags)
                if not path then
                    return false, e:append(re)
                end
                local args = string.format("-p '%s' -d '%s' -i '%s'", file.patch,
                symlink, path)
                rc, re = e2lib.patch(args)
                if not rc then
                    e:append("applying patch: \"%s:%s\"", file.server, file.location)
                    return false, e:cat(re)
                end
            elseif file.copy then
                local destdir, destname
                destdir, destname = gen_dest_dir_name(buildpath, sourcename,
                    file.copy, file.location)

                rc, re = e2lib.mkdir(destdir, "-p")
                if not rc then
                    re = err.new("creating directory failed: %s", re)
                    return false, e:cat(re)
                end

                local rc, re = info.cache:fetch_file(file.server, file.location,
                    destdir, destname, {})
                if not rc then
                    return false, e:cat(re)
                end
            else
                e2lib.abort(string.format("missing destiny for file %s (%s)",
                file.location, file.server))
            end
        end
    end
    return true, nil
end

--- create a table of lines for display
-- @param info the info structure
-- @param sourcename string
-- @return a table, nil on error
-- @return an error string on failure
function files.display(info, sourcename)
    local rc, e
    rc, e = files.validate_source(info, sourcename)
    if not rc then
        return false, e
    end
    local src = info.sources[sourcename]
    local display = {}
    display[1] = string.format("type       = %s", src.type)
    local i = 2
    for _,f in pairs(src.file) do
        display[i] = string.format("file       = %s:%s", f.server, f.location)
        i = i + 1
    end
    for _,l in ipairs(src.licences) do
        display[i] = string.format("licence    = %s", l)
        i = i + 1
    end
    if src.sourceid then
        display[i] = string.format("sourceid   = %s", src.sourceid)
        i = i + 1
    end
    return display
end

--- calculate an id for a source
-- @param info
-- @param sourcename
-- @param sourceset
-- @return string: the source id, nil on error
-- @return an error string on error
function files.sourceid(info, sourcename, sourceset)
    local rc, re
    local e = err.new("error calculating sourceid for source: %s",
    sourcename)
    rc, re = files.validate_source(info, sourcename)
    if not rc then
        return false, re
    end
    local src = info.sources[sourcename]
    if src.sourceid then
        return true, nil, src.sourceid
    end
    -- sourceset is ignored for files sources
    local hc = hash.hash_start()
    hash.hash_line(hc, src.name)
    hash.hash_line(hc, src.type)
    hash.hash_line(hc, src._env:id())
    for _,l in ipairs(src.licences) do
        hash.hash_line(hc, l)
        local licenceid, re = e2tool.licenceid(info, l)
        if not licenceid then
            return false, re
        end
        hash.hash_line(hc, licenceid)
    end
    for _,f in ipairs(src.file) do
        local fileid, re = e2tool.fileid(info, f)
        if not fileid then
            return false, e:cat(re)
        end
        hash.hash_line(hc, fileid)
        hash.hash_line(hc, f.location)
        hash.hash_line(hc, f.server)
        hash.hash_line(hc, tostring(f.unpack))
        hash.hash_line(hc, tostring(f.patch))
        hash.hash_line(hc, tostring(f.copy))
    end
    e2lib.log(4, string.format("hash data for source %s\n%s", src.name,
    hc.data))
    src.sourceid = hash.hash_finish(hc)
    return true, nil, src.sourceid
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
    local rc, re
    local e = err.new("converting result failed")
    rc, re = files.validate_source(info, sourcename)
    if not rc then
        return false, e:cat(re)
    end
    local s = info.sources[sourcename]
    local makefile = "makefile" -- name of the makefile
    local source = "source"     -- directory to store source files in
    local fname = string.format("%s/%s", directory, makefile)
    local f, msg = io.open(fname, "w")
    if not f then
        return false, e:cat(msg)
    end

    f:write(string.format(".PHONY: place\n\nplace:\n"))
    for _,file in ipairs(s.file) do
        e2lib.log(4, string.format("export file: %s", file.location))
        local destdir = string.format("%s/%s", directory, source)
        local destname = nil
        e2lib.mkdir(destdir, "-p")
        local rc, re = info.cache:fetch_file(file.server,
        file.location, destdir, destname, {})
        if not rc then
            return false, e:cat(re)
        end
        if file.sha1 then
            local filename = e2lib.basename(file.location)
            local checksum_file = string.format("%s/%s.sha1",
            destdir, filename)
            rc, re = e2lib.write_file(checksum_file,
            string.format("%s  %s", file.sha1, filename))
            if not rc then
                return false, e:cat(re)
            end
            f:write(string.format(
            "\tcd source && sha1sum -c '%s'\n",
            e2lib.basename(checksum_file)))
        end
        if file.unpack then
            local physpath = e2lib.join(destdir, e2lib.basename(file.location))
            local virtpath = e2lib.join(source, e2lib.basename(file.location))
            local rc, re = e2lib.howtounpack(physpath, virtpath, "$(BUILD)")
            if not rc then
                e:cat("unable to generate unpack command")
                return false, e:cat(re)
            end

            local tool, toolargv = rc, re
            local toolname = tools.get_tool_name(tool)

            f:write(string.format("\t%s", toolname))
            for _,v in ipairs(toolargv) do
                f:write(string.format(" %s", e2lib.shquote(v)))
            end
            f:write("\n")

            if file.unpack ~= sourcename then
                f:write(string.format(
                "\tln -s %s $(BUILD)/%s\n", file.unpack,
                sourcename))
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
            f:write(string.format('\tif [ test -d %s ]; then \\\n', to))

            to = string.format('"$(BUILD)"%s',
                e2lib.shquote(e2lib.join(destdir, destname)))
            f:write(string.format('\t\tcp %s %s; \\\n', from, to))
            f:write(string.format('\telse \\\n'))
            --
            -- not a directory
            --
            destdir, destname = gen_dest_dir_name("/", sourcename, file.copy,
                file.location, "no")

            to = string.format('"$(BUILD)"%s', e2lib.shquote(destdir))
            f:write(string.format('\t\tmkdir -p %s; \\\n', to))

            to = string.format('"$(BUILD)"%s',
                e2lib.shquote(e2lib.join(destdir, destname)))
            f:write(string.format('\t\tcp %s %s; \\\n', from, to))
            f:write('\tfi\n')
        end
        if file.patch then
            f:write(string.format(
            "\tpatch -p%s -d \"$(BUILD)/%s\" "..
            "-i \"$(shell pwd)/%s/%s\"\n",
            file.patch, sourcename, source,
            e2lib.basename(file.location)))
        end
        -- write licences
        local destdir = string.format("%s/licences", directory)
        local fname = string.format("%s/%s.licences", destdir,
        e2lib.basename(file.location))
        local licence_list = table.concat(file.licences, "\n") .. "\n"
        rc, re = e2lib.mkdir(destdir, "-p")
        if not rc then
            return false, e:cat(re)
        end
        rc, re = e2lib.write_file(fname, licence_list)
        if not rc then
            return false, e:cat(re)
        end
        e2lib.log(4, string.format("export file: %s done",
        file.location))
    end
    f:close()
    return true, nil
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
