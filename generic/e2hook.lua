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

e2hook = e2lib.module("e2hook")

e2hook.hooks = {}

local hooks = { 
  "tool-start",
  "tool-finish",
  "pre-build",
  "post-build",
  "create-project",
  "fetch-project",
  "fetch-sources",
  "enter-playground",
  "use-source",
  "build-setup-chroot",
  "build-pre-runbuild",
  "build-post-runbuild",
  "build-remove-chroot",
  "build-pre-sources",
  "build-post-sources",
  "build-pre-result",
  "build-post-result",
  "files-prepare-source",
  "build-failure",
}

for _, k in pairs(hooks) do
  e2hook.hooks[ k ] = true
end

e2hook.info = nil
e2hook.arguments = nil

function e2hook.log(msg)
  e2lib.log(3, "[hook: " .. e2hook.hookname .. "] " .. msg)
end

function e2hook.run_hook(info, hookname, arguments, toolname)
  if not e2hook.hooks[ hookname ] then
    e2lib.bomb("invalid hook: ", hookname)
  end
  local hfile
  if info then
    hfile = info.root .. "/proj/hooks/" .. hookname
  else
    hfile = buildconfig.PREFIX .. "/share/e2/hooks/" .. hookname
  end
  if e2util.exists(hfile) then
    e2lib.log(3, "running hook `" .. hookname .. "' ...")
    e2hook.arguments = arguments
    e2hook.hookname = hookname
    e2hook.info = info or {}
    e2hook.toolname = toolname
    dofile(hfile)
  end
end
