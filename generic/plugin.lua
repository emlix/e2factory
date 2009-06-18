module("plugin", package.seeall)

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
plugins = {}

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
-- @param plugin_file string: filename
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure
local function load_plugin(dir, p, ctx)
	local e = new_error("loading plugin failed: %s", p)
	local plugin_file = string.format("%s/%s", dir, p)
	local chunk, msg = loadfile(plugin_file)
	if not chunk then
		return false, e:append("%s", msg)
	end
	chunk()
	if not plugin_descriptor then
		return false, e:append("no plugin descriptor in plugin: %s",
								plugin_file)
	end
	local pd = plugin_descriptor
	if type(pd.description) ~= "string" then
		e:append("description missing in plugin descriptor")
	end
	if type(pd.init) ~= "function" then
		e:append("init function missing in descriptor")
	end
	if type(pd.exit) ~= "function" then
		e:append("exit function missing in descriptor")
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

--- initialize a plugin
-- @param pd table: plugin descriptor
-- @return bool
-- @return an error object on failure
local function init_plugin(pd)
	return pd.init(pd.ctx)
end

--- deinitialize a plugin
-- @param pd table: plugin descriptor
-- @return bool
local function exit_plugin(pd)
	return pd.exit(pd.ctx)
end

--- load plugins from a directory, and apply the plugin context
-- @param dir string: directory
-- @param ctx table: plugin context
-- @return bool
-- @return an error object on failure
function load_plugins(dir, ctx)
  local e = new_error("loading plugins failed")
  e2lib.logf(4, "loading plugins from: %s", dir)
  for p in e2lib.directory(dir) do
    local rc, re = load_plugin(dir, p, ctx)
    if not rc then
      e2lib.logf(1, "loading plugin: %s failed", p)
      return false, e:cat(re)
    end
  end
  return true
end

--- initialize plugins
-- @return bool
-- @return an error object on failure
function init_plugins()
  local e = new_error("initializing plugins failed")
  for _, pd in ipairs(plugins) do
    local rc, re = init_plugin(pd)
    if not rc then
      return false, e:cat(re)
    end
  end
  return true, nil
end

--- deinitialize plugins
-- @return bool
-- @return an error object on failure
function exit_plugins()
  local e = new_error("deinitializing plugins failed")
  for _, pd in ipairs(plugins) do
    local rc, re = exit_plugin(pd)
    if not rc then
      return false, e:cat(re)
    end
  end
  return true, nil
end
