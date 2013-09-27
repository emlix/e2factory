--- e2-cf helps creating and editing sources and results.
-- @module local.e2-cf

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

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local e2option = require("e2option")

local commands = {}

--- Start external editor.
-- @return True on success, false on error.
-- @return Error object on failure.
local function editor(file)
    local e = e2lib.globals.osenv["EDITOR"]
    e2lib.shquote(e)
    file = e2lib.shquote(file)

    local cmd = string.format("%s %s", e, file)


    local rc
    rc = os.execute(cmd)
    rc = rc / 256
    if rc ~= 0 then
        return false, err.new("Editor finished with exit status %d", rc)
    end

    return true
end

--- Find whether upstream config files hide this source/result.
local function shadow_config_up(src_res, pathname)
    local cf, cfdir
    if src_res == "src" then
        cf = e2tool.sourceconfig(pathname)
        cfdir = e2tool.sourcedir(pathname)
    elseif src_res == "res" then
        cf = e2tool.resultconfig(pathname)
        cfdir = e2tool.resultdir(pathname)
    else
        return false, err.new("unexpected value in src_res")
    end

    if pathname == "." then
        return true
    end

    if e2lib.isfile(cf) then
        local thing = "source"
        if src_res == "res" then
            thing = "result"
        end

        return false,
            err.new("config in %s would shadow the new %s", cfdir, thing)
    end

    return shadow_config_up(src_res, e2lib.dirname(pathname))
end

--- Find whether downstream sources/results would be hidden by creating
-- config here.
local function shadow_config_down(src_res, pathname)
    local cf, cfdir
    if src_res == "src" then
        cf = e2tool.sourceconfig(pathname)
        cfdir = e2tool.sourcedir(pathname)
    elseif src_res == "res" then
        cf = e2tool.resultconfig(pathname)
        cfdir = e2tool.resultdir(pathname)
    else
        return false, err.new("unexpected value in src_res")
    end

    if e2lib.isfile(cf) then
        return false, err.new("config in %s would be shadowed", cfdir)
    end

    local re
    for f, re in e2lib.directory(cfdir, false, true) do
        if not f then
            return false, re
        end

        if e2lib.isdir(e2lib.join(cfdir, f)) then
            return shadow_config_down(src_res, e2lib.join(pathname, f))
        end
    end

    return true
end

--- Create new source.
local function newsource(info, ...)
    local rc, re
    local e = err.new("creating a new source failed")
    local t = ...
    local name = t[2]
    local scm = t[3]

    if not name then
        e:append("missing parameter: name")
    end
    if not scm then
        e:append("missing parameter: scm")
    end
    if e:getcount() > 1 then
        return false, e
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(name)
    if not rc then
        return false, e:cat(re)
    end

    local cftemplate =
        e2lib.join(info.local_template_path, string.format("source.%s", scm))
    if not e2lib.isfile(cftemplate) then
        return false, e:append("no template for '%s' available", scm)
    end

    local pathname = e2tool.src_res_name_to_path(name)
    local cf = e2tool.sourceconfig(pathname)
    local cfdir = e2tool.sourcedir(pathname)

    if e2lib.isfile(cf) then
        return false, e:append("refusing to overwrite config in %s", cfdir)
    end

    rc, re = shadow_config_up("src", pathname)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = shadow_config_down("src", pathname)
    if not rc then
        return false, e:cat(re)
    end

    local rc, re = e2lib.mkdir_recursive(cfdir)
    if not rc then
        return false, e:cat(re)
    end

    local rc, re = e2lib.cp(cftemplate, cf)
    if not rc then
        return false, e:cat(re)
    end

    local rc, re = commands.editsource(info, ...)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- Edit source.
local function editsource(info, ...)
    local rc, re
    local e = err.new("editsource")
    local t = ...
    local name = t[2]
    if not name then
        return false, e:append("missing parameter: name")
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(name)
    if not rc then
        return false, e:cat(re)
    end

    local pathname = e2tool.src_res_name_to_path(name)
    local cf = e2tool.sourceconfig(pathname)
    return editor(cf)
end

--- Create new result.
local function newresult(info, ...)
    local rc, re
    local e = err.new("making new result failed")
    local t = ...
    local name = t[2]
    if not name then
        return false, e:append("missing parameter: name")
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(name)
    if not rc then
        return false, e:cat(re)
    end

    local pathname = e2tool.src_res_name_to_path(name)
    local cfdir = e2tool.resultdir(pathname)
    local cf = e2tool.resultconfig(pathname)
    local bs = e2tool.resultbuildscript(pathname)

    local cftemplate = e2lib.join(info.local_template_path, "result")
    local bstemplate = e2lib.join(info.local_template_path, "build-script")
    if not e2lib.isfile(cftemplate) then
        return false, e:append("config template %s not available", cftemplate)
    end

    if not e2lib.isfile(bstemplate) then
        return false, e:append("build-script template % not available",
            bstemplate)
    end

    if e2lib.isfile(cf) then
        return false, e:append("refusing to overwrite config in %s", cfdir)
    end

    if e2lib.isfile(bs) then
        return false,
            e:append("refusing to overwrite build-script in %s", cfdir)
    end

    rc, re = shadow_config_up("res", pathname)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = shadow_config_down("res", pathname)
    if not rc then
        return false, e:cat(re)
    end

    local rc, re = e2lib.mkdir_recursive(cfdir)
    if not rc then
        return false, e:cat(re)
    end

    local rc, re = e2lib.cp(cftemplate, cf)
    if not rc then
        return false, e:cat(re)
    end
    local rc, re = e2lib.cp(bstemplate, bs)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = commands.editresult(info, ...)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = commands.editbuildscript(info, ...)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

--- Edit result config.
-- @return True on success, false on failure.
-- @return Error object on failure.
local function editresult(info, ...)
    local rc, re
    local e = err.new("editresult")
    local t = ...
    local name = t[2]
    if not name then
        return false, e:append("missing parameter: name")
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(name)
    if not rc then
        return false, e:cat(re)
    end

    local pathname = e2tool.src_res_name_to_path(name)
    local cf = e2tool.resultconfig(pathname)
    return editor(cf)
end

--- Edit build-script.
local function editbuildscript(info, ...)
    local rc, re
    local e = err.new("editbuildscript")
    local t = ...
    local name = t[2]
    if not name then
        return false, e:append("missing parameter: name")
    end

    rc, re = e2tool.verify_src_res_name_valid_chars(name)
    if not rc then
        return false, e:cat(re)
    end

    local pathname = e2tool.src_res_name_to_path(name)
    local cf = e2tool.resultbuildscript(pathname)
    return editor(cf)
end

local function e2_cf(arg)
    local rc, re = e2lib.init()
    if not rc then
        return false, re
    end

    local info, re = e2tool.local_init(nil, "cf")
    if not info then
        return false, re
    end

    local opts, arguments = e2option.parse(arg)
    if not opts then
        return false, arguments
    end

    -- initialize some basics in the info structure without actually loading
    -- the project configuration.
    info, re = e2tool.collect_project_info(info, true)
    if not info then
        return false, re
    end

    local rc, re = e2lib.chdir(info.root)
    if not rc then
        return false, re
    end

    commands.editbuildscript = editbuildscript
    commands.editresult = editresult
    commands.newresult = newresult
    commands.newsource = newsource
    commands.editsource = editsource
    commands.ebuildscript = editbuildscript
    commands.eresult = editresult
    commands.nresult = newresult
    commands.nsource = newsource
    commands.esource = editsource

    if #arguments < 1 then
        e2option.usage(1)
    end

    local match = {}
    local cmd = arguments[1]
    for c,f in pairs(commands) do
        if c:match(string.format("^%s", cmd)) then
            table.insert(match, c)
        end
    end

    if #match == 0 then
        return false, err.new("unknown command")
    elseif #match == 1 then
        local a = {}
        for _,o in ipairs(arguments) do
            table.insert(a, o)
        end
        local f = commands[match[1]]
        rc, re = f(info, a)
        if not rc then
            return false, re
        end
    else
        return false, err.new("Ambiguous command: \"%s\" matches: %s",
            cmd, table.concat(match, ', '))
    end

    return true
end

local rc, re = e2_cf(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
