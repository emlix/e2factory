--- e2-help command. This tool shows the locally available help
-- matching the project version.
--
-- @module local.e2-help

--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2013 Tobias Ulmer <tu@emlix.com>, emlix GmbH

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
local tools = require("tools")

--- Documentation array, contains doc entries in arbitrary order.
-- @see doc
-- @table documentation

--- Doc table describing a specific document.
-- @field doctype Type of a document (pdf, man, ...), see doctype table
--                (constant number).
-- @field section Manpage section (string). Only if the document is a manpage.
-- @field path Directory path (absolute) to the document (string).
-- @field filename File name (without path) of the document (string).
-- @field displayname Name of the document as it should be displayed (string).
-- @table doc

--- Document type constants.
local doctype = {
    PDF = 1, -- PDF document.
    MAN = 2, -- Man page.
    TXT = 3, -- Text file.
}

--- List (print) available man pages in the specified section.
-- @param documentation Documentation array containing doc tables (table).
-- @param header Print this string before anything else.
-- @param section Man page/dir section (string, numbers converted to string).
-- @return True on success, false on error.
-- @return Error object on failure.
local function list_manpage_section(documentation, header, section)
    section = tostring(section)

    local sorted = {}
    for _,doc in ipairs(documentation) do
        if doc.section == section then
            table.insert(sorted, doc.displayname)
        end
    end
    table.sort(sorted)

    print(header)
    for _,displayname in ipairs(sorted) do
            print(string.format("  %s", displayname))
    end
    print()
    return true
end

--- List (print) all available documentation. Calls subfunctions that know how
-- to handle various document formats and locations.
-- @param documentation Documentation array containing doc tables (table).
-- @return True on success, false on error.
-- @return Error object on failure.
local function list_documentation(documentation)
    local rc, re, e

    local header = "Global and local e2factory tools (section 1):"
    rc, re = list_manpage_section(documentation, header, 1)
    if not rc then
        return false, re
    end

    header = "e2factory configuration files (section 5):"
    rc, re = list_manpage_section(documentation, header, 5)
    if not rc then
        return false, re
    end

    return true
end

--- Discovers and adds local man pages in a specified section relative to
-- projectdir.
-- @param documentation Documentation array to be filled
--                      with doc tables (table).
-- @param projectdir Path to the root of the project (string).
-- @param section Man page/dir section (string, numbers converted to string).
-- @return True on success, false on error.
-- @return Error object on failure.
local function discover_manpages(documentation, projectdir, section)
    local rc, re, e
    section = tostring(section)

    local mancomp = string.format("man%s", section)
    local man_re_ext = string.format("%%.%s$", section)
    local man_re_disp = string.format("^(.+)%%.%s$", section)
    local mandir = e2lib.join(projectdir, ".e2", "doc", "man", mancomp)

    for f in e2lib.directory(mandir, false, true) do
        if f:match(man_re_ext) then
            local doc = {}

            doc.doctype = doctype.MAN
            doc.section = section
            doc.path = mandir
            doc.filename = f
            doc.displayname = f:match(man_re_disp)

            table.insert(documentation, doc)
        end
    end

    return true
end

--- Discovers documentation in the local project.
-- @param documentation Documentation array to be filled
--                      with doc tables (table).
-- @return True on success, false on error.
-- @return Error object on failure.
local function discover_documentation(documentation)
    local rc, re, e

    e = err.new("while collecting available documentation")

    local projectdir, re = e2lib.locate_project_root()
    if not projectdir then
        return false, e:cat(re)
    end

    rc, re = discover_manpages(documentation, projectdir, 1)
    if not rc then
        return false, e:cat(re)
    end

    rc, re = discover_manpages(documentation, projectdir, 5)
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- Display a man page.
-- @param doc Doc table of the document to be displayed.
-- @return True on success, false on error.
-- @return Error object on failure.
local function display_man_page(doc)
    local rc, re, e
    local cmd = {}

    local viewer = tools.get_tool("man")
    if not viewer then
        return false, err.new("no man page viewer is available")
    end
    table.insert(cmd, e2lib.shquote(viewer))

    local viewerflags = tools.get_tool_flags("man")
    if viewerflags and #viewerflags > 0 then
        table.insert(cmd, table.concat(viewerflags, " "))
    end

    table.insert(cmd, e2lib.shquote(e2lib.join(doc.path, doc.filename)))

    rc = os.execute(table.concat(cmd, ' '))
    rc = rc / 256
    if rc ~= 0 then
        return false,
            err.new("man page viewer terminated with exit code %d", rc)
    end

    return true
end

--- Find matching document and display it.
-- @param documentation Documentation array containing doc tables (table).
-- @param doc_name Document name, supplied by user (string).
-- @return True on success, false on error.
-- @return Error object on failure.
local function display_doc(documentation, doc_name)
    local rc, re, e

    local found = 0
    local founddoc
    for _,doc in ipairs(documentation) do
        if doc.displayname == doc_name then
            found = found + 1;
            founddoc = doc
        end
    end

    if found == 0 then
        return false, err.new("No document matched '%s'", doc_name)
    elseif found == 1 then
        if founddoc.doctype == doctype.MAN then
            display_man_page(founddoc)
        else
            return false, err.new("unhandled doctype: %d", founddoc.doctype)
        end
    else
        return false, err.new("More than one document matches '%s'", doc_name)
    end

    return true
end

--- List available help and display them on request. e2-help entry point.
-- @param arg Global argv table.
-- @return True on success, false on error.
-- @return Error object on failure.
local function e2_help(arg)
    local rc, re, e
    rc, re = e2lib.init()
    if not rc then
        return false, re
    end

    local info, re = e2tool.local_init(nil, "help")
    if not info then
        return false, re;
    end

    local opts, arguments = e2option.parse(arg)
    if not opts then
        return false, arguments
    end

    info, re = e2tool.collect_project_info(info, true)
    if not info then
        return false, re
    end

    local documentation = {}
    if #arguments == 0 then
        rc, re = discover_documentation(documentation)
        if not rc then
            return false, re
        end

        rc, re = list_documentation(documentation)
        if not rc then
            return false, re
        end
    elseif #arguments == 1 then
        rc, re = discover_documentation(documentation)
        if not rc then
            return false, re
        end

        rc, re = display_doc(documentation, arguments[1])
        if not rc then
            return false, re
        end
    else
        return false, err.new("Too many arguments")
    end

    return true
end

local rc, re = e2_help(arg)
if not rc then
    e2lib.abort(re)
end

e2lib.finish(0)

-- vim:sw=4:sts=4:et:
