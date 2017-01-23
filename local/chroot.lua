--- Chroot config module.
-- @module local.chroot

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

local chroot = {}
package.loaded["chroot"] = chroot
local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local hash = require("hash")
local projenv = require("projenv")
local strict = require("strict")

--- On disk chroot configuration.
-- @table e2chroot
-- @field default_groups Default group name vector.
-- @field groups Vector of group tables.
-- @see group

--- On disk chroot group config.
-- @table group
-- @field name Group name
-- @field server Server name
-- @field files Vector of file tables.
-- @see file

--- Raw table for file_class.
-- @table file
-- @field server Server name.
-- @field location File location.
-- @field sha1 SHA1 sum, optional
-- @field sha256 SHA256 sum, optional

--- Default chroot group names applied to all results. Locked.
chroot.groups_default = {}

--- Chroot group objects indexed by their name.
chroot.groups_byname = {}

--- Vector of sorted chroot group names. Locked.
chroot.groups_sorted = {}

--- Chroot class.
-- @type chroot
chroot.chroot = class("chroot")

--- Chroot group object constructor.
-- @param name Chroot group name.
-- @return May throw error(err).
function chroot.chroot:initialize(name)
    local ok, re = e2lib.vrfy_string_len(name, "chroot group name")
    if not ok then
        error(re)
    end
    self._name = name
    self._files = {}
    self._chrootgroupid = false
end

--- Get the chroot group name.
-- @return Chroot group name.
function chroot.chroot:get_name()
    return self._name
end

--- Add a file to a chroot group.
-- @param file file_class object to add
-- @see e2tool.file_class
function chroot.chroot:add_file(file)
    assertIsTable(file)
    assert(file:isInstanceOf(e2tool.file_class))
    self._chrootgroupid = false
    table.insert(self._files, file)
end

--- Iterator that returns file tables in the order they were added.
-- @return Iterator function
-- @see file
function chroot.chroot:file_iter()
    local i = 0

    return function ()
        i = i + 1

        if self._files[i] then
            -- return a copy
            return self._files[i]:instance_copy()
        end

        return nil
    end
end

--- Calculate chroot group id.
-- @param info Info table.
-- @return Chroot group ID or false on error.
-- @return Error object on failure.
function chroot.chroot:chrootgroupid(info)
    local rc, re, e, hc

    if self._chrootgroupid then
        return self._chrootgroupid
    end

    e = err.new("calculating chroot group id failed for group %s",
        self._name)

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)

    local fileid
    for file in self:file_iter() do
        fileid, re = file:fileid()
        if not fileid then
            return false, e:cat(re)
        end
        hash.hash_append(hc, fileid)
    end

    self._chrootgroupid = hash.hash_finish(hc)
    return self._chrootgroupid
end
--- @section end

--- Load and validate chroot configuration. Populates chroot.groups_byname,
-- chroot.groups_sorted and chroot.groups_default.
-- @param info Info table.
-- @return True on success, false on error.
-- @return Error object on failure
function chroot.load_chroot_config(info)
    local rc, re, e
    local t, path, cgroup

    path = e2lib.join(e2tool.root(), "proj/chroot")
    e = err.new("loading chroot config %q failed", path)

    t = nil
    local g = {
        e2chroot = function (data) t = data end,
        env = projenv.safe_global_res_env_table(),
        string = e2lib.safe_string_table(),
    }

    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, re
    end

    if type(t) ~= "table" then
        return false, e:append("empty or invalid chroot configuration")
    end

    rc, re = e2lib.vrfy_dict_exp_keys(t, "chroot configuration",
        { "groups", "default_groups" })
    if not rc then
        return false, e:cat(re)
    end

    if type(t.groups) ~= "table" then
        return false, e:append("chroot groups configuration is not a table")
    end

    rc, re = e2lib.vrfy_vector(t.groups, "chroot groups")
    if not rc then
        return false, e:cat(re)
    end

    if type(t.default_groups) ~= "table" then
        return false, e:append("chroot.default_groups is not a table")
    end

    rc, re = e2lib.vrfy_listofstrings(t.default_groups,
        "chroot default_groups", true, false)
    if not rc then
        return false, e:cat(re)
    end

    for _,grp in ipairs(t.groups) do
        if grp.group then
            e:append("in group: %s", grp.group)
            e:append(" `group' attribute is deprecated. Replace by `name'")
            return false, e
        end

        if not grp.name then
            return false, e:append("`name' attribute is missing in a group")
        end

        if chroot.groups_byname[grp.name] then
            return false, e:append("duplicate chroot group name: %s", grp.name)
        end

        rc, re = e2lib.vrfy_dict_exp_keys(grp,
            string.format("chroot group %q", grp.name),
            { "name", "server", "files" })
        if not rc then
            return false, e:cat(re)
        end

        if not grp.server then
            e:append("in group: %s", grp.name)
            e:append(" `server' attribute missing")
            return false, e
        end
        if not cache.valid_server(cache.cache(), grp.server) then
            e:append("in group: %s", grp.name)
            e:append(" no such server: %s", grp.server)
            return false, e
        end

        if not grp.files or #grp.files == 0 then
            e:append("in group: %s", grp.name)
            e:append(" list of files is empty")
            return false, e
        end

        rc, re = e2lib.vrfy_vector(grp.files,
                string.format("group: %s", grp.name))
        if not rc then
            return false, e:cat(re)
        end

        cgroup = chroot.chroot:new(grp.name)

        for n, f in ipairs(grp.files) do
            local ferr, file

            ferr = err.new("error in file entry %d of chroot group '%s'", n,
                tostring(grp.name))

            file = e2tool.file_class:new()

            if f.server == nil then
                f.server = grp.server
            end

            rc, re = e2lib.vrfy_dict_exp_keys(f,
                string.format("file entry of group: %s", grp.name),
                {
                    "server",
                    "location",
                    "sha1",
                    "sha256",
                })
            if not rc then
                return false, e:cat(re)
            end

            rc, re = file:validate_set_servloc(f.server, f.location)
            if not rc then
                e:cat(ferr)
                return false, e:cat(re)
            end

            rc, re = file:validate_set_checksums(f.sha1, f.sha256)
            if not rc then
                e:cat(ferr)
                return false, e:cat(re)
            end

            cgroup:add_file(file)
        end

        chroot.groups_byname[cgroup:get_name()] = cgroup
        table.insert(chroot.groups_sorted, cgroup:get_name())
    end
    table.sort(chroot.groups_sorted)
    strict.lock(chroot.groups_sorted)

    for _,g in ipairs(t.default_groups) do
        if not chroot.groups_byname[g] then
            return false,
                e:append("unknown group in default groups list: %q", g)
        end
        table.insert(chroot.groups_default, g)
    end
    table.sort(chroot.groups_default)
    strict.lock(chroot.groups_default)

    --- XXX: remove, there is no reason to enforce a default group
    if #chroot.groups_default == 0 then
        return false,
            e:append("`default_groups' attribute is missing or empty list")
    end

    return true
end

return strict.lock(chroot)

-- vim:sw=4:sts=4:et:
