--- Licence config module.
-- @module local.licence

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

local licence = {}
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local hash = require("hash")
local strict = require("strict")

--- Licence base class.
-- @see generic.class
licence.licence = class("licence")

--- Dictionary of loaded licence objects, indexed by name.
licence.licences = {}
--- Vector of loaded licence objects, sorted by name.
licence.licences_sorted = {}

--- Create a new licence object.
-- @param name Licence name string.
-- @return May throw error(err) on invalid input.
function licence.licence:initialize(name)
    local ok, re = e2lib.vrfy_string_len(name, "licence name")
    if not ok then
        error(re)
    end
    self._name = name
    self._files = {}
    self._licenceid = false
end

--- Add a file to a licence.
-- @param location Path to licence file.
-- @param server Server name.
-- @param sha1 SHA1 checksum string. If file is local sha1 may be nil
-- @return May throw error(err) on invalid input.
function licence.licence:add_file(location, server, sha1)
    local t, ok, re

    ok, re = e2lib.vrfy_string_len(location, "licence location")
    if not ok then
        error(re)
    end

    ok, re = e2lib.vrfy_string_len(server, "licence server")
    if not ok then
        error(re)
    end

    if sha1 then
        ok, re = e2lib.vrfy_string_len(sha1, "licence sha1")
        if not ok then
            error(re)
        end
    end

    self._licenceid = false

    t = {
        location = location,
        server = server,
        sha1 = sha1,
    }
    table.insert(self._files, t)
end

--- Iterator that returns file tables in the order they were added.
function licence.licence:file_iter()
    local i = 0

    return function ()
        i = i + 1

        if self._files[i] then
            -- return a copy
            return {
                location = self._files[i].location,
                server = self._files[i].server,
                sha1 = self._files[i].sha1,
            }
        end

        return nil
    end
end

--- Get the licence name.
-- @return Licence name.
function licence.licence:get_name()
    return self._name
end

--- Calculate the LicenceID
-- @param info Info table.
-- @return LicenceID or false on error.
-- @return Error object on failure.
function licence.licence:licenceid(info)
    local rc, re, e, hc, fileid

    if self._licenceid then
        return self._licenceid
    end

    e = err.new("calculating licence id failed for licence: %s", self._name)

    hc = hash.hash_start()
    hash.hash_line(hc, self._name)

    for file in self:file_iter() do
        hash.hash_line(hc, file.server)
        hash.hash_line(hc, file.location)

        fileid, re = e2tool.fileid(info, file)
        if not fileid then
            return false, e:cat(re)
        end
        hash.hash_line(hc, fileid)
    end

    self._licenceid, re = hash.hash_finish(hc)
    if not self._licenceid then
        return false, e:cat(re)
    end

    return self._licenceid
end

--- Load project licence config, validate, and populate the licences,
-- licences_sorted tables with licence objects.
-- @param info Info table.
-- @return True on success, false on error
-- @return Error object on failure.
function licence.load_licence_config(info)
    local rc, re, e
    local path, ltable

    path = e2lib.join(info.root, "proj/licences")

    e2lib.logf(3, "loading licence config %q", path)
    e = err.new("loading licence config %q failed", path)

    ltable = {}
    local function assign(table)
        for k,v in pairs(table) do
            ltable[k] = v
        end
    end

    rc, re = e2lib.dofile2(path,
        { e2licence = assign, env = info.env, string = string })
    if not rc then
        return false, re
    end

    for k,v in pairs(ltable) do
        if type(k) ~= "string" then
            return false, e:append("key %q is not a string", tostring(k))
        end

        if type(v) ~= "table" then
            return false, e:append("licence %s is not a table", k)
        end
    end

    for name,l in pairs(ltable) do
        e2lib.logf(4, "in licence.load_licence_config, add %s, %s", tostring(name), tostring(l))

        rc, re = e2lib.vrfy_dict_exp_keys(l, "licence",
            { "server", "files" })
        if not rc then
            return false, e:cat(re)
        end

        if not l.server then
            return false, e:append("no server attribute in %s", name)
        elseif type(l.server) ~= "string" then
            return false, e:append("server attribute in %s not a string", name)
        end

        if not l.files then
            return false, e:append("no files attribute in %s", name)
        elseif type(l.files) ~= "table" then
            return false, e:append("files attribute in %s not a table", name)
        end

        for _,file in ipairs(l.files) do
            rc, re = e2lib.vrfy_dict_exp_keys(file, "file",
                { "server", "location", "sha1" })
            if not rc then
                return false, e:cat(re)
            end

            local inherit = {
                server = l.server,
            }

            local keys = {
                server = {
                    mandatory = true,
                    type = "string",
                    inherit = true,
                },
                location = {
                    mandatory = true,
                    type = "string",
                    inherit = false,
                },
                sha1 = {
                    mandatory = false,
                    type = "string",
                    inherit = false,
                },
            }


            rc, re = e2lib.vrfy_table_attributes(file, keys, inherit)
            if not rc then
                return false, e:cat(re)
            end
            if file.server ~= info.root_server_name and not file.sha1 then
                return false, e:append(
                    "file entry for remote file without sha1 attribute")
            end
        end


        licence.licences[name] = licence.licence:new(name)

        for _,file in ipairs(l.files) do
            licence.licences[name]:add_file(
                file.location, file.server, file.sha1)
        end
    end

    for _,l in pairs(licence.licences) do
        table.insert(licence.licences_sorted, l)
    end

    local function s(a, b)
        return a:get_name() < b:get_name()
    end
    table.sort(licence.licences_sorted, s)

    return true
end

return strict.lock(licence)

-- vim:sw=4:sts=4:et:
