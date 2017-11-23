--- Console output. When e2factory acts as a command-line program, this
-- is just a wrapper for the stdout and stderr channels. This module should make
-- it easy to extend and redirect console output for other purposes.
-- @module generic.console

-- Copyright (C) 2013 emlix GmbH, see file AUTHORS
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

local console = {}
package.loaded["console"] = console -- prevent module loading loop

local eio = require("eio")
local strict = require("strict")

local stdout = false
local stderr = false

--- Open and set up standard and error output to the console.
function console.open()
    local rc, re

    rc, re = eio.fdopen(eio.STDERR, "w")
    if rc then
        stderr = rc
        eio.setunbuffered(stderr)
    end

    rc, re = eio.fdopen(eio.STDOUT, "w")
    if rc then
        stdout = rc
    end
end

--- Close console outputs, if appropriate.
function console.close()
    -- didn't open stdout and stderr, don't close them.
end

--- Write message to the standard output channel.
-- @param msg Message string.
function console.info(msg)
    if stdout then
        eio.fwrite(stdout, msg)
    else
        io.stdout:write(msg)
    end
end

--- Write message to the error output channel.
-- @param msg Error message string.
function console.eout(msg)
    if stderr then
        eio.fwrite(stderr, msg)
    else
        io.stderr:write(msg)
    end
end

--- Write message to the standard output channel, and append a newline.
-- @param msg Message string, may be nil.
function console.infonl(msg)
    msg = msg or ""
    return console.info(msg.."\n")
end

--- Pass format string and arguments to string.format() before sending the
-- resulting string to the standard output channel.
-- @param format string.format() compatible format.
-- @param ... Arguments as per format string above.
function console.infof(format, ...)
    return console.info(string.format(format, ...))
end


--- Pass format string and arguments to string.format() before sending the
-- resulting string to the error output channel.
-- @param format string.format() compatible format.
-- @param ... Arguments as per format string above.
function console.eoutf(format, ...)
    return console.eout(string.format(format, ...))
end

return strict.lock(console)

-- vim:sw=4:sts=4:et:
