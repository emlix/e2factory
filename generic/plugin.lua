--- Plugin Loader.
-- @module generic.plugin

--[[
   e2factory, the emlix embedded build system

   Copyright (C) 2012 Tobias Ulmer <tu@emlix.com>, emlix GmbH
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

local plugin = {}
local err = require("err")
local e2lib = require("e2lib")
local strict = require("strict")

--- plugin descriptor
-- @class table
-- @name plugin descriptor
-- @field description string: human readable plugin description string,
--                            including unique plugin version information
-- @field init function: initialization function
-- @field exit function: deinitialization function
-- @field file string: plugin file name (inserted by plugin loader)
-- @field ctx table: plugin context (inserted by plugin loader)

--- plugin context
-- @class table
-- @name plugin context
-- @field plugin table: plugin descriptor
-- @field info table: info table (local tools only)

--- plugin init function
-- @class function
-- @name init
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure

--- plugin exit function
-- @class function
-- @name init
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure

-- list of plugin descriptors
local plugins = {}

--[[ example plugin descriptor:
-- plugin = {
--   description = "...",
--   init = init,
--   exit = exit,
--   file = nil, -- automatically inserted by plugin loader
--   ctx = nil,  -- automatically inserted by plugin loader
-- }
--]]

--- load a plugin
-- @param dir string: plugin directory
-- @param p string: plugin filename
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure
local function load_plugin(dir, p, ctx)
    local e = err.new("loading plugin failed: %s", p)
    local plugin_file = string.format("%s/%s", dir, p)

    strict.declare(_G, {"plugin_descriptor"})

    local chunk, msg = loadfile(plugin_file)
    if not chunk then
        return false, e:append("%s", msg)
    end
    chunk()
    if not plugin_descriptor then
        strict.undeclare(_G, {"plugin_descriptor"})
        return false, e:append("no plugin descriptor in plugin: %s",
        plugin_file)
    end
    local pd = plugin_descriptor

    strict.undeclare(_G, {"plugin_descriptor"})

    if type(pd.description) ~= "string" then
        e:append("description missing in plugin descriptor")
    end
    if type(pd.init) ~= "function" then
        e:append("init function missing in descriptor")
    end
    if type(pd.exit) ~= "function" then
        e:append("exit function missing in descriptor")
    end

    if pd.depends then
        for _,dep in ipairs(pd.depends) do
            if type(dep) ~= "string" then
                e:append("a dependency of plugin %s is not a string", p)
            end

            if not e2util.exists(string.format("%s/%s", dir, dep)) then
                e:append("dependency %s of plugin %s is not installed", dep, p)
            end
        end
    else
        pd.depends = {}
    end

    if e:getcount() > 1 then
        return false, e
    end
    pd.file = p
    pd.ctx = ctx
    ctx.plugin = pd
    table.insert(plugins, pd)
    e2lib.logf(4, "loading plugin: %s (%s)", pd.file, pd.description)
    return true, nil
end

--- load plugins from a directory, and apply the plugin context
-- @param dir string: directory
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure
function plugin.load_plugins(dir, ctx)
    local e = err.new("loading plugins failed")
    e2lib.logf(4, "loading plugins from: %s", dir)

    local pfn = {}
    for fn in e2lib.directory(dir) do
        table.insert(pfn, fn)
    end

    -- create a stable base
    table.sort(pfn)

    for _,p in ipairs(pfn) do
        local rc, re = load_plugin(dir, p, ctx)
        if not rc then
            e2lib.logf(1, "loading plugin: %s failed", p)
            return false, e:cat(re)
        end
    end
    return true
end

local function plugin_dfs_visit(plugin, plugins, pluginsvisited, pluginssorted,
    cycledetect)
    if pluginsvisited[plugin] then
        return
    end

    pluginsvisited[plugin] = true
    cycledetect[plugin] = true

    for _,pluginm in ipairs(plugins) do
        for _,mdep in ipairs(pluginm.depends) do
            if mdep == plugin.file then
                if cycledetect[pluginm] then
                    local e = err.new("plugin dependency cycle detected.")
                    local c
                    for p,_ in pairs(cycledetect) do
                        c = " " .. p.file
                    end
                    e:append("somewhere in this branch:" .. c)
                    e2lib.abort(e)
                end
                plugin_dfs_visit(pluginm, plugins, pluginsvisited,
                    pluginssorted, cycledetect)
            end
        end
    end

    table.insert(pluginssorted, 1,  plugin)
end

--- topological sort for plugins according to their dependencies
-- When cycles are encountered, it aborts.
-- @return a sorted plugin table
local function plugin_tsort(plugins)
    local pluginsvisited = {}
    local pluginssorted = {}

    for _, plugin in ipairs(plugins) do
        if not pluginsvisited[plugin] then
            plugin_dfs_visit(plugin, plugins, pluginsvisited, pluginssorted, {})
        end
    end

    return pluginssorted
end

--- initialize plugins
-- @return bool
-- @return an error object on failure
function plugin.init_plugins()
    local e = err.new("initializing plugins failed")

    plugins = plugin_tsort(plugins)

    for _, pd in ipairs(plugins) do
        e2lib.logf(4, "init plugin %s", pd.file)
        local rc, re = pd.init(pd.ctx)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

--- deinitialize plugins
-- @return bool
-- @return an error object on failure
function plugin.exit_plugins()
    local e = err.new("deinitializing plugins failed")
    for _, pd in ipairs(plugins) do
        local rc, re = pd.exit(pd.ctx)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true, nil
end

--- print a description for each plugin. This is for use with the --version
-- option. This version always succeeds.
-- @return nil
function plugin.print_descriptions()
    for i,pd in ipairs(plugins) do
        print(pd.description)
    end
end

return strict.lock(plugin)

-- vim:sw=4:sts=4:et:
