--- Extended IO
-- @module generic.eio

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

local eio = {}
package.loaded["eio"] = eio -- prevent module loading loop

local e2lib = require("e2lib")
local err = require("err")
local leio = require("leio")
local strict = require("strict")
local trace = require("trace")

--- Numeric constant for stdin.
eio.STDIN = 0;
--- Numeric constant for stdout.
eio.STDOUT = 1;
--- Numeric constant for sterr.
eio.STDERR = 2;

--- Check whether an EIO object is valid and contains an open file.
-- @param file File object.
-- @return True on success, false on error.
-- @return Error object on failure.
local function is_eio_object(file)
    local msg = "Internal EIO error: Please report this error:"

    if type(file) ~= "table" then
        return false, err.new("%s invalid object", msg)
    end

    if type(file.handle) == "boolean" and not file.handle then
        return false,
            err.new("%s no open file", msg)
    end

    if type(file.handle) ~= "userdata" then
        return false, err.new("%s invalid internal field structure")
    end

    return true
end

--- Create new file object.
-- @return File object. This function always succeeds.
function eio.new()
    local file = {}
    file.handle = false
    file.finfo = false -- purely informative file name or descriptor string
                       -- for better error messages.
    return strict.lock(file)
end

--- Open a file.
-- @param path Path to file (string).
-- @param mode Mode string of r, r+, w, w+, a or a+. See fopen(3) for details.
-- @return File object on success, false on error.
-- @return Error object on failure.
function eio.fopen(path, mode)
    local file, handle, errstring

    handle, errstring = leio.fopen(path, mode)
    if not handle then
        return false, err.new("could not open file %q with mode %q: %s",
            path, mode, errstring)
    end

    file = eio.new()
    file.handle = handle
    file.finfo = string.format("file %q", path)
    return file
end

--- Open a file descriptor.
-- @param fd Valid UNIX file descriptor (number).
-- @param mode Mode string of r, r+, w, w+, a or a+. See fdopen(3) for details.
-- @return File object on success, false on error.
-- @return Error object on failure.
function eio.fdopen(fd, mode)
    local file, handle, errstring

    handle, errstring = leio.fdopen(fd, mode)
    if not handle then
        return false,
            err.new("could not open file descriptor #%d with mode %q: %s",
                fd, mode, errstring)
    end

    file = eio.new()
    file.handle = handle
    file.finfo = string.format("file descriptor #%d", fd)
    return file
end

--- Close a file object.
-- @param file File object.
-- @return True on success, false on error.
-- @return Error object on failure.
function eio.fclose(file)
    local rc, re, errstring

    rc, re = is_eio_object(file)
    if not rc then
        return false, re
    end

    rc, errstring = leio.fclose(file.handle)
    file.handle = false
    if not rc then
        return false, err.new("error closing %s: %s", file.finfo, errstring)
    end

    return true
end

--- Read a file.
-- @param file File object.
-- @param size Positive number specifying how many bytes to read.
-- @return File data as a string, or false on error. May be *up to* 'size' bytes
-- large and contain embedded zero's. On EOF the empty string is returned.
-- @return Error object on failure.
function eio.fread(file, size)
    local rc, re, errstring, buffer

    rc, re = is_eio_object(file)
    if not rc then
        return false, re
    end

    if type(size) ~= "number" then
        return false, err.new("eio.fread: size argument has wrong type")
    end

    if size <= 0 or size > 2147483648 --[[2GB]] then
        return false, err("eio.fread: size argument out of range")
    end

    buffer, errstring = leio.fread(file.handle, size)
    if not buffer then
        return false, err.new("error reading %s: %s", file.finfo, errstring)
    end

    return buffer
end

--- Read character from file.
-- @param file File object.
-- @return Character as a string, string of length 0 on EOF, or false on error.
-- @return Error object on failure.
function eio.fgetc(file)
    local rc, re, errstring, char

    rc, re = is_eio_object(file)
    if not rc then
        return false, re
    end

    char, errstring = leio.fgetc(file.handle)
    if not char then
        return false, err.new("error reading character from %s: %s",
            file.finfo, errstring)
    end


    return char
end

--- Write buffer to a file.
-- @param file File object.
-- @param buffer Data string to be written. May contain embedded zero's.
-- @return True on success, False on error.
-- @return Error object on failure.
function eio.fwrite(file, buffer)
    local rc, re, errstring

    rc, re = is_eio_object(file)
    if not rc then
        return false, rc
    end

    rc, errstring = leio.fwrite(file.handle, buffer)
    if not rc then
        return false, err.new("error writing %s: %s", file.finfo, errstring)
    end

    return true
end

--- Read line from a file.
-- @param file File object.
-- @return Line of data, potentially including a new-line character at the end
-- but no further. Returns the empty string on end-of-file, or false in
-- case of an error.
-- @return Error object on failure.
function eio.readline(file)
    local rc, re, line, char

    trace.disable() -- don't spam the logs with fgetc calls.

    line = ""
    while true do
        char, re = eio.fgetc(file)
        if not char then
            trace.enable()
            return false, re
        elseif char == "\0" then
            -- fgets cannot handle embedded zeros, causing mayhem in C.
            -- We could do this in Lua, but lets signal an error till
            -- we have a use case.
            trace.enable()
            return false, err.new("got NUL character while reading line")
        elseif char == "\n" or char == "" then
            line = line..char -- retain newline just like fgets does.
            trace.enable()
            return line
        end

        line = line..char
    end
end

--- Return file descriptor of a file object.
-- @param file File object.
-- @return Integer file descriptor of the file descriptor. This method does not
-- have an error condition. If passed an invalid or closed file object, it calls
-- e2lib.abort() signaling an internal error.
function eio.fileno(file)
    local rc, re, fd, errstring

    rc, re = is_eio_object(file)
    if not rc then
        e2lib.abort(re)
    end

    fd, errstring = leio.fileno(file.handle)
    if not fd then
        e2lib.abort(err.new("%s", errstring))
    end

    return fd
end

--- Test for end of file.
-- @param file File object.
-- @return True on end-of-file, false otherwise. feof calls
-- e2lib.abort() when used with an invalid file object.
function eio.feof(file)
    local rc, re

    rc, re = is_eio_object(file)
    if not rc then
        e2lib.abort(re)
    end

    rc, re = leio.feof(file.handle)
    if not rc and re then
        e2lib.abort(err.new("%s", re))
    end

    return rc
end

--- Enable line buffer mode. See setbuf(3) for details. setlinebuf has no
-- error conditions. If an invalid file object is passed, it calls
-- e2lib.abort() terminating the process.
-- @param file File object
function eio.setlinebuf(file)
    local errstring, rc, re

    rc, re = is_eio_object(file)
    if not rc then
        e2lib.abort(re)
    end

    rc, errstring = leio.setlinebuf(file.handle)
    if not rc then
        e2lib.abort(err.new("%s", errstring))
    end
end

--- Turn line and block buffering off. See setbuf(3) for details. setunbuffered
-- has no error conditions. If an invalid file object is passed, it calls
-- e2lib.abort() terminating the process.
-- @param file File object
function eio.setunbuffered(file)
    local errstring, rc, re

    rc, re = is_eio_object(file)
    if not rc then
        e2lib.abort(re)
    end

    rc, errstring = leio.setunbuffered(file.handle)
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
function eio.dup2(oldfd, newfd)
    local rc, errstring

    rc, errstring = leio.dup2(oldfd, newfd)
    if not rc then
        return false,
            err.new("duplicating file descriptor failed: %s", errstring)
    end

    return true
end


--- Create a new UNIX pipe(2) between two file objects.
-- @return File object in read mode, or false on error.
-- @return File object in write mode, or error object on failure.
function eio.pipe()
    local fd1, fd2, fr, fw, re

    fd1, fd2 = leio.pipe()
    if not fd1 then
        return false, err.new("failed creating pipe: %s", fd2)
    end

    fr, re = eio.fdopen(fd1, "r")
    if not fr then
        return false, re
    end

    fw,re = eio.fdopen(fd2, "w")
    if not fw then
        return false, re
    end

    return fr, fw
end


--- Set the CLOEXEC flag on underlying file descriptor. Throws exception on
-- invalid input.
-- @param something can be a numeric file descriptor, eio file, or io file
-- @param set True to set the CLOEXEC, False to unset it. Defaults to True.
-- @return True on success, False on error.
function eio.cloexec(something, set)
    assert(something ~= nil)
    assert(set == nil or type(set) == "boolean")
    if set == nil then
        set = true
    end

    return leio.cloexec(something, set)
end


--- Read the first line from file pointed to by filename. End of file is
-- considered to be an error.
-- @param filename File name.
-- @return First line of text, up to but not including the new-line character.
-- False on error.
-- @return Error object on failure.
function eio.file_read_line(filename)
    local file, re, line, rc

    file, re = eio.fopen(filename, "r")
    if not file then
        return false, re
    end

    line, re = eio.readline(file)
    if not line then
        eio.fclose(file)
        return false, re
    end

    rc, re = eio.fclose(file)
    if not rc then
        return false, re
    end

    if line == "" then
        return false, err.new("unexpected end of file in %q", filename)
    end

    if string.sub(line, -1) == "\n" then
        line = string.sub(line, 1, -2)
    end

    return line
end

--- Create or truncate a file pointed to by filename, and fill it with data.
-- @param filename File name.
-- @param data String of data, may contain embedded zeros.
-- @return True on success, false on error.
-- @return Error object on failure.
function eio.file_write(filename, data)
    local rc, re, file

    file, re = eio.fopen(filename, "w")
    if not file then
        return false, re
    end

    rc, re = eio.fwrite(file, data)
    if not rc then
        return false, re
    end

    rc, re = eio.fclose(file)
    if not rc then
        return false, re
    end

    return true
end

return strict.lock(eio)

-- vim:sw=4:sts=4:et:
