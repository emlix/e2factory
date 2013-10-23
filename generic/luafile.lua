--- File handling.
-- @module generic.luafile

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
local e2lib = require("e2lib")
local err = require("err")
local luafile_ll = require("luafile_ll")
local strict = require("strict")

--- Numeric constant for stdin.
luafile.STDIN = 0;
--- Numeric constant for stdout.
luafile.STDOUT = 1;
--- Numeric constant for sterr.
luafile.STDERR = 2;

--- Check whether a luafile object is valid and contains an open file.
-- @param luafile File object.
-- @return True on success, false on error.
-- @return Error object on failure.
local function valid_open_luafile(luafile)
    local msg = "Internal luafile error: Please report this error:"

    if type(luafile) ~= "table" then
        return false, err.new("%s invalid object", msg)
    end

    if type(luafile.file) == "boolean" and not luafile.file then
        return false,
            err.new("%s no open file", msg)
    end

    if type(luafile.file) ~= "userdata" then
        return false, err.new("%s invalid internal field structure")
    end

    return true
end

--- Create new file object.
-- @return File object. This function always succeeds.
function luafile.new()
    local luafile = {}
    luafile.file = false
    return strict.lock(luafile)
end

--- Open a file.
-- @param path Path to file (string).
-- @param mode Mode string of r, r+, w, w+, a or a+. See fopen(3) for details.
-- @return File object on success, false on error.
-- @return Error object on failure.
function luafile.fopen(path, mode)
    local f, handle, errstring

    handle, errstring = luafile_ll.fopen(path, mode)
    if not handle then
        return false, err.new("could not open file %q with mode %q: %s",
            path, mode, errstring)
    end

    f = luafile.new()
    f.file = handle
    return f
end

--- Open a file descriptor.
-- @param fd Valid UNIX file descriptor (number).
-- @param mode Mode string of r, r+, w, w+, a or a+. See fdopen(3) for details.
-- @return File object on success, false on error.
-- @return Error object on failure.
function luafile.fdopen(fd, mode)
    local f, handle, errstring

    handle, errstring = luafile_ll.fdopen(fd, mode)
    if not handle then
        return false,
            err.new("could not open file descriptor %d with mode %q: %s",
                fd, mode, errstring)
    end

    f = luafile.new()
    f.file = handle
    return f
end

--- Close a file object.
-- @param luafile File object.
-- @return True on success, false on error.
-- @return Error object on failure.
function luafile.fclose(luafile)
    local rc, re, errstring

    rc, re = valid_open_luafile(luafile)
    if not rc then
        return false, re
    end

    rc, errstring = luafile_ll.fclose(luafile.file)
    luafile.file = false
    if not rc then
        return false, err.new("error closing file: %s", errstring)
    end

    return true
end

--- Read a file.
-- @param luafile File object.
-- @return File data as a string, or false on error. May be up to 16K bytes
-- large and contain embedded zero's. On EOF an empty string is returned.
-- @return Error object on failure.
function luafile.fread(luafile)
    local rc, re, errstring, buffer

    rc, re = valid_open_luafile(luafile)
    if not rc then
        return false, re
    end

    buffer, errstring = luafile_ll.fread(luafile.file)
    if not buffer then
        return false, err.new("error reading file: %s", errstring)
    end

    return buffer
end

--- Read character from file.
-- @param luafile File object.
-- @return Character as a string, string of length 0 on EOF, or false on error.
-- @return Error object on failure.
function luafile.fgetc(luafile)
    local rc, re, errstring, char

    rc, re = valid_open_luafile(luafile)
    if not rc then
        return false, re
    end

    char, errstring = luafile_ll.fgetc(luafile.file)
    if not char then
        return false, err.new("error reading character from file: %s",
            errstring)
    end


    return char
end

--- Write buffer to a file.
-- @param luafile File object.
-- @param buffer Data string to be written. May contain embedded zero's.
-- @return True on success, False on error.
-- @return Error object on failure.
function luafile.fwrite(luafile, buffer)
    local rc, re, errstring

    rc, re = valid_open_luafile(luafile)
    if not rc then
        return false, rc
    end

    rc, errstring = luafile_ll.fwrite(luafile.file, buffer)
    if not rc then
        return false, err.new("error writing file: %s", errstring)
    end

    return true
end

--- Read line from a file.
-- @param file File object.
-- @return Line of data, potentially including a new-line character at the end
-- but no further. Returns the empty string on end-of-file, or false in
-- case of an error.
-- @return Error object on failure.
function luafile.readline(file)
    local rc, re, line, char

    --rc, re = valid_open_luafile(file)
    --if not rc then
    --    return false, rc
    --end

    line = ""
    while true do
        char, re = luafile.fgetc(file)
        if not char then
            return false, re
        elseif char == "\0" then
            -- fgets cannot handle embedded zeros, causing mayhem in C.
            -- We could do this in Lua, but lets signal an error till
            -- we have a use case.
            return false, err.new("got NUL character while reading line")
        elseif char == "\n" or char == "" then
            line = line..char -- retain newline just like fgets does.
            return line
        end

        line = line..char
    end
end

--- Return file descriptor of a file object.
-- @param luafile File object.
-- @return Integer file descriptor of the file descriptor. This method does not
-- have an error condition. If passed an invalid or closed file object, it calls
-- e2lib.abort() signaling an internal error.
function luafile.fileno(luafile)
    local rc, re, fd, errstring

    rc, re = valid_open_luafile(luafile)
    if not rc then
        e2lib.abort(re)
    end

    fd, errstring = luafile_ll.fileno(luafile.file)
    if not fd then
        e2lib.abort(err.new("%s", errstring))
    end

    return fd
end

--- Test for end of file.
-- @param luafile File object.
-- @return True on end-of-file, false otherwise. feof calls
-- e2lib.abort() when used with an invalid file object.
function luafile.feof(luafile)
    local rc, re

    rc, re = valid_open_luafile(luafile)
    if not rc then
        e2lib.abort(re)
    end

    rc, re = luafile_ll.feof(luafile.file)
    if not rc and re then
        e2lib.abort(err.new("%s", re))
    end

    return rc
end

--- Enable line buffer mode. See setbuf(3) for details. setlinebuf has no
-- error conditions. If an invalid file object is passed, it calls
-- e2lib.abort() terminating the process.
-- @param luafile File object
function luafile.setlinebuf(luafile)
    local errstring, rc, re

    rc, re = valid_open_luafile(luafile)
    if not rc then
        e2lib.abort(re)
    end

    rc, errstring = luafile_ll.setlinebuf(luafile.file)
    if not rc then
        e2lib.abort(err.new("%s", errstring))
    end
end

--- Duplicate a file descriptor. See dup(2) for details.
-- @param oldfd File descriptor to duplicate.
-- @param newfd Duplicated file descritor. If the file descriptor was open
-- before the call, it's closed automatically.
-- @return True on success, false on error.
-- @return Error object on failure.
function luafile.dup2(oldfd, newfd)
    local rc, errstring

    rc, errstring = luafile_ll.dup2(oldfd, newfd)
    if not rc then
        return false,
            err.new("duplicating file descriptor failed: %s", errstring)
    end

    return true
end


--- Create a new UNIX pipe(2) between two file objects.
-- @return File object in read mode, or false on error.
-- @return File object in write mode, or error object on failure.
function luafile.pipe()
    local fd1, fd2, fr, fw, re

    fd1, fd2 = luafile_ll.pipe()
    if not fd1 then
        return false, err.new("failed creating pipe: %s", fd2)
    end

    fr, re = luafile.fdopen(fd1, "r")
    if not fr then
        return false, re
    end

    fw,re = luafile.fdopen(fd2, "w")
    if not fw then
        return false, re
    end

    return fr, fw
end


--- Set the CLOEXEC flag on underlying file descriptor. Throws exception on
-- invalid input.
-- @param something can be a file descriptor number, luafile object, or io file
-- @param set True to set the CLOEXEC, False to unset it. Defaults to True.
-- @return True on success, False on error.
function luafile.cloexec(something, set)
    assert(something ~= nil)
    assert(set == nil or type(set) == "boolean")
    if set == nil then
        set = true
    end

    return luafile_ll.cloexec(something, set)
end

return strict.lock(luafile)

-- vim:sw=4:sts=4:et:
