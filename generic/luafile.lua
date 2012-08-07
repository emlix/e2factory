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

local luafile = {}
require("luafile_ll")

function luafile.new()
  local f = {}
  local meta = { __index = luafile }
  setmetatable(f, meta)
  return f
end

function luafile.open(path, mode)
  local f = luafile.new()
  f.file = luafile_ll.fopen(path, mode)
  if f.file then
    return f
  end
  return nil
end

function luafile.fdopen(fd, mode)
  local f = luafile.new()
  f.file = luafile_ll.fdopen(fd, mode)
  if f.file then
    return f
  end
  return nil
end

function luafile.close(luafile)
  if luafile and luafile.file then
    if luafile_ll.fclose(luafile.file) then
      luafile.file = nil
      return true
    end
  end
  return false
end

function luafile.read(luafile)
  if luafile and luafile.file then
    return luafile_ll.fread(luafile.file)
  end
  return nil
end

function luafile.write(luafile, buffer)
  if luafile and luafile.file and buffer then
    return luafile_ll.fwrite(luafile.file, buffer)
  end
  return nil
end

function luafile.readline(luafile)
  if luafile and luafile.file then
    return luafile_ll.fgets(luafile.file)
  end
  return nil
end

function luafile.seek(luafile, offset)
  if luafile and luafile.file and offset then
    return luafile_ll.fseek(luafile.file, offset)
  end
  return nil
end

function luafile.flush(luafile)
  if luafile and luafile.file then
    return luafile_ll.fflush(luafile.file)
  end
  return nil
end

function luafile.fileno(luafile)
  if luafile and luafile.file then
    return luafile_ll.fileno(luafile.file)
  end
  return nil
end

function luafile.eof(luafile)
  if luafile and luafile.file then
    return luafile_ll.feof(luafile.file)
  end
  return nil
end

function luafile.setlinebuf(luafile)
  if luafile and luafile.file then
    return luafile_ll.setlinebuf(luafile.file)
  end
  return nil
end

function luafile.pipe()
  local rc, r, w = luafile_ll.pipe()
  local fr, fw
  if not rc then
    return false, nil, nil
  end
  fr = luafile.fdopen(r, "r")
  fw = luafile.fdopen(w, "w")
  return rc, fr, fw
end

function luafile.dup2(oldfd, newfd)
  if oldfd and newfd then
    return luafile_ll.dup2(oldfd, newfd)
  end
  return nil
end

return luafile
