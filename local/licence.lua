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
package.loaded["licence"] = licence

local cache = require("cache")
local class = require("class")
local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local hash = require("hash")
local projenv = require("projenv")
local strict = require("strict")

--- Dictionary of loaded licence objects, indexed by name.
licence.licences = {}

--- Vector of loaded licence objects, sorted by name.
licence.licences_sorted = {}

--- Licence base class.
-- @type licence
licence.licence = class("licence")

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
-- @param file add file_class object
-- @return May throw error(err) on invalid input.
-- @see e2tool.file_class
function licence.licence:add_file(file)
    assertIsTable(file)
    assert(file:isInstanceOf(e2tool.file_class))
    self._licenceid = false
    table.insert(self._files, file)
end

--- Iterator that returns file_class objects in the order they were added.
function licence.licence:file_iter()
    local i = 0

    return function ()
        i = i + 1

        if self._files[i] then
            return self._files[i]:instance_copy()
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
-- @return LicenceID or false on error.
-- @return Error object on failure.
function licence.licence:licenceid()
    local rc, re, e, hc, fileid

    if self._licenceid then
        return self._licenceid
    end

    e = err.new("calculating licence id failed for licence: %s", self._name)

    hc = hash.hash_start()
    hash.hash_append(hc, self._name)

    for file in self:file_iter() do
        fileid, re = file:fileid()
        if not fileid then
            return false, e:cat(re)
        end
        hash.hash_append(hc, fileid)
    end

    self._licenceid, re = hash.hash_finish(hc)
    if not self._licenceid then
        return false, e:cat(re)
    end

    return self._licenceid
end
--- @section end

--- Load project licence config, validate, and populate the licences,
-- licences_sorted tables with licence objects.
-- @return True on success, false on error
-- @return Error object on failure.
function licence.load_licence_config()
    local rc, re, e
    local path, ltable

    path = e2lib.join(e2tool.root(), "proj/licences")

    e2lib.logf(3, "loading licence config %q", path)
    e = err.new("loading licence config %q failed", path)

    ltable = nil
    local g = {
        e2licence = function(data) ltable = data end,
        env = projenv.safe_global_res_env_table(),
        string = e2lib.safe_string_table(),
    }

    rc, re = e2lib.dofile2(path, g)
    if not rc then
        return false, re
    end

    if type(ltable) ~= "table" then
        return false, e:append("empty or invalid licence configuration")
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
        local lerr = err.new("error in licence %q", name)

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

        licence.licences[name] = licence.licence:new(name)

        for _,f in ipairs(l.files) do
            local file

            rc, re = e2lib.vrfy_dict_exp_keys(f, "file",
                {
                    "server",
                    "location",
                    "sha1",
                    "sha256",
                })
            if not rc then
                e:cat(lerr)
                return false, e:cat(re)
            end

            if f.server == nil then
                f.server = l.server
            end

            file = e2tool.file_class:new()

            rc, re = file:validate_set_servloc(f.server, f.location)
            if not rc then
                e:cat(lerr)
                return false, e:cat(re)
            end

            rc, re = file:validate_set_checksums(f.sha1, f.sha256)
            if not rc then
                e:cat(lerr)
                return false, e:cat(re)
            end

            licence.licences[name]:add_file(file)
        end



        for _,f in ipairs(l.files) do
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
