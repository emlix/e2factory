--- e2-ls-project command
-- @module local.e2-ls-project

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

-- ls-project - show project information -*- Lua -*-

local e2lib = require("e2lib")
local e2tool = require("e2tool")
local err = require("err")
local e2option = require("e2option")
local scm = require("scm")
local policy = require("policy")

e2lib.init()
local info, re = e2tool.local_init(nil, "ls-project")
if not info then
    e2lib.abort(re)
end

policy.register_commandline_options()
e2option.flag("dot", "generate dot(1) graph")
e2option.flag("dot-sources", "generate dot(1) graph with sources included")
e2option.flag("swap", "swap arrow directions in dot graph")
e2option.flag("all", "show unused results and sources, too")

local opts, arguments = e2option.parse(arg)

info, re = e2tool.collect_project_info(info)
if not info then
    e2lib.abort(re)
end
local rc, re = e2tool.check_project_info(info)
if not rc then
    e2lib.abort(re)
end

local results = {}
if opts.all then
    for r, _ in pairs(info.results) do
        table.insert(results, r)
    end
elseif #arguments > 0 then
    for _, r in ipairs(arguments) do
        if info.results[r] then
            table.insert(results, r)
        else
            e2lib.abort(err.new("not a result: %s", r))
        end
    end
end
if #results > 0 then
    results, re = e2tool.dlist_recursive(info, results)
    if not results then
        e2lib.abort(re)
    end
else
    results, re = e2tool.dsort(info)
    if not results then
        e2lib.abort(re)
    end
end
table.sort(results)

local sources = {}
if opts.all then
    for s, _ in pairs(info.sources) do
        table.insert(sources, s)
    end
else
    local yet = {}
    for _, r in pairs(results) do
        for _, s in ipairs(info.results[r].sources) do
            if not yet[s] then
                table.insert(sources, s)
                yet[s] = true
            end
        end
    end
end
table.sort(sources)

local function pempty(s1, s2, s3)
    print(string.format("   %s  %s  %s", s1, s2, s3))
end
local function p0(s1, s2, v)
    print(string.format("%s", v))
end
local function p1(s1, s2, v)
    print(string.format("   o--%s", v))
end
local function p2(s1, s2, v)
    print(string.format("   %s  o--%s", s1, v))
end
local function p3(s1, s2, k, v)
    if v then
        -- remove leading spaces, that allows easier string
        -- append code below, where collecting multiple items
        while v:sub(1,1) == " " do

            v = v:sub(2)
        end
        print(string.format("   %s  %s  o--%-10s = %s", s1, s2, k, v))
    else
        print(string.format("   %s  %s  o--%s", s1, s2, k))
    end
end

local function p3t(s1, s2, k, t)
    local col = tonumber(e2lib.globals.osenv["COLUMNS"])
    local header1 = string.format("   %s  %s  o--%-10s =", s1, s2, k)
    local header2 = string.format("   %s  %s     %-10s  ", s1, s2, "")
    local header = header1
    local l = nil
    local i = 0
    for _,v in ipairs(t) do
        i = i + 1
        if l then
            if (l:len() + v:len() + 1) > col then
                print(l)
                l = nil
            end
        end
        if not l then
            l = string.format("%s %s", header, v)
        else
            l = string.format("%s %s", l, v)
        end
        header = header2
    end
    if l then
        print(l)
    end
end

if opts.dot or opts["dot-sources"] then
    local arrow = "->"
    print("digraph \"" .. info.name .. "\" {")
    for _, r in pairs(results) do
        local res = info.results[r]
        local deps = e2tool.dlist(info, r)
        if #deps > 0 then
            for _, dep in pairs(deps) do
                if opts.swap then
                    print(string.format("  \"%s\" %s \"%s\"", dep, arrow, r))
                else
                    print(string.format("  \"%s\" %s \"%s\"", r, arrow, dep))
                end
            end
        else
            print(string.format("  \"%s\"", r))
        end
        if opts["dot-sources"] then
            for _, src in ipairs(res.sources) do
                if opts.swap then
                    print(string.format("  \"%s-src\" %s \"%s\"", src, arrow, r))
                else
                    print(string.format("  \"%s\" %s \"%s-src\"", r, arrow, src))
                end
            end
        end
    end
    if opts["dot-sources"] then
        for _, s in pairs(sources) do
            print(string.format("  \"%s-src\" [label=\"%s\", shape=box]", s, s))
        end
    end
    print("}")
    e2lib.finish()
end

--------------- project name
local s1 = "|"
local s2 = "|"
p0(s1, s2, info.name)

--------------- servers
local s1 = "|"
local s2 = "|"
p1(s1, s2, "servers")
local servers_sorted = info.cache:servers()
for i = 1, #servers_sorted, 1 do
    local ce = info.cache:ce_by_server(servers_sorted[i])
    if i < #servers_sorted then
        s2 = "|"
    else
        s2 = " "
    end
    p2(s1, s2, ce.server)
    p3(s1, s2, "url", ce.remote_url)
    local flags = {}
    for k,v in pairs(ce.flags) do
        table.insert(flags, k)
    end
    table.sort(flags)
    for _,k in ipairs(flags) do
        p3(s1, s2, k, tostring(ce.flags[k]))
    end
end
print("   |")

--------------------- sources
local s1 = "|"
local s2 = " "
p1(s1, s2, "src")
local len = #sources
for _, s in pairs(sources) do
    local src = info.sources[s]
    len = len - 1
    if len == 0 then
        s2 = " "
    else
        s2 = "|"
    end
    p2(s1, s2, src.name)
    local t, re = scm.display(info, src.name)
    if not t then
        e2lib.abort(re)
    end
    for _,line in pairs(t) do
        p3(s1, s2, line)
    end
end

--------------------- results
local s1 = "|"
local s2 = " "
local s3 = " "
pempty(s1, s2, s3)
s2 = " "
p1(s1, s2, "res")
local len = #results
for _, r in pairs(results) do
    local res = info.results[r]
    p2(s1, s2, r)
    len = len - 1
    if len == 0 then
        s2 = " "
    else
        s2 = "|"
    end
    p3t(s1, s2, "sources", res.sources)
    p3t(s1, s2, "depends", res.depends)
    if res.collect_project then
        p3(s1, s2, "collect_project", "enabled")
        p3(s1, s2, "collect_project_default_result",
        res.collect_project_default_result)
    end
end

--------------------- licences
local s1 = "|"
local s2 = " "
local s3 = " "
pempty(s1, s2, s3)
s2 = "|"
p1(s1, s2, "licences")
local llen = #info.licences_sorted
for _,l in pairs(info.licences_sorted) do
    local lic = info.licences[l]
    llen = llen - 1
    if llen == 0 then
        s2 = " "
    end
    p2(s1, s2, l)
    for _,f in ipairs(lic.files) do
        p3(s1, s2, "file", string.format("%s:%s", f.server, f.location))
    end
end

--------------------- chroot
local s1 = "|"
local s2 = " "
local s3 = " "
pempty(s1, s2, s3)
p1(s1, s2, "chroot groups")
local s1 = " "
local s2 = "|"
local len = #info.chroot.groups_sorted
for _,g in ipairs(info.chroot.groups_sorted) do
    local grp = info.chroot.groups_byname[g]
    len = len - 1
    if len == 0 then
        s2 = " "
    end
    p2(s1, s2, grp.name, grp.name)
    for _,f in ipairs(grp.files) do
        p3(s1, s2, "file", string.format("%s:%s", f.server, f.location))
    end
    if grp.groupid then
        p3(s1, s2, "groupid", grp.groupid)
    end
end

e2lib.finish()

-- vim:sw=4:sts=4:et:
