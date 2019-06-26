--- Plugin Loader.
-- @module generic.plugin

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

local plugin = {}
local console = require("console")
local err = require("err")
local e2lib = require("e2lib")
local strict = require("strict")

--- Plugin descriptor. Must be present in a plugin, otherwise it can not be
-- loaded.
-- @class table
-- @name plugin_descriptor
-- @field description Human readable plugin description string, including
-- unique plugin version information (string).
-- @field init Initialization function (see description below).
-- @field exit Deinitialization function (see description below).
-- @field depends Array of plugin file names to be loaded before this plugin
-- (table containing strings). Optional.
-- @field Plugin file name (string) (inserted by plugin loader)
-- @field ctx Plugin context (table) (inserted by plugin loader)

--- Plugin context. The plugin is passed this table on (de)initialization by
-- the plugin loader.
-- @class table
-- @name plugin_ctx
-- @field plugin Plugin descriptor (table)
-- @field info Global info table (local tools only)

--- Plugin init function.
-- @class function
-- @name init
-- @param ctx Plugin context (table).
-- @return Boolean.
-- @return An error object on failure.

--- Plugin exit function
-- @class function
-- @name exit
-- @param ctx Plugin context (table).
-- @return Boolean.
-- @return An error object on failure.

-- list of plugin descriptors
local plugins = {}

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

            if not e2lib.exists(string.format("%s/%s", dir, dep)) then
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
    for fn, re in e2lib.directory(dir) do
        if not fn then
            return false, e:cat(re)
        end

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

--- Depth first search visitor that does the sorting.
local function plugin_dfs_visit(plugin, plugins, pluginsvisited, pluginssorted,
    cycledetect)

    local rc, re

    if pluginsvisited[plugin] then
        return true
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
                    return false, e
                end
                rc, re = plugin_dfs_visit(pluginm, plugins, pluginsvisited,
                    pluginssorted, cycledetect)
                if not rc then
                    return false, re
                end
            end
        end
    end

    table.insert(pluginssorted, 1,  plugin)

    return true
end

--- Topological sort for plugins according to their dependencies.
-- @return Sorted plugin table or false on error.
-- @return Error object on failure.
local function plugin_tsort(plugins)
    local rc, re
    local pluginsvisited = {}
    local pluginssorted = {}

    for _, plugin in ipairs(plugins) do
        if not pluginsvisited[plugin] then
            rc, re = plugin_dfs_visit(plugin, plugins,
                pluginsvisited, pluginssorted, {})
            if not rc then
                return false, re
            end
        end
    end

    return pluginssorted
end

--- initialize plugins
-- @return bool
-- @return an error object on failure
function plugin.init_plugins()
    local e = err.new("initializing plugins failed")
    local re

    plugins, re = plugin_tsort(plugins)
    if not plugins then
        plugins = {}
        return false, e:cat(re)
    end

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
    while #plugins > 0 do
        local pd = table.remove(plugins) -- deinitialize in reverse order
        e2lib.logf(4, "de-init plugin %s", pd.file)
        local rc, re = pd.exit(pd.ctx)
        if not rc then
            return false, e:cat(re)
        end
    end
    return true
end

--- print a description for each plugin. This is for use with the --version
-- option. This function always succeeds.
function plugin.print_descriptions()
    for i,pd in ipairs(plugins) do
        console.infonl(pd.description)
    end
end

return strict.lock(plugin)

-- vim:sw=4:sts=4:et:
