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

require("buildconfig")
local e2lib = require("e2lib")
local e2option = require("e2option")
local generic_git = require("generic_git")
local err = require("err")

e2lib.init()

e2option.documentation = [[
usage: e2-install-e2 [OPTION ...]

Installs local tools in project environment.
]]

local opts = e2option.parse(arg)

local root = e2lib.locate_project_root()
if not root then
  e2lib.abort("can't locate project root.")
end

-- try to get project specific config file paht
local config_file_config = string.format("%s/%s", root, e2lib.globals.e2config)
local config_file = e2lib.read_line(config_file_config)
-- don't care if this succeeds, the parameter is optional.

local rc, e = e2lib.read_global_config(config_file)
if not rc then
  e2lib.abort(e)
end
e2lib.init2()
local e = err.new("e2-install-e2 failed")

local config = e2lib.get_global_config()
local servers = config.servers
if not servers then
  e2lib.abort("no servers configured in global config")
end

local scache, re = e2lib.setup_cache()
if not scache then
  e2lib.abort(e:cat(re))
end

-- standard global tool setup finished

if #opts.arguments > 0 then
  e2option.usage(1)
end

local rc, re

-- change to the project root directory
rc, re = e2lib.chdir(root)
if not rc then
  e2lib.abort(e:cat(re))
end

-- read the version from the first line
local line, re = e2lib.read_line(e2lib.globals.global_interface_version_file)
if not line then
	e2lib.abort(e:cat(re))
end

v = tonumber(line:match("[0-9]+"))
if not v or v < 1 or v > 2 then
	e2lib.abort(e:append("unhandled project version"))
end

-- version is 1 or 2

-- remove the old e2 source, installation and plugins, if it exists
rc, re = e2lib.rm(".e2/e2 .e2/bin .e2/lib .e2/plugins", "-fr")
if not rc then
  e2lib.abort(e:cat(re))
end

e2lib.logf(2, "installing local tools")

local extensions
if e2util.exists(e2lib.globals.extension_config) then
  extensions, re = e2lib.read_extension_config()
  if not extensions then
    e2lib.abort(e:cat(re))
  end
else
  e2lib.warnf("WOTHER", "extension configuration not available")
  extensions = {}  -- empty list
end

local s = e2lib.read_line(".e2/e2version")
local branch, tag = s:match("(%S+) (%S+)")
if not branch or not tag then
  e2lib.abort(e:append("cannot parse e2 version"))
end
local ref
if tag == "^" then
  e2lib.warnf("WOTHER", "using e2 version by branch")
  if branch:match("/") then
    ref = branch
  else
    ref = string.format("remotes/origin/%s", branch)
  end
else
  ref = string.format("refs/tags/%s", tag)
end

rc, re = e2lib.chdir(".e2")
if not rc then
  e2lib.abort(e:cat(re))
end

-- checkout e2factory itself
local server = config.site.e2_server
local location = config.site.e2_location
local destdir = "e2"
local skip_checkout = false
e2lib.logf(2, "fetching e2factory (ref %s)", ref)
rc, re = generic_git.git_clone_from_server(scache, server, location,
						destdir, skip_checkout)
if not rc then
  e2lib.abort(e:cat(re))
end
e2lib.chdir(destdir)

-- checkout ref
local args = string.format("%s --", ref)
rc, re = e2lib.git(nil, "checkout", args)
if not rc then
  e2lib.abort(e:cat(re))
end

for _,ex in ipairs(extensions) do
  -- change to the e2factory extensions directory
  rc, re = e2lib.chdir(root .. "/.e2/e2/extensions")
  if not rc then
    e2lib.abort(e:cat(re))
  end
  local ref
  if ex.ref:match("/") then
    ref = ex.ref
  else
    ref = string.format("refs/tags/%s", ex.ref)
  end
  e2lib.logf(2, "fetching extension: %s (%s)", ex.name, ref)
  local server = config.site.e2_server
  local location = string.format("%s/%s.git", config.site.e2_base, ex.name)
  local destdir = ex.name
  local skip_checkout = false
  rc, re = e2lib.rm(destdir, "-fr")
  if not rc then
    e2lib.abort(e:cat(re))
  end
  rc, re = generic_git.git_clone_from_server(scache, server, location,
						destdir, skip_checkout)
  if not rc then
    e2lib.abort(e:cat(re))
  end
  e2lib.chdir(destdir)

  -- checkout ref
  rc, re = e2lib.git(nil, "checkout", ref)
  if not rc then
    e2lib.abort(e:cat(re))
  end
end

-- build and install
e2lib.logf(2, "building e2factory")
rc, re = e2lib.chdir(root .. "/.e2/e2")
if not rc then
  e2lib.abort(e:cat(re))
end
local cmd = string.format("make PREFIX=%s BINDIR=%s local install-local",
  e2lib.shquote(buildconfig.PREFIX), e2lib.shquote(buildconfig.BINDIR))
rc, re = e2lib.callcmd_capture(cmd)
if rc ~= 0 then
  e2lib.abort(e:cat(re))
end

e2lib.finish()
