--- Utility and Helper Library
-- @module generic.e2lib

-- Copyright (C) 2007-2017 emlix GmbH, see file AUTHORS
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

-- Before we do anything else, lock the global environment and default
-- packages to catch bugs
local strict = require("strict")
strict.lock(_G)
for k,_ in pairs(_G) do
    if type(_G[k]) == "table" and _G[k] ~= _G then
        strict.lock(_G[k])
    end
end

local e2lib = {}

-- Multiple modules below require e2lib themselves. This leads to a module
-- loading loop.
--
-- We solve this problem by registering e2lib as loaded, and supply the empty
-- table that we are going to fill later (after the require block below).
package.loaded["e2lib"] = e2lib

local assrt = require("assrt")
local buildconfig = require("buildconfig")
local cache = require("cache")
local console = require("console")
local eio = require("eio")
local err = require("err")
local errno = require("errno")
local le2lib = require("le2lib")
local lock = require("lock")
local plugin = require("plugin")
local tools = require("tools")
local trace = require("trace")

--- Various global settings
-- @table globals
e2lib.globals = strict.lock({
    logflags = {
        { "v1", true },    -- minimal
        { "v2", true },    -- verbose
        { "v3", false },   -- verbose-build
        { "v4", false }    -- tooldebug
    },
    warn_category = {
        WDEFAULT = false,
        WDEPRECATED = false,
        WOTHER = true,
        WPOLICY = false,
        WHINT = false,
    },
    log_debug = false,  -- debug log/warning level
    osenv = {},         -- environment variable dictionary
    tmpdir = false,     -- base temp dir, defaults to /tmp
    tmpdirs = {},       -- vector of temp dirs created by e2
    tmpfiles = {},      -- vector of temp files created by e2
    lock = false,       -- lock object
    default_projects_server = "projects",
    default_project_version = "2",
    template_path = string.format("%s/templates", buildconfig.SYSCONFDIR),
    extension_config = ".e2/extensions",
    e2config = false,
    global_interface_version_file = ".e2/global-version",
    project_location_file = ".e2/project-location",
    e2version_file = ".e2/e2version",
    syntax_file = ".e2/syntax",
    logrotate = 5,   -- configurable via config.log.logrotate
    _version = "e2factory, the emlix embedded build system, version " ..
    buildconfig.VERSION,
    _licence = [[
e2factory is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.]],
    debuglogfile = false,
    debuglogfilebuffer = {},
})

--- Call function in a protected environment. This is a fancy version of the
-- native pcall() and a poor mans exception mechanism. A traceback of the stack
-- at the time of the error is sent to logf at level 4 to help with debugging.
-- @param f Function to call.
-- @param ... Arguments to the function.
-- @return True when function ended without an anomaly, false otherwise.
-- @return If previous result is false, the object or string that was passed
--         from error(), assert() etc. If the previous result is true, the
--         first result of the called function.
-- @return Further results from the called function if any.
function e2lib.trycall(f, ...)
    local args = {...}
    return xpcall(
        function() return f(unpack(args)) end,
        function(e) e2lib.logf(4, "%s", debug.traceback("", 2)) return e end
        )
end

--- Get current working directory.
-- @return Current working directory (string) or false on error.
-- @return Error object on failure.
function e2lib.cwd()
    local path, errstring = le2lib.cwd()

    if not path then
        return false,
            err.new("cannot get current working directory: %s", errstring)
    end

    return path
end

--- Dirent table, returned by @{stat}.
-- @table dirent
-- @field dev Device-id (number).
-- @field ino Inode-number (number).
-- @field mode Permissions and access mode (number).
-- @field nlink Number of hard links (number).
-- @field uid User ID (number).
-- @field gid Group ID (number).
-- @field rdev Device id for char of block special files (number).
-- @field size File size (number).
-- @field atime access time (number).
-- @field mtime modification time (number).
-- @field ctime change time (number).
-- @field blksize block size (number).
-- @field type One of the following strings: block-special, character-special,
--             fifo-special, regular, directory, symbolic-link, socket, unknown.


--- Get file status information.
-- @param path Path to the file, including special files.
-- @return Dirent table containing attributes (see @{dirent}), or false on error
-- @return Error object on failure.
function e2lib.stat(path)
    local dirent, errstring

    dirent, errstring = le2lib.stat(path, true)
    if not dirent then
        return false, err.new("stat failed: %s: %s", path, errstring)
    end

    return dirent
end

--- Get file status information, don't follow symbolic links.
-- @param path Path to the file, including special files.
-- @return Dirent table containing attributes (see @{dirent}), or false on error
-- @return Error object on failure.
function e2lib.lstat(path)
    local dirent, errstring

    dirent, errstring = le2lib.stat(path, false)
    if not dirent then
        return false, err.new("lstat failed: %s: %s", path, errstring)
    end

    return dirent
end

--- Checks if file exists.
-- If executable is true, it also checks whether the file is executable.
-- @param path Path to check.
-- @param executable Check if executable (true) or not (false).
-- @return True if file exists, false otherwise.
function e2lib.exists(path, executable)
    return le2lib.exists(path, executable)
end

--- Create a symlink.
-- @param oldpath Path to point to (string).
-- @param newpath New symlink path (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.symlink(oldpath, newpath)
    local rc, errstring = le2lib.symlink(oldpath, newpath)

    if not rc then
        return false, err.new("creating symlink failed: %s -> %s: %s",
            newpath, oldpath, errstring)
    end

    return true
end

--- Create a hardlink.
-- @param oldpath Path to existing file (string).
-- @param newpath Path to new file (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.hardlink(oldpath, newpath)
    local rc, errstring = le2lib.hardlink(oldpath, newpath)

    if not rc then
        return false, err.new("creating hard link failed: %s -> %s: %s",
            newpath, oldpath, errstring)
    end

    return true
end

--- Wait for process to terminate.
-- @param pid Process ID, -1 to wait for any child.
-- @param wnohang True to set WNOHANG flag, pid == 0 indicates running process.
-- @return Exit status of process, signal + 128, or false on error.
-- @return Process ID of the terminated child or error object on failure.
-- @return Number of signal that killed the process, if any.
function e2lib.wait(pid, wnohang)
    while true do
        local rc, childpid, sig = le2lib.wait(pid, wnohang)
        if not rc then
            if sig ~= errno.def2errnum("EINTR") then
                return false,
                    err.new("waiting for child %d failed: %s", pid, childpid)
            end
            e2lib.logf(4, "wait(%d) returned EINTR", childpid)
        else
            return rc, childpid, sig
        end
    end
end

local _children = {}

--- Add child PID into a table to keep track of all active children of the
-- process. Also tracks the associated pty fd if there is one.
-- @param cpid Unique child PID
-- @param fd Pty file descriptor if one is associated with the child.
-- @param fd File descriptor of the PTY, optional.
-- @return nil
local function children_insert(cpid, fd)
    fd = fd or -1
    assertIsNumber(cpid)
    assertIsNumber(fd)
    assertIsNil(_children[cpid])
    _children[cpid] = fd
end

--- Remove active child PID from table. Returns pty file descriptor or -1.
-- @param cpid Active child PID.
-- @return Pty file descriptor or -1.
local function children_remove(cpid)
    assertIsNumber(cpid)
    assert(_children[cpid])
    local fd = _children[cpid]
    _children[cpid] = nil
    return fd
end

--- Send SIGINT to all children, either via kill() or if they have an
-- associated pty descriptor, via TIOCSIG ioctl.
-- @param pid Optional PID to select specific child.
local function children_send_sigint(pid)
    local rc, re
    local SIGINT = 2
    local t = _children

    if pid then
        t = {}
        assert(_children[pid])
        t[pid] = _children[pid]
    end

    for cpid, fd in pairs(t) do
        if fd < 0 then
            e2lib.logf(4, "(%d) sending SIGINT to child %d",
                e2lib.getpid(), cpid)

            rc, re = e2lib.kill(cpid, SIGINT)
            if not rc then
                e2lib.logf(4, "(%d) sending SIGINT to child %d failed",
                    e2lib.getpid(), cpid)
            end
        else
            e2lib.logf(4, "(%d) ioctl(TIOCSIG, SIGINT) to %d",
                e2lib.getpid(), fd)
            le2lib.ioctl_tiocsig_sigint(fd)
        end
    end
end

--- Assert no children are left behind (on exit).
-- If this is successful, all registered children have been terminated and
-- wait()'ed on.
local function children_assert_empty()
    for cpid, fd in pairs(_children) do
        e2lib.logf(4, "children_assert_empty: child remaining cpid=%d fd=%d",
            cpid, fd)
    end
    -- assert(next(_children) == nil, "exiting with children remaining!")
    if next(_children) then
        e2lib.logf(4, "children_assert_empty: exiting with children remaining!")
    end
end

--- Wait for process to terminate.
-- Also deletes the PID from the table of children and closes the pty descriptor
-- if the child had any.
-- @param pid Process ID, -1 to wait for any child.
-- @param wnohang True to set WNOHANG flag, pid == 0 indicates running process.
-- @return Exit status of process, signal + 128, or false on error.
-- @return Process ID of the terminated child or error object on failure.
-- @return Number of signal that killed the process, if any.
function e2lib.wait_pid_delete(pid, wnohang)
    local rc, childpid, sig = e2lib.wait(pid, wnohang)
    if rc then
        local fdm, rc, re
        fdm = children_remove(childpid)
        if fdm >= 0 then
            rc, re = eio.close(fdm)
            if not rc then
                e2lib.logf(4,
                    "wait_pid_delete: closing pty fd=%d of cpid=%d failed:\n%s",
                    fdm, childpid, re:tostring())
            end
        end
    end
    return rc, childpid, sig
end

--- Poll input output multiplexing. See poll(2) for details on flags etc.
-- @param timeout Timeout in milliseconds (number).
-- @param fdvec Vector of file descriptors. This wrapper listens for
--              POLLIN and POLLOUT events on every fd.
-- @return False on error, empty table on timeout, or a vector of tables for
--         each selected file descriptor. The tables looks like this:
--         { fd=(file descriptor number), fdvecpos=(index number),
--         POLLIN=boolean, POLLOUT=boolean }.
--         If a file descriptor is selected but neither POLLIN nor POLLOUT are
--         set, the file descriptor was closed. fdvecpos is the position of the
--         fd in the fdvec table.
-- @return Error object on failure.
function e2lib.poll(timeout, fdvec)
    while true do
        local pollvec, errstring, e = le2lib.poll(timeout, fdvec)
        if not pollvec then
            if e ~= errno.def2errnum("EINTR") then
                return false, err.new("poll() failed: %s", errstring)
            end
        else
            return pollvec
        end
    end
end

--- Rename file or directory using the rename syscall.
-- @param src Source path.
-- @param dst Destination path.
-- @return True on success, false on error.
-- @return Error object on failure.
-- @return Errno number on failure.
function e2lib.rename(src, dst)
    local rc, re, eno = le2lib.rename(src, dst)
    if rc then
        return rc
    end
    return false, err.new("renaming %q to %q failed: %s", src, dst, re), eno
end

--- Set file descriptor in non-blocking mode.
-- @param fd Open file descriptor.
function e2lib.unblock(fd)
    return le2lib.unblock(fd)
end

--- Creates a new process. Returns both in the parent and in the child.
-- @return Process ID of the child or false on error in the parent process.
--         Returns zero in the child process.
-- @return Error object on failure.
function e2lib.fork()
    local pid, errstring = le2lib.fork()

    if pid == false then
        return false, err.new("failed to fork a new child: %s", errstring)
    end

    return pid
end

--- Forkpty. Like fork but open a PTY.
-- @return PID of child or false on error. PID of 0 means child process.
-- @return File Descriptor for pseudo terminal (parent only).
--         Error object on failure.
-- @return Path to PTY device node.
function e2lib.forkpty()
    local rc, re
    local pid, fdm, ptyname

    pid, fdm, ptyname = le2lib.forkpty()
    if not pid then
        return false, err.new("failed to fork new pty: %s", fdm)
    end
    if pid == 0 then
        -- child, return early
        return pid
    end

    assert(type(fdm) == "number")
    assert(type(ptyname) == "string")

    return pid, fdm, ptyname
end

--- Set umask value.
-- @param mask New umask value.
-- @return Previous umask value.
function e2lib.umask(mask)
    return le2lib.umask(mask)
end

--- Set environment variable.
-- @param var Variable name (string).
-- @param val Variable content (string).
-- @param overwrite True to overwrite existing variable of same name.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.setenv(var, val, overwrite)
    local rc, errstring

    rc, errstring = le2lib.setenv(var, val, overwrite)
    if not rc then
        return false,
            err.new("setting environment variable %q to $q failed: %s",
            var, val, errstring)
    end

    return true
end

--- Reset signal handlers back to their default.
-- @raise Error on failure.
function e2lib.signal_reset()
    local rc, errstring

    rc, errstring = le2lib.signal_reset()
    if not rc then
        error(err.new("resetting signal handlers: %s", errstring))
    end
end

--- Install signal handlers that will call interrupt_hook()
-- @raise Error on failure.
function e2lib.signal_install()
    local rc, errstring

    rc, errstring = le2lib.signal_install()
    if not rc then
        error(err.new("installing signal handlers: %s", errstring))
    end
end

--- Get the first signal triggering shutdown.
-- Returns empty string if no signal has yet occured.
-- @return Signal name (eg "Interrupt") or "".
-- @return Signal number or 0.
function e2lib.signal_received()
    return le2lib.signal_received()
end

--- Get current process id.
-- @return Process ID (number)
function e2lib.getpid()
    -- used only for tempfile generation
    return le2lib.getpid()
end

--- Send signal to process.
-- @param pid Process ID to signal (number).
-- @param sig Signal number.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.kill(pid, sig)
    local rc, errstring = le2lib.kill(pid, sig)

    if not rc then
        return false, err.new("sending signal %d to process %d failed: %s",
            sig, pid, errstring)
    end

    return true
end

--- Execute a process image and replace the current process.
-- See execvp(3) for more information.
-- @param filenm File name or path to execute. PATH is searched.
-- @param argv Vector containing arguments for the process. First argument
--             should be the file name itself.
-- @return False on error. It does not return on success.
-- @return Error object on failure.
function e2lib.execvp(filenm, argv)
    local rc, errstring

    rc, errstring = le2lib.execvp(filenm, argv)

    return false, err.new("executing process %q failed: %s", filenm, errstring)
end

--- Interrupt handling.
-- le2lib.signal_install() installs a handler calling back into this function.
function e2lib.interrupt_hook()
    trace.install() -- reinstall the trace hook.
    children_send_sigint()
end

--- Make sure the environment variables inside the globals table are
-- initialized properly, set up output channels etc. Must be called before
-- anything else.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.init()
    e2lib.log(4, "e2lib.init()")
    console.open()

    trace.install()
    trace.default_filter()

    e2lib.signal_reset()

    e2lib.closefrom(3)
    -- ignore errors, no /proc should not prevent factory from working

    e2lib.globals.warn_category = {
        WDEFAULT = false,
        WDEPRECATED = false,
        WOTHER = true,
        WPOLICY = false,
        WHINT = false,
    }

    -- get environment variables
    local getenv = {
        { name = "HOME", required = true },
        { name = "USER", required = true },
        { name = "EDITOR", required = false, default = "vi" },
        { name = "TERM", required = false, default = "linux" },
        { name = "E2_CONFIG", required = false },
        { name = "TMPDIR", required = false, default = "/tmp" },
        { name = "E2TMPDIR", required = false },
        { name = "COLUMNS", required = false, default = "72" },
        { name = "E2_SSH", required = false },
    }

    for _, var in pairs(getenv) do
        var.val = os.getenv(var.name)
        if var.required and not var.val then
            return false, err.new("%s is not set in the environment", var.name)
        end
        if var.default and not var.val then
            var.val = var.default
        end
        e2lib.globals.osenv[var.name] = var.val
    end

    if e2lib.globals.osenv["E2TMPDIR"] then
        e2lib.globals.tmpdir = e2lib.globals.osenv["E2TMPDIR"]
    else
        e2lib.globals.tmpdir = e2lib.globals.osenv["TMPDIR"]
    end

    e2lib.globals.lock = lock.new()

    tools.add_default_tools()

    return true
end

--- Initialize e2factory further, past parsing options. Reads global config
-- and sets up tools module.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.init2()
    local rc, re, e, config, ssh

    e = err.new("Initialize global configuration and tools ")

    -- get the global configuration
    config, re = e2lib.get_global_config()
    if not config then
        return false, re
    end

    -- honour tool customizations from the config file
    if config.tools then
        for k,v in pairs(config.tools) do
            rc, re = tools.set_tool(k, v.name, v.flags, v.enable)
            if not rc then
                return false, e:cat(re)
            end
        end
    end

    -- handle E2_SSH environment setting
    ssh = e2lib.globals.osenv["E2_SSH"]
    if ssh then
        e2lib.logf(4, "using E2_SSH environment variable: %s", ssh)
        rc, re = tools.set_tool("ssh", ssh)
        if not rc then
            return false, e:cat(re)
        end
    end

    -- initialize the tools library after resetting tools
    rc, re = tools.init()
    if not rc then
        return false, e:cat(re)
    end

    return true
end

--- Print a warning, composed by concatenating all arguments to a string.
-- @param category
-- @param ... any number of strings
-- @return nil
function e2lib.warn(category, ...)
    local msg = table.concat({...})
    return e2lib.warnf(category, "%s", msg)
end

--- Print a warning.
-- @param category
-- @param format string: a format string
-- @param ... arguments required for the format string
-- @return nil
function e2lib.warnf(category, format, ...)
    if (format:len() == 0) or (not format) then
        e2lib.log(1, "Internal error: calling warnf() with zero length format")
    end
    if type(e2lib.globals.warn_category[category]) ~= "boolean" then
        e2lib.log(1,
            "Internal error: calling warnf() with invalid warning category")
    end
    if e2lib.globals.warn_category[category] == true then
        local prefix = "Warning: "
        if e2lib.globals.log_debug then
            prefix = string.format("Warning [%s]: ", category)
        end
        e2lib.log(1, prefix .. string.format(format, ...))
    end
end

--- Exit, cleaning up temporary files and directories.
-- Return code is '1' and cannot be overwritten.
-- This function takes any number of strings or an error object as arguments.
-- Please pass error objects to this function in the future.
-- @param ... an error object, or any number of strings
-- @return This function does not return
function e2lib.abort(...)
    local t = { ... }
    local e = t[1]
    if type(e) == "table" and e.print then
        e:print()
    else
        local msg = table.concat(t)
        if msg:len() == 0 then
            e2lib.log(1,
                "Internal error: calling abort() with zero length message")
        end
        e2lib.log(1, "Error: " .. msg)
    end
    e2lib.finish(1)
end

--- Enable or disable logging for level.
-- @param level number: loglevel
-- @param value bool
-- @return nil
function e2lib.setlog(level, value)
    e2lib.globals.logflags[level][2] = value
end

--- Get logging setting for level
-- @param level number: loglevel
-- @return bool
function e2lib.getlog(level)
    return e2lib.globals.logflags[level][2]
end

--- Return highest loglevel that is enabled.
-- @return number
function e2lib.maxloglevel()
    local level = 0
    for i = 1, 4 do
        if e2lib.getlog(i) then level = i end
    end
    return level
end

--- log to the debug logfile, and log to console if getlog(level)
-- @param level number: loglevel
-- @param format string: format string
-- @param ... additional parameters to pass to string.format
-- @return nil
function e2lib.logf(level, format, ...)
    if type(format) ~= "string" then
        e2lib.log(1, "Internal error: calling logf() without valid format string")
    end
    local status, msg = pcall(string.format, format, ...)
    if not status then
        e2lib.abort("failed to format log message\n",
            "  error message: ", msg, "\n",
            "  format string: ", format, "\n",
            "  ", debug.traceback())
    end
    return e2lib.log(level, msg)
end

--- log to the debug logfile, and log to console if getlog(level)
-- is true
-- @param level number: loglevel
-- @param msg string: log message
-- @param nonewline Defaults to false. Do not append newline if set to true.
function e2lib.log(level, msg, nonewline)
    trace.off()
    if level < 1 or level > 4 then
        e2lib.log(1, "Internal error: invalid log level")
    end

    if not msg then
        e2lib.log(1, "Internal error: calling log() without log message")
    end

    local log_prefix = "[" .. level .. "] "

    if not nonewline and string.sub(msg, -1) ~= "\n"  then
        msg = msg.."\n"
    end

    if e2lib.globals.debuglogfile then
        -- write out buffered messages first
        if #e2lib.globals.debuglogfilebuffer > 0 then
            for _,m in ipairs(e2lib.globals.debuglogfilebuffer) do
                eio.fwrite(e2lib.globals.debuglogfile, m)
            end
            e2lib.globals.debuglogfilebuffer = {}
        end

        eio.fwrite(e2lib.globals.debuglogfile, log_prefix .. msg)
    else
        table.insert(e2lib.globals.debuglogfilebuffer, log_prefix .. msg)
    end

    if e2lib.getlog(level) then
        if e2lib.globals.log_debug then
            console.eout(log_prefix .. msg)
        else
            console.eout(msg)
        end
    end
    trace.on()
end

--- Rotate log file.
-- @param file Absolute path to log file.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.rotate_log(file)
    local e = err.new("rotating logfile: %s", file)
    local rc, re
    local logdir = e2lib.dirname(file)
    local logfile = e2lib.basename(file)
    local files = {}
    local dst

    if not e2lib.lstat(file) then -- file may be an invalid symlink
        return true
    end

    for f, re in e2lib.directory(logdir, false) do
        local start, stop, extension

        if not f then
            return false, e:cat(re)
        end

        start, stop = string.find(f, logfile, 1, true)
        if start and start == 1 then
            extension = string.sub(f, stop+1)
            if string.find(extension, "^%.[0-9]+$") then
                table.insert(files, f)
            end
        end
    end

    -- sort in reverse order
    local function comp(a, b)
        local na = a:match("%.([0-9]+)$")
        local nb = b:match("%.([0-9]+)$")
        return tonumber(na) > tonumber(nb)
    end

    table.sort(files, comp)

    for _,f in ipairs(files) do
        local n, src, dst

        src = e2lib.join(logdir, f)
        n = f:match("%.([0-9]+)$")
        assert(n, "could not match logfile number")
        n = tonumber(n)
        if n >= e2lib.globals.logrotate - 1 then
            rc, re = e2lib.unlink(src)
            if not rc then
                return false, e:cat(re)
            end
        else
            dst = string.format("%s/%s.%d", logdir, logfile, n + 1)
            rc, re = e2lib.rename(src, dst)
            if not rc then
                return false, e:cat(re)
            end
        end
    end

    dst = string.format("%s/%s.0", logdir, logfile)
    rc, re = e2lib.rename(file, dst)
    if not rc then
        return false, e:cat(re)
    end
    return true
end

local _cleanup = {}

--- Register a callback that runs during e2lib.cleanup()
-- @param name Name of the function, for logging.
-- @param func Funtion to be run
-- @param ... Any number of arguments to be passed to function when it runs.
function e2lib.register_cleanup(name, func, ...)
    assertIsStringN(name)
    assertIsFunction(func)
    table.insert(_cleanup, #_cleanup+1, { name=name, func=func, args = {...}})
end

--- Clean up temporary files and directories, shut down plugins.
function e2lib.cleanup()
    local rc, re = plugin.exit_plugins()
    if not rc then
        e2lib.log(1, "deinitializing plugins failed (ignoring)")
    end

    for _,entry in ipairs(_cleanup) do
        e2lib.logf(4, "running cleanup callback %s()", tostring(entry.name))
        entry.func(unpack(entry.args))
    end

    e2lib.rmtempdirs()
    e2lib.rmtempfiles()
    if e2lib.globals.lock then
        e2lib.globals.lock:cleanup()
    end
end

--- exit from the tool, cleaning up temporary files and directories
-- @param rc number: return code (optional, defaults to 0)
-- @return This function does not return.
function e2lib.finish(returncode)
    local sigstr, signum
    local finalreturn
    if not returncode then
        returncode = 0
    end
    e2lib.cleanup()

    finalreturn = returncode
    sigstr, signum = e2lib.signal_received()
    if sigstr ~= "" then
        e2lib.logf(1,"Error: *** received signal %d \"%s\" ***", signum, sigstr)
        finalreturn = 128 + signum
    end

    children_assert_empty()

    e2lib.logf(4, "exiting e2factory with pid=%d returncode=%d finalreturn=%d",
        e2lib.getpid(), returncode, finalreturn)
    if e2lib.globals.debuglogfile then
        eio.fclose(e2lib.globals.debuglogfile)
        e2lib.globals.debuglogfile = false
    end
    console.close()
    os.exit(finalreturn)
end

--- Returns the "directory" part of a path
-- @param path string: a path with components separated by slashes.
-- @return all but the last component of the path, or "." if none could be found.
function e2lib.dirname(path)
    assert(type(path) == "string")

    local s, e, dir = string.find(path, "^(.*)/[^/]+[/]*$")
    if dir == "" then
        return "/"
    end

    return dir or "."
end

--- Returns the "filename" part of a path.
-- @param path string: a path with components separated by slashes.
-- @return returns the last (right-most) component of a path, or the path
-- itself if no component could be found.
function e2lib.basename(path)
    assert(type(path) == "string")

    local s, e, base = string.find(path, "^.*/([^/]+)[/]*$")
    if not base then
        base = path
    end

    return base
end

--- Return a file path joined from the supplied components.
-- This function is modelled after Python's os.path.join, but missing some
-- features and handles edge cases slightly different. It only knows about
-- UNIX-style forward slash separators. Joining an empty string at the end will
-- result in a trailing separator to be added, following Python's behaviour.
-- The function does not fail under normal circumstances.
--
-- @param p1 A potentially empty path component (string). This argument is
--           mandatory.
-- @param p2 A potentially empty, optional path component (string).
-- @param ... Further path components, following the same rule as "p2".
-- @return A joined path (string), which may be empty.
function e2lib.join(p1, p2, ...)
    assert(type(p1) == "string")
    assert(p2 == nil or type(p2) == "string")

    local sep = "/"
    local args = {p1, p2, ...}
    local buildpath = ""
    local sepnext = false
    local component

    for i=1,#args do
        component = args[i]
        assert(type(component) == "string", "join() arg not a string")

        if sepnext then
            -- If the previous or next component already
            -- has a separator in the right place, we don't
            -- need to add one. We do however not go to the
            -- trouble removing multiple separators.
            if buildpath:sub(-1) == sep or
                component:sub(1) == sep then
                -- do nothing
            else
                buildpath = buildpath .. sep
            end
        end

        buildpath = buildpath .. component

        if component:len() > 0 then
            sepnext = true
        else
            sepnext = false
        end
    end

    return buildpath
end

--- Checks whether file matches some usual backup file names left behind by vi
-- and emacs.
function e2lib.is_backup_file(path)
    return string.find(path, "~$") or string.find(path, "^#.*#$")
end

--- quotes a string so it can be safely passed to a shell
-- @param str string to quote
-- @return quoted string
function e2lib.shquote(str)
    assert(type(str) == "string")

    str = string.gsub(str, "'", "'\"'\"'")
    return "'"..str.."'"
end

--- Translate filename suffixes to valid tartypes for e2-su-2.2 only.
-- @param filename string: filename
-- @return string: tartype, or nil on failure
-- @return an error object on failure
function e2lib.tartype_by_suffix(filename)
    local tartype
    if filename:match("tgz$") or filename:match("tar.gz$") then
        tartype = "tar.gz"
    elseif filename:match("tar.bz2$") then
        tartype = "tar.bz2"
    elseif filename:match("tar$") then
        tartype = "tar"
    else
        return false, err.new("unknown suffix for filename: %s", filename)
    end
    return tartype
end

--- Check the global configuration for existance of fields and their types.
-- @param config e2config table to check.
-- @return True on success, false on error.
-- @return Error object on failure.
local function verify_global_config(config)
    local rc, re

    local function assert_type(x, d, t1)
        local t2 = type(x)
        if t1 ~= t2 then
            return false,
                err.new("configuration error: %s (expected %s got %s)",
                d, t1, t2)
        end

        return true
    end

    if config.log then
        rc, re = assert_type(config.log, "config.log", "table")
        if not rc then
            return false, re
        end

        if config.log.logrotate then
            rc, re = assert_type(config.log.logrotate, "config.log.logrotate", "number")
            if not rc then
                return false, re
            end
            e2lib.globals.logrotate = config.log.logrotate
        end
    end
    rc, re = assert_type(config.site, "config.site", "table")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.site.e2_branch, "config.site.e2_branch", "string")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.site.e2_tag, "config.site.e2_tag", "string")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.site.e2_server, "config.site.e2_server", "string")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.site.e2_base, "config.site.e2_base", "string")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.site.default_extensions, "config.site.default_extensions", "table")
    if not rc then
        return false, re
    end

    rc, re = assert_type(config.servers, "config.servers", "table")
    if not rc then
        return false, re
    end

    return true
end

--- Cache for global config table.
local get_global_config_cache = false

--- Selects and read the global config file on first call, returns cached table
-- on further calls. Local tools call this function inside
-- collect_project_info(). Global tools must call this function after parsing
-- command line options.
-- @return Global config table on success, false on error.
-- @return Error object on failure.
function e2lib.get_global_config()
    local rc, re, cf, cf2, cf_path, home, root

    if get_global_config_cache then
        return get_global_config_cache
    end

    if type(e2lib.globals.e2config) == "string" then
        cf = e2lib.globals.e2config
    elseif type(e2lib.globals.osenv["E2_CONFIG"]) == "string" then
        cf = e2lib.globals.osenv["E2_CONFIG"]
    end

    -- e2config contains path to e2.conf. Optional, errors are ignored.
    root, re = e2lib.locate_project_root()
    if root then
        local e2_e2config = e2lib.join(root, ".e2/e2config")
        cf2, re = eio.file_read_line(e2_e2config)
    end

    if cf then
        cf_path = { cf }
    elseif cf2 then
        cf_path = { cf2 }
    else
        home = e2lib.globals.osenv["HOME"]
        cf_path = {
            -- this is ordered by priority
            string.format("%s/.e2/e2.conf-%s.%s.%s", home,
            buildconfig.MAJOR, buildconfig.MINOR, buildconfig.PATCHLEVEL),
            string.format("%s/.e2/e2.conf-%s.%s", home, buildconfig.MAJOR,
            buildconfig.MINOR),
            string.format("%s/.e2/e2.conf", home),
            string.format("%s/e2.conf-%s.%s.%s", buildconfig.SYSCONFDIR,
            buildconfig.MAJOR, buildconfig.MINOR, buildconfig.PATCHLEVEL),
            string.format("%s/e2.conf-%s.%s", buildconfig.SYSCONFDIR,
            buildconfig.MAJOR, buildconfig.MINOR),
            string.format("%s/e2.conf", buildconfig.SYSCONFDIR),
        }
    end
    -- use ipairs to keep the list entries ordered
    for _,path in ipairs(cf_path) do
        local data = nil

        e2lib.logf(4, "reading global config file: %s", path)
        local rc = e2lib.exists(path)
        if rc then
            e2lib.logf(4, "using global config file: %s", path)
            rc, re = e2lib.dofile2(path,
                { config = function(x) data = x end })
            if not rc then
                return false, re
            end
            if not data then
                return false, err.new("invalid configuration")
            end
            rc, re = verify_global_config(data)
            if not rc then
                return false, re
            end

            get_global_config_cache = strict.lock(data)
            return get_global_config_cache
        else
            e2lib.logf(4, "global config file does not exist: %s", path)
        end
    end
    return false, err.new("no config file available")
end

--- Read the local extension configuration. The extension configuration table
-- may be empty if the extension config does not exist or only contains
-- an empty configuration.
-- @param root Project root directory.
-- @return Extension configuration table (which may be empty), or false on error.
-- @return Error object on failure.
function e2lib.read_extension_config(root)
    local rc, re, e, extension_config

    extension_config = e2lib.join(root, e2lib.globals.extension_config)

    e = err.new("reading extension config file: %s", extension_config)

    rc = e2lib.exists(extension_config)
    if not rc then
        e2lib.warnf("WOTHER", "extension configuration not available")
        return {}
    end

    e2lib.logf(4, "reading extension file: %s", extension_config)

    local data = nil
    rc, re = e2lib.dofile2(extension_config,
        { extensions = function(x) data = x end })
    if not rc then
        return false, e:cat(re)
    end

    if type(data) ~= "table" then
        return false, e:cat("invalid extension configuration, missing table")
    end

    for _, entry in ipairs(data) do
        if type(entry) ~= "table" then
            return false, e:cat("extension entry is not a table")
        end

        rc, re = e2lib.vrfy_dict_exp_keys(entry, "extension config",
            { "ref", "name" })

        if not rc then
            return false, e:cat(re)
        end

        for _, field in ipairs({"ref", "name"}) do
            if entry[field] == nil then
                return false, e:cat("field '%s' is mandatory", field)
            end

            if type(entry[field]) ~= "string" then
                return false, e:cat("field '%s' takes a string value", field)
            end
        end
    end

    return data
end

--- Successively returns the file names in the directory.
-- @param path Directory path (string).
-- @param dotfiles If true, also return files starting with a '.'. Optional.
-- @param noerror If true, do not report any errors. Optional.
-- @return Iterator function, returning a string containing the filename,
--         or false and an err object on error. The iterator signals the
--         end of the list by returning nil.
function e2lib.directory(path, dotfiles, noerror)
    local dir, errstring = le2lib.directory(path, dotfiles)
    if not dir then
        if noerror then
            dir = {}
        else
            -- iterator that signals an error, once.
            local error_signaled = false

            return function ()
                if not error_signaled then
                    error_signaled = true
                    return false, err.new("reading directory `%s' failed: %s",
                        path, errstring)
                else
                    return nil
                end
            end
        end
    end

    table.sort(dir)
    local i = 1

    return function ()
        if i > #dir then
            return nil
        else
            i = i + 1
            return dir[i-1]
        end
    end
end

--- File descriptor config table vector. This vector simply holds file
-- descriptor config tables.
-- @table fdctv
-- @field 1..n File descriptor config table
-- @see fdct

--- File descriptor configuration table.
-- @table fdct
-- @field dup File descriptor(s) in the child process that should be replaced by
--            this configuration. Can be a single descriptor number or a
--            vector of descriptors (the later works with "writefunc" only).
-- @field istype Describes the type of fdct. Can be either "readfo" or
--               "writefunc". For details, check their respective pseudo-tables.
-- @see fdct_readfo
-- @see fdct_writefunc

--- File descriptor configuration table - readfo. This is an extension to
-- fdct for documentation purposes. It's not a separate table. When istype is
-- "readfo", the following field are expected in addition to ones in fdct.
-- The file object is used as an input to the child.
-- @table fdct_readfo
-- @field file Readable file object or file descriptor (number).
-- @see fdct

--- File descriptor configuration table - writefunc. This is an extension to
-- fdct for documentation purposes. It's not a separate table. When istype is
-- "writefunc", the following field are expected in addition to ones in fdct.
-- A function is called whenever output from dup is available or once a line
-- has been collected.
-- @table fdct_writefunc
-- @field linebuffer True to request line buffering, false otherwise.
-- @field callfn Function that is called when data is available.
--               Declared as "function (data)", no return value.
-- @field _p Private field, do not use.
-- @see fdct

--- Call a command. Forks a child and uses exec to directly run the command.
-- @param argv Argument vector to execute.
-- @param fdctv File descriptor config table vector. This determines
--              the file descriptor setup in parent and child. If none
--              is supplied, no changes to the file descriptors are done.
--              See fdctv and fdct tables for more detail.
-- @param workdir Working directory to start the new process in.
-- @param envdict Dictionary of (name, value) pairs to be added to the
--                environment of the new process. Existing variables are
--                overwritten.
-- @param nowait Optional - if true, return the PID instead of calling wait() to
--               get the return code.
-- @return Return code of the child is returned. It's the callers responsibility
--         to make sense of the value. If the return code is false, an error
--         within the function occurred and an error object is returned
-- @return Error object on failure.
-- @see fdctv
-- @see fdct
function e2lib.callcmd(argv, fdctv, workdir, envdict, nowait)

    -- To keep this large mess somewhat grokable, split into multiple functions.

    local function fd_parent_setup(fdctv)
        local rc, re
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" then
                rc, re = eio.pipe()
                if not rc then
                    return false, re
                end

                fdct._p = {}
                fdct._p.rfd = rc
                fdct._p.wfd = re
                fdct._p.buffer = ""

                rc, re = eio.cloexec(fdct._p.wfd)
                if not rc then
                    return false, re
                end

            elseif fdct.istype == "readfo" then
            else
                return false, err.new("while setting up parent file " ..
                    "descriptors: unknown istype (%q)", tostring(fdct.istype))
            end
        end

        return true
    end

    local function fd_child_setup(fdctv)
        local rc, re
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" then
                rc, re = eio.close(fdct._p.rfd)
                if not rc then
                    e2lib.abort(re)
                end

                local duptable
                if type(fdct.dup) == "table" then
                    duptable = fdct.dup
                else
                    duptable = {}
                    table.insert(duptable, fdct.dup)
                end

                for _,todup in ipairs(duptable) do
                    rc, re = eio.dup2(fdct._p.wfd, todup)
                    if not rc then
                        e2lib.abort(re)
                    end
                end
            elseif fdct.istype == "readfo" then
                local fd
                if type(fdct.file) == "number" then
                    fd = fdct.file
                else
                    fd = eio.fileno(fdct.file)
                end
                rc, re = eio.dup2(fd, fdct.dup)
                if not rc then
                    e2lib.abort(re)
                end
            end
        end
    end

    local function fd_parent_after_fork(fdctv)
        local rc, re
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" then
                rc, re = eio.close(fdct._p.wfd)
                if not rc then
                    return false, re
                end
            end
        end

        return true
    end

    local function fd_find_writefunc_by_readfd(fdctv, fd)
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" and fdct._p.rfd == fd then
                return fdct
            end
        end

        return false
    end

    local function fd_parent_poll(fdctv)

        local function fd_linebuffer(fdct, data)
            local linepos

            fdct._p.buffer = fdct._p.buffer..data
            repeat
                linepos = string.find(fdct._p.buffer, "\n")
                if linepos then
                    fdct.callfn(string.sub(fdct._p.buffer, 1, linepos))
                    fdct._p.buffer = string.sub(fdct._p.buffer, linepos + 1)
                end
            until not linepos
        end

        local function fd_linebuffer_final(fdct, data)
            if fdct.linebuffer and fdct._p.buffer ~= "" then
                fdct.callfn(fdct._p.buffer)
                fdct._p.buffer = ""
            end
        end

        local rc, re, fdvec, pollvec, fdvec, fdct

        fdvec = {}
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" then
                table.insert(fdvec, fdct._p.rfd)
            end
        end

        while #fdvec > 0 do
            pollvec, re = e2lib.poll(-1, fdvec)
            if not pollvec then
                return false, re
            elseif #pollvec == 0 then
                return false, err.new("poll timeout")
            end

            for _,ptab in ipairs(pollvec) do
                if ptab.POLLIN then
                    fdct = fd_find_writefunc_by_readfd(fdctv, ptab.fd)
                    if fdct then
                        local data, eno

                        data, re, eno = eio.read(fdct._p.rfd, 4096)
                        if not data then
                            if eno ~= errno.def2errnum("EINTR") then
                                return false, re
                            end
                            e2lib.logf(4, "poll loop read: fd=%d -> EINTR",
                                fdct._p.rfd)
                        elseif data ~= "" then
                            if fdct.linebuffer then
                                fd_linebuffer(fdct, data)
                            else
                                fdct.callfn(data)
                            end
                        end
                    end
                elseif ptab.POLLOUT then
                    return false, err.new("poll unexpectedly returned POLLOUT")
                else
                    -- Nothing to read, nothing to write, file descriptor
                    -- was closed.
                    --
                    -- Flush remaining buffers if linebuffer is enabled
                    -- and the last fread did not end with \n.
                    fdct = fd_find_writefunc_by_readfd(fdctv, ptab.fd)
                    if fdct then
                        fd_linebuffer_final(fdct)
                    end
                    table.remove(fdvec, ptab.fdvecpos)
                end
            end
        end

        return true
    end

    local function fd_parent_cleanup(fdctv)
        local rc, re
        for _,fdct in ipairs(fdctv) do
            if fdct.istype == "writefunc" then
                rc, re = eio.close(fdct._p.rfd)
                if not rc then
                    return false, re
                end
            end
        end

        return true
    end

    local function sync_pipe_setup()
        local sync_pipes = {}

        sync_pipes[1], sync_pipes[2] = eio.pipe()
        if not sync_pipes[1] then
            return false, sync_pipes[2]
        end

        sync_pipes[3], sync_pipes[4] = eio.pipe()
        if not sync_pipes[3] then
            return false, sync_pipes[4]
        end

        return sync_pipes
    end

    local function sync_child(sync_pipes)
        local rc, re

        -- close unused ends early
        for _,fd in ipairs({2, 3}) do
            rc, re = eio.close(sync_pipes[fd])
            if not rc then
                return false, re
            end
        end

        -- ping parent
        rc, re = eio.write(sync_pipes[4], "c")
        if not rc then
            return false, re
        elseif rc ~= 1 then
            return false, err.new("wrote %d bytes instead of 1", rc)
        end

        -- wait for parent
        rc, re = eio.read(sync_pipes[1], 1)
        if not rc then
            return false, re
        elseif rc ~= "p" then
            return false, err.new("unexpected reply from parent: %q", rc)
        end

        -- cleanup
        for _,fd in ipairs({4, 1}) do
            rc, re = eio.close(sync_pipes[fd])
            if not rc then
                return false, re
            end
        end

        return true
    end

    local function sync_parent(sync_pipes)
        local rc, re

        -- close unused ends
        -- note: don't start reading/writing before all unused ends
        -- are closed. If anything goes wrong with the child, we will
        -- otherwise block forever trying to read from ourselves.
        -- comment also applies to sync_child()
        for _,fd in ipairs({1, 4}) do
            rc, re = eio.close(sync_pipes[fd])
            if not rc then
                return false, re
            end
        end

        -- ping child
        rc, re = eio.write(sync_pipes[2], "p")
        if not rc then
            return false, re
        elseif rc ~= 1 then
            return false, err.new("wrote %d bytes instead of 1", rc)
        end

        -- wait for child
        rc, re = eio.read(sync_pipes[3], 1)
        if not rc then
            return false, re
        elseif rc ~= "c" then
            return false, err.new("unexpected reply from child: %q", rc)
        end

        -- cleanup
        for _,fd in ipairs({2, 3}) do
            rc, re = eio.close(sync_pipes[fd])
            if not rc then
                return false, re
            end
        end

        return true
    end

    -- start of callcmd() proper

    local rc, re, pid, sig
    local sync_pipes = {}

    e2lib.logf(4, "calling %q in %q", table.concat(argv, " "),
        workdir or "$PWD")

    rc, re = fd_parent_setup(fdctv)
    if not rc then
        return false, re
    end

    sync_pipes, re = sync_pipe_setup()
    if not sync_pipes then
        return false, re
    end

    pid, re = e2lib.fork()
    if not pid then
        return false, re
    elseif pid == 0 then
        -- disable debug logging to console in the child because it
        -- potentially mixes with the output of the command
        e2lib.setlog(4, false)

        e2lib.signal_reset()

        fd_child_setup(fdctv)

        if workdir then
            rc, re = e2lib.chdir(workdir)
            if not rc then
                e2lib.abort(re)
            end
        end

        if envdict then
            for var,val in pairs(envdict) do
                rc, re = e2lib.setenv(var, val, true)
                if not rc then
                    e2lib.abort(re)
                end
            end
        end

        rc, re = sync_child(sync_pipes)
        if not rc then
            e2lib.abort(re)
        end

        rc, re = e2lib.execvp(argv[1], argv)
        e2lib.abort(re)
    end

    rc, re = fd_parent_after_fork(fdctv)
    if not rc then
        return false, re
    end

    rc, re = sync_parent(sync_pipes)
    if not rc then
        return false, re
    end

    rc, re = fd_parent_poll(fdctv)
    if not rc then
        return false, re
    end

    rc, re = fd_parent_cleanup(fdctv)
    if not rc then
        return false, re
    end

    if nowait == true then
        return pid
    end

    e2lib.logf(4, "waiting for command %s pid %d", table.concat(argv, " "), pid)
    rc, re, sig = e2lib.wait(pid)
    if not rc then
        return false, re
    end

    e2lib.logf(4, "command %q pid %d exit %d signal %d",
        table.concat(argv, " "), re, rc, sig or 0)

    return rc
end

--- Call a command with stdin redirected to /dev/null, stdout and stderr
-- are captured  via a pipe.
-- @param cmd Argument vector holding the command.
-- @param capture Function taking a string argument. Called on every line of
--                stdout and stderr output captured from the program.
-- @param workdir Workdir of the command. Optional.
-- @param envdict Dictionary to add to the environment of the command. Optional.
-- @return Return status code of the command (number) or false on error.
-- @return Error object on failure.
-- @see callcmd
function e2lib.callcmd_capture(cmd, capture, workdir, envdict)
    local rc, re, devnull

    local function autocapture(msg)
        e2lib.log(3, msg)
    end

    capture = capture or autocapture

    devnull, re = eio.fopen("/dev/null", "r")
    if not devnull then
        return false, re
    end

    local fdctv = {
        { dup = eio.STDIN, istype = "readfo", file = devnull },
        { dup = { [1] = eio.STDOUT, [2] = eio.STDERR },  istype = "writefunc",
            linebuffer = true, callfn = capture },
    }

    rc, re = e2lib.callcmd(cmd, fdctv, workdir, envdict)
    if not rc then
        eio.fclose(devnull)
        return false, re
    end

    eio.fclose(devnull)
    return rc
end

--- Call command with stdin redirected to /dev/null and stderr/stdout
-- independently redirected to callback functions. Note that unlike
-- callcmd_capture(), the output will not necessarily appear in order at the
-- callbacks.
-- @param cmd Argument vector holding command and args.
-- @param outfn Callback for stdout.
-- @param errfn Callback for stderr.
-- @param workdir Optional working directory
-- @param envdict Optional environment dictionary.
-- @return Numeric return code of program or false on some errors.
-- @return Error object on failure.
function e2lib.callcmd_stdout_stderr(cmd, outfn, errfn, workdir, envdict)
    assertIsTable(cmd)
    assertIsFunction(outfn)
    assertIsFunction(errfn)
    assert(workdir == nil or type(workdir) == "string")
    assert(envdict == nil or type(workdir) == "table")

    local rc, re, devnull

    devnull, re = eio.fopen("/dev/null", "r")
    if not devnull then
        return false, re
    end

    local fdctv = {
        { dup = eio.STDIN, istype = "readfo", file = devnull },
        { dup = eio.STDOUT, istype = "writefunc", callfn = outfn },
        { dup = eio.STDERR, istype = "writefunc", callfn = errfn },
    }

    rc, re = e2lib.callcmd(cmd, fdctv, workdir, envdict)
    if not rc then
        eio.fclose(devnull)
        return false, re
    end

    eio.fclose(devnull)
    return rc
end

--- Call a command, log its output and catch the last lines for error reporting.
-- See callcmd() for details.
-- @param cmd Argument vector holding the command.
-- @param workdir Workdir of the command. Optional.
-- @param envdict Dictionary to add to the environment of the command. Optional.
-- @return Return code of the command (number), or false on error.
-- @return Error object containing command line and last lines of output. It's
--         the callers responsibility to determine whether an error occured
--         based on the return code. If the return code is false, an error
--         within the function occured and a normal error object is returned.
-- @see callcmd
function e2lib.callcmd_log(cmd, workdir, envdict)
    local e = err.new("command %q failed", table.concat(cmd, " "))
    local fifo = {}

    local function logto(msg)
        e2lib.log(3, msg)

        if msg ~= "" then
            if #fifo > 4 then -- keep the last n lines.
                table.remove(fifo, 1)
            end
            table.insert(fifo, msg)
        end
    end

    local rc, re = e2lib.callcmd_capture(cmd, logto, workdir, envdict)
    if not rc then
        return false, e:cat(re)
    end

    if #fifo == 0 then
        table.insert(fifo, "command failed silently, no output captured")
    end

    for _,v in ipairs(fifo) do
        e:append("%s", v)
    end

    return rc, e
end

--- Generate a new table populated with all the safe Lua "string" functions.
-- The intended use is to generate a now string table for each protected
-- environment, so that no information can be passed through string, or worse,
-- real string functions can be overwritten and thus escape the protected env.
-- @return New "string" replacement package.
function e2lib.safe_string_table()
    local safefn = {
        "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower",
        "match", "rep", "reverse", "sub", "upper"
    }
    -- unsafe: dump

    local st = {}

    for _,name in ipairs(safefn) do
        assert(string[name])
        st[name] = string[name]
    end

    return st
end

--- Executes Lua code loaded from path.
--@param path Filename to load lua code from (string).
--@param gtable Environment (table) that is used instead of the global _G.
--              If gtable has no metatable, the default is to reject
--              __index and __newindex access.
--@return True on success, false on error.
--@return Error object on failure.
function e2lib.dofile2(path, gtable)
    local e = err.new("error loading config file: %s", path)
    local chunk, msg = loadfile(path)
    if not chunk then
        return false, e:cat(msg)
    end

    --for k,v in pairs(gtable) do
    --  e2lib.logf(1, "[%s] = %s", tostring(k), tostring(v))
    --end

    local function checkread(t, k)
        local x = rawget(t, k)
        if x then
            return x
        else
            error(string.format(
                "%s: attempt to reference undefined global variable '%s'",
                path, tostring(k)), 0)
        end
    end

    local function checkwrite(t, k, v)
        error(string.format("%s: attempt to set new global variable `%s' to %s",
            path, tostring(k), tostring(v)), 0)
    end

    if not getmetatable(gtable) then
        setmetatable(gtable, { __newindex = checkwrite, __index = checkread })
    end

    setfenv(chunk, gtable)
    local s, msg = pcall(chunk)
    if not s then
        return false, e:cat(msg)
    end
    return true, nil
end

--- Locates the root directory of the current project. If path is not given,
-- then the current working directory is taken as the base directory from
-- where to start.
-- @param path Project directory (string) or nil.
-- @return Absolute base project directory or false on error.
-- @return Error object on failure.
function e2lib.locate_project_root(path)
    local rc, re
    local e = err.new("locating project root failed")
    local save_path

    save_path, re = e2lib.cwd()
    if not save_path then
        return false, e:cat(re)
    end

    if path then
        rc, re = e2lib.chdir(path)
        if not rc then
            return false, e:cat(re)
        end
        path, re = e2lib.cwd() -- make it absolute
        if not path then
            return false, e:cat(re)
        end
        rc, re = e2lib.chdir(save_path)
        if not rc then
            return false, e:cat(re)
        end
    else
        path = save_path
    end

    while true do
        if e2lib.isdir(e2lib.join(path, ".e2")) then
            return path
        end

        if path == "/" or path == "." then
            break
        end

        path = e2lib.dirname(path)
    end

    return false, e:cat("not in a project directory")
end

--- Checks whether the tool is an existing global e2factory tool. Note that
-- there is third class of binaries living in BINDIR, which are not considered
-- global (in a tool sense).
-- @param tool Tool name such as 'e2-create-project', 'e2-build' etc.
-- @return True or false.
-- @return Error object when false.
-- @see islocaltool
function e2lib.isglobaltool(tool)
    local tool = e2lib.join(buildconfig.TOOLDIR, tool)
    if e2lib.isfile(tool) then
        return true
    end

    return false, err.new('global tool "%s" does not exists', tool)
end

--- Check whether tool is an existing local e2factory tool.
-- Only works in a project context.
-- @param tool Tool name such as 'e2-install-e2', 'e2-build' etc.
-- @return True or false
-- @return Error object when false.
-- @see isglobaltool
function e2lib.islocaltool(tool)
    local dir, re = e2lib.locate_project_root()
    if not dir then
        return false, re
    end

    local tool = e2lib.join(dir, ".e2/bin", tool)
    if e2lib.isfile(tool) then
        return tool
    end

    return false, err.new('local tool "%s" does not exist', tool)
end

--- Parse e2version file.
-- @return Table containing tag and branch. False on error.
-- @return Error object on failure.
function e2lib.parse_e2versionfile(filename)
    local f, e, rc, re, l

    f, re = eio.fopen(filename, "r")
    if not f then
        e = err.new("can't open e2 version file: %s", filename)
        return false, e:cat(re)
    end

    l, re = eio.readline(f)
    eio.fclose(f)
    if not l then
        e = err.new("can't parse e2 version file: %s", filename)
        return false, e:cat(re)
    end

    local match = l:gmatch("[^%s]+")

    local version_table = {}
    version_table.branch = match()
    if not version_table.branch then
        return false, err.new("invalid branch name `%s' in e2 version file %s",
            l, filename)
    end

    version_table.tag = match()
    if not version_table.tag then
        return false, err.new("invalid tag name `%s' in e2 version file %s",
            l, filename)
    end

    e2lib.logf(4, "using e2 branch %s tag %s",
        version_table.branch, version_table.tag)

    return strict.lock(version_table)
end

--- Create a temporary file.
-- The template string is passed to the mktemp tool, which replaces
-- trailing X characters by some random string to create a unique name.
-- @param template string: template name (optional)
-- @return Name of the file or false on error.
-- @return Error object on failure.
function e2lib.mktempfile(template)
    local rc, re, errstring, tmpfile, tmpfd, tmpfo

    if not template then
        template = string.format("%s/e2tmp.%d.XXXXXX", e2lib.globals.tmpdir,
            e2lib.getpid())
    end

    rc, errstring, tmpfile, tmpfd = le2lib.mkstemp(template)
    if not rc then
        return false, err.new("could not create temporary file: %s", errstring)
    end

    -- Currently we do not use the file descriptor, close it.
    tmpfo, re = eio.fdopen(tmpfd, "w")
    if not tmpfo then
        return false, re
    end

    rc, re = eio.fclose(tmpfo)
    if not rc then
        return false, re
    end

    -- register tmp for removing with rmtempfiles() later on
    table.insert(e2lib.globals.tmpfiles, tmpfile)
    e2lib.logf(4, "e2lib.mktempfile: created %s", tmpfile)

    return tmpfile
end

--- Delete the temporary file and remove it from the builtin list of
-- temporary files.
-- @param tmpfile File name to remove (string).
function e2lib.rmtempfile(tmpfile)
    local rc, re

    for i,v in ipairs(e2lib.globals.tmpfiles) do
        if v == tmpfile then
            table.remove(e2lib.globals.tmpfiles, i)
            e2lib.logf(4, "removing temporary file: %s", tmpfile)
            if e2lib.exists(tmpfile) then
                rc, re = e2lib.unlink(tmpfile)
                if not rc then
                    e2lib.warnf(3, "could not remove tmpfile %q", tmpfile)
                end
            end
        end
    end
end

--- Create a unique temporary directory.
-- The template string must contain at least six trailing "X" characters
-- which are replaced with a random and unique string.
-- @param template Template string or nil for the default.
-- @return Name of the directory (string) or false on error.
-- @return Error object on failure.
function e2lib.mktempdir(template)
    local rc, errstring, tmpdir
    if not template then
        template = string.format("%s/e2tmp.%d.XXXXXX", e2lib.globals.tmpdir,
            e2lib.getpid())
    end

    rc, errstring, tmpdir = le2lib.mkdtemp(template)
    if not rc then
        return false, err.new("could not create temporary directory: %s",
            errstring)
    end

    -- register tmpdir for removal with rmtempdirs() later on
    table.insert(e2lib.globals.tmpdirs, tmpdir)
    e2lib.logf(4, "e2lib.mktempdir: created %q", tmpdir)

    return tmpdir
end

--- Recursively delete the temporary directory and remove it from the builtin
-- list of temporary directories.
-- @param tmpdir Directory name to remove (string).
function e2lib.rmtempdir(tmpdir)
    local rc, re

    for i,v in ipairs(e2lib.globals.tmpdirs) do
        if v == tmpdir then
            table.remove(e2lib.globals.tmpdirs, i)
            e2lib.logf(4, "removing temporary directory: %s", tmpdir)
            if e2lib.exists(tmpdir) then
                rc, re = e2lib.unlink_recursive(tmpdir)
                if not rc then
                    e2lib.warnf(3, "could not remove tmpdir %q", tmpdir)
                end
            end
        end
    end
end

--- remove temporary directories registered with mktempdir()
-- This function does not support error checking and is intended to be
-- called from the finish() function.
function e2lib.rmtempdirs()
    while #e2lib.globals.tmpdirs > 0 do
        e2lib.rmtempdir(e2lib.globals.tmpdirs[1])
    end
end

--- remove temporary files registered with mktempfile()
-- This function does not support error checking and is intended to be
-- called from the finish() function.
function e2lib.rmtempfiles()
    while #e2lib.globals.tmpfiles > 0 do
        e2lib.rmtempfile(e2lib.globals.tmpfiles[1])
    end
end

--- Remove regular and special files, except dirs.
-- @param pathname Path to file (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.unlink(pathname)
    local rc, errstring = le2lib.unlink(pathname)

    if not rc then
        return false, err.new("could not remove file %s: %s",
            pathname, errstring)
    end

    return true
end

--- Remove directories and files recursively.
-- @param pathname File or directory to delete.
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.unlink_recursive(pathname)
    local de, rc, re
    local filepath

    de, re = e2lib.lstat(pathname) -- do not follow links
    if not de then
        return false, re
    end

    if de.type == "directory" then
        for file, re in e2lib.directory(pathname, true) do
            if not file then
                return false, re
            end

            filepath = e2lib.join(pathname, file)

            de, re = e2lib.lstat(filepath) -- do not follow links
            if not de then
                return false, re
            end

            if de.type == "directory" then
                rc, re = e2lib.unlink_recursive(filepath)
                if not rc then
                    return false, re
                end
            else
                rc, re = e2lib.unlink(filepath)
                if not rc then
                    return false, re
                end
            end
        end

        rc, re = e2lib.rmdir(pathname)
        if not rc then
            return false, re
        end
    else
        rc, re = e2lib.unlink(pathname)
        if not rc then
            return false, re
        end
    end

    return true
end

--- Remove single empty directory.
-- @param dir Directory name (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.rmdir(dir)
    local rc, errstring = le2lib.rmdir(dir)

    if not rc then
        return false, err.new("could not remove directory %s: %s",
            dir, errstring)
    end

    return true
end

--- Parse a mode string in the form ugo+rwx, 755 etc.
-- @param modestring Mode string.
-- @return Numeric mode or false on error.
-- @return Error object on failure.
function e2lib.parse_mode(modestring)
    --- check for with octal numbers
    if tonumber(modestring) ~= nil then
        if string.len(modestring) == 3 then
            local out = 0
            local index = 0
            for mode in string.gmatch(modestring, "%S") do
                if tonumber(mode) > 7 then
                    return false, err.new("cannot parse mode string '%s': mode is a number between 0 and 7", tostring(modestring))
                end
                out = out + tonumber(mode) * 8^(2 - index)
                index = index + 1
            end
            return out
        else
            return false, err.new("cannot parse mode string '%s': octal string is exactly 3 characters long", tostring(modestring))
        end
    end

    --- VARIABLE SETUP
    local perm = { -- w      r      x
            user =   {w = 0, r = 0, x = 0}, -- u
            group =  {w = 0, r = 0, x = 0}, -- g
            other =  {w = 0, r = 0, x = 0}, -- o
    }
    local class_name = {}
    local func
    local operator = ""

    --- state functions
    -- state function for permissions
    local function permissions(char)
        if char == "X" then
            char = "x" -- cast special Executable to normal executable for calculation reasons
        end
        if char == "," then
            return "reset"
        elseif char ~= "w" and char ~= "r" and char ~= "x" then
            return false, err.new("cannot parse mode string '%s': unknown permission mode: %s", modestring, char)
        end

        for ow in pairs(class_name) do
            if operator == "+" then
                perm[ow][char] = 1
            elseif operator == "-" then
                perm[ow][char] = 0
            elseif operator == "=" then
                perm[ow][char] = 1
            else
                return false, err.new("cannot parse mode string '%s': unknown operator in permission evaluation: %s", modestring, char)
            end
        end
    end

    -- state function for operators
    local function op(char)
        if char == "=" or char == "-" or char == "+" then
            func = permissions
            operator = char
            if char == "=" then
                -- nulling the given classs.
                -- If we do this, we only need to set the given modes to 1 later
                for ow in pairs(class_name) do
                    for p in pairs(perm[ow]) do
                        perm[ow][p] = 0
                    end
                end
            end
        else
            return false, err.new("cannot parse mode string '%s': unknown operator: %s", modestring, char)
        end
    end

    -- state function for class
    local function class(char)
        if char == "u" then
            class_name["user"] = 1
        elseif char == "g" then
            class_name["group"] = 1
        elseif char == "o" then
            class_name["other"] = 1
        elseif char == "a" then
            class_name["user"] = 1
            class_name["group"] = 1
            class_name["other"] = 1
        else
            -- calculate size of user_name table
            local table_size = 0
            for _ in pairs(class_name) do
                table_size = table_size + 1
            end
            if table_size == 0 then -- if no entry is in user_name, string is invalid
                return false, err.new("cannot parse mode string '%s': no valid class given", modestring)
            end
            return op(char) -- pass char to actual current state, which is 'operator'
        end
    end
    func = class

    --- evaluting the string
    for c in string.gmatch(modestring, "%S") do
        local re, re_err
        re, re_err = func(c) -- the func(c) call does the most magic here
        if re ~= nil then
            if re == "reset" then
                class_name = {}
                operator = ""
                func = class
            end
            if (not re) and re_err then
                return false, re_err
            end
        end
    end

    -- calculate classs permissions as decimals
    local out_other =  perm["other"]["r"] * 4 + perm["other"]["w"] * 2 + perm["other"]["x"]
    local out_group = (perm["group"]["r"] * 4 + perm["group"]["w"] * 2 + perm["group"]["x"]) * 8
    local out_user =  (perm["user"]["r"]  * 4 + perm["user"]["w"]  * 2 + perm["user"]["x"]) * 64
    return out_user + out_group + out_other
end

--- Create a single directory.
-- @param dir Directory name (string).
-- @param mode Numeric mode for directory creation (umask restrictions apply).
-- @return True on success, false on error.
-- @return Error object on failure.
-- @return Errno (number) on failure.
function e2lib.mkdir(dir, mode)
    local re

    if mode == nil then
        mode, re = e2lib.parse_mode("777")
        if not mode then
            return false, re
        end
    end

    local rc, errstring, errnum = le2lib.mkdir(dir, mode)

    if not rc then
        return false, err.ecset(
            err.new("cannot create directory %q: %s", dir, errstring),
            errno.errnum2def(errnum))
    end

    return true
end

--- Create zero or more directories making up a path. Some or all directories
-- in the path may already exist.
-- @param path Path name (string).
-- @param mode Numeric mode for directory creation (umask restrictions apply).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.mkdir_recursive(path, mode)
    local dirs = e2lib.parentdirs(path)
    local rc, re, errnum, eexist

    if mode == nil then
        mode, re = e2lib.parse_mode("777")
        if not mode then
            return false, re
        end
    end

    trace.filter_function("e2lib", "mkdir")
    for _,dir in ipairs(dirs) do
        rc, re, errnum = e2lib.mkdir(dir, mode)
        if not rc and not err.eccmp(re, "EEXIST") then
            trace.filter_function_remove("e2lib", "mkdir")
            return false, re
        end
    end
    trace.filter_function_remove("e2lib", "mkdir")

    return true
end

--- Call a tool with an argument vector.
-- @param tool Tool name as registered in the tools library (string).
-- @param argv Vector of arguments, escaping is handled by the function
--             (table of strings).
-- @param workdir Working directory of tool (optional).
-- @param envdict Environment dictionary of tool (optional).
-- @return True when the tool returned 0, false on error.
-- @return Error object on failure.
-- @see callcmd_log
function e2lib.call_tool_argv(tool, argv, workdir, envdict)
    local rc, re, cmd, flags, call

    cmd, re = tools.get_tool_flags_argv(tool)
    if not cmd then
        return false, re
    end

    for _,arg in ipairs(argv) do
        table.insert(cmd, arg)
    end

    rc, re = e2lib.callcmd_log(cmd, workdir, envdict)
    if not rc or rc ~= 0 then
        return false, re
    end

    return true
end

--- Change permission mode of file.
-- @param path Path to file.
-- @param mode Permission mode, may be "644" or "ugo+rwx" (string).
-- @return True on success, false on error.
-- @return Error object on failure.
function e2lib.chmod(path, mode)
    local rc, re, errstring, pmode

    pmode, re = e2lib.parse_mode(mode)
    if not pmode then
        return false, re
    end

    rc, errstring = le2lib.chmod(path, pmode)
    if not rc then
        return false, err.new("changing permission mode on %q failed: %s",
            path, errstring)
    end

    return true
end

--- Close all file descriptors equal or larger than "fd".
-- @param fd file descriptor (number)
-- @return True on success, false on error
-- @return Error object on failure.
-- @raise Error on invalid input.
function e2lib.closefrom(fd)
    local rc, errstring

    rc, errstring = le2lib.closefrom(fd)
    if not rc then
        return false, err.new("closefrom(%d) failed: %s",
            tonumber(fd), errstring)
    end

    return true
end

--- Call the mv command. For more defails see mv(1).
-- @param src string: source name
-- @param dst string: destination name
-- @return bool
-- @return the last line of captured output
function e2lib.mv(src, dst)
    assert(type(src) == "string" and type(dst) == "string")
    assert(string.len(src) > 0 and string.len(dst) > 0)

    return e2lib.call_tool_argv("mv", { src, dst })
end

--- Call the cp command. For more details, see cp(1)
-- @param src string: source name
-- @param dst string: destination name
-- @param recursive True enables recursive copying. The default is false.
-- @return bool
-- @return the last line of captured output
function e2lib.cp(src, dst, recursive)
    local argv

    argv = { src, dst }
    if recursive then
        table.insert(argv, 1, "-R")
    end

    return e2lib.call_tool_argv("cp", argv)
end

--- call the curl command
-- @param argv table: argument vector
-- @return bool
-- @return an error object on failure
function e2lib.curl(argv)
    assert(type(argv) == "table")

    return e2lib.call_tool_argv("curl", argv)
end

--- Run command on remote server via SSH.
-- @param u URL object pointing to the remote server.
-- @param argv Command vector to run on the remote server.
-- @return True on success, false on error.
-- @return Error object on failure.
-- @return Captured standard output of the command as a string.
function e2lib.ssh_remote_cmd(u, argv)
    local command, rc, re, e, flags, args, stdout, stderr, devnull, fdctv

    command, re = tools.get_tool_flags_argv("ssh")
    if not command then
        return false, re
    end

    if u.pass then
        return false, err.new("ssh_remote_cmd does not support password URL's")
    end

    if u.port then
        table.insert(command, "-p")
        table.insert(command, u.port)
    end

    if u.user then
        table.insert(command, "-l")
        table.insert(command, u.user)
    end

    if not u.servername then
        return false,
            err.new("ssh_remote_cmd: no server name in URL %q", u.url)
    end
    table.insert(command, u.servername)

    args = {}
    for i, arg in ipairs(argv) do
        table.insert(args, e2lib.shquote(arg))
    end
    table.insert(command, table.concat(args, " "))

    stdout = {}
    stderr = {}
    local function capture_stdout(data)
        table.insert(stdout, data)
    end

    local function capture_stderr(data)
        table.insert(stderr, data)
    end

    rc, re = e2lib.callcmd_stdout_stderr(command, capture_stdout,
        capture_stderr)
    if not rc then
        return false, re
    end

    if rc ~= 0 then
        e = err.new("%q returned with exit code %d:",
            table.concat(command, " "), rc)
        for i = #stderr-3,#stderr do
            if stderr[i] then
                e:append("%s", stderr[i])
            end
        end

        return false, e
    end

    return true, nil, table.concat(stdout)
end

--- call the scp command
-- @param argv table: argument vector
-- @return bool
-- @return an error object on failure
function e2lib.scp(argv)
    assert(type(argv) == "table")

    return e2lib.call_tool_argv("scp", argv)
end

--- call the rsync command
-- @param argv table: vector filled with arguments
-- @return bool
-- @return an error object on failure
function e2lib.rsync(argv)
    assert(type(argv) == "table")

    return e2lib.call_tool_argv("rsync", argv)
end

--- call the gzip command
-- @param argv table: argument vector
-- @return bool
-- @return the last line of captured output
function e2lib.gzip(argv)
    assert(type(argv) == "table")

    return e2lib.call_tool_argv("gzip", argv)
end

--- check if dir is a directory
-- @param dir string: path
-- @return bool
function e2lib.isdir(dir)
    local t = e2lib.stat(dir)
    if t and t.type == "directory" then
        return true
    end

    return false
end

--- check if path is a file
-- @param dir string: path
-- @return bool
function e2lib.isfile(path)
    local t = e2lib.stat(path)
    if t and t.type == "regular" then
        return true
    end
    return false
end

--- call the e2-su-2.2 command
-- @param argv table: argument vector
-- @return bool
function e2lib.e2_su_2_2(argv)
    assert(type(argv) == "table")
    local rc, re

    rc, re = e2lib.get_global_config()
    if not rc then
        return false, re
    end

    rc, re = tools.enabled("sudo")
    if rc then
        local cmd

        cmd, re = tools.get_tool_flags_argv("e2-su-2.2")
        if not cmd then
            return false, re
        end

        for _,arg in ipairs(argv) do
            table.insert(cmd, arg)
        end

        table.insert(cmd, 1, "--")

        return e2lib.call_tool_argv("sudo", cmd)
    else
        return e2lib.call_tool_argv("e2-su-2.2", argv)
    end
end

--- call the tar command
-- @param argv table: argument vector
-- @return bool
function e2lib.tar(argv)
    assert(type(argv) == "table")

    return e2lib.call_tool_argv("tar", argv)
end

--- Get machine system architecture.
-- @return Machine hardware name as a string, false on error.
-- @return Error object on failure.
function e2lib.uname_machine()
    local machine, errstring = le2lib.uname_machine()

    if not machine then
        return false, err.new("getting host system architecture failed: %s",
            errstring)
    end

    return machine
end

--- Return a table of parent directories going deeper one directory at a time.
-- Example: "/foo/", "/foo/bar", ...
-- @param path string: path
-- @return a table of parent directories, including path.
function e2lib.parentdirs(path)
    local start = 2
    local stop
    local t = {}
    local parent

    while stop ~= path:len() do
        stop = path:find("/", start)
        if not stop then
            stop = path:len()
        end
        start = stop + 1
        parent = path:sub(1, stop)
        table.insert(t, parent)
    end
    return t
end

--- Parse a server:location string, taking a default server into account.
-- @param serverloc string: the string to parse
-- @param default_server Default server name used when serverloc contains none.
-- @return Locked server location table, false on error
-- @return Error object on failure.
-- @see server_location
function e2lib.parse_server_location(serverloc, default_server)
    assert(type(serverloc) == 'string' and type(default_server) == 'string')

    --- Server location table.
    -- @table server_location
    -- @field server Server name, defaults to default_server if not supplied.
    -- @field location Path location relative to the server.
    -- @see parse_server_location
    local sl = {}

    sl.server, sl.location = serverloc:match("(%S+):(%S+)")
    if not (sl.server and sl.location) then
        sl.location = serverloc:match("(%S+)")
        if not (sl.location and default_server) then
            return false, err.new("can't parse location in %q", serverloc)
        end
        sl.server = default_server
    end

    if sl.location:match("[.][.]") or
        sl.location:match("^/") then
        return false, err.new("invalid location: %q", serverloc)
    end

    return strict.lock(sl)
end

--- replace format elements, according to the table
-- @param s string: the string to work on
-- @param t table: a table of key-value pairs
-- @return string
function e2lib.format_replace(s, t)
    -- t has the format { f="foo" } to replace %f by foo inside the string
    -- %% is automatically replaced by %
    local start = 1
    while true do
        local p = s:find("%%", start)
        if not p then
            break
        end
        t["%"] = "%"
        for x,y in pairs(t) do
            if s:sub(p+1, p+1) == x then
                s = s:sub(1, p-1) .. y .. s:sub(p+2, #s)
                start = p + #y
                break
            end
        end
        start = start + 1
    end
    return s
end

--- change directory
-- @param path
-- @return bool
-- @return an error object on failure
function e2lib.chdir(path)
    local rc, re
    rc, re = le2lib.chdir(path)
    if not rc then
        return false, err.new("chdir %s failed: %s", path, re)
    end
    return true, nil
end

--- align strings
-- @param columns screen width
-- @param align1 column to align string1to
-- @param string1 first string
-- @param align2 column to align string2 to
-- @param string2 second string
function e2lib.align(columns, align1, string1, align2, string2)
    local lines = 1
    if align2 + #string2 > columns then
        -- try to move string2 to the left first
        align2 = columns - #string2
    end
    if align1 + #string1 + #string2 > columns then
        -- split into two lines
        lines = 2
    end
    local s
    if lines == 1 then
        s = string.rep(" ", align1) .. string1 ..
        string.rep(" ", align2 - #string1 - align1) .. string2
    else
        s = string.rep(" ", align1) .. string1 .. "\n" ..
        string.rep(" ", align2) .. string2
    end
    return s
end

--- Verify that type t is a string with a minimal length.
-- @param t Variable to verify.
-- @param name Name of the variable in error message.
-- @param minlen Minimum length of t (default=1).
-- @return True if string of minimal length, false if not.
-- @return Error object if false.
function e2lib.vrfy_string_len(t, name, minlen)
    assert(type(name) == "string", "vrfy_string_len: name must be a string")

    if type(minlen) ~= "number" then
        minlen = 1
    end

    if type(t) ~= "string" then
        return false, err.new("%s is not a string (found %s)", name, type(t))
    end

    if string.len(t) < minlen then
        return false,
            err.new("%s is too short (minimum length %d)", name, minlen)
    end

    return true
end

--- Verify that a dictionary contains only expected keys. Does not check
-- for missing expected keys.
-- @param t Variable to verify
-- @param name Name of t in error message.
-- @param ekeyvec Expected key vector
-- @return True if t is a table and contains only the expected keys
-- @return Error object if false.
function e2lib.vrfy_dict_exp_keys(t, name, ekeyvec)
    assert(type(name) == "string", "vrfy_dict_exp_keys: name must be a string")
    assert(type(ekeyvec) == "table", "vrfy_dict_exp_keys: ekeyvec not a table")

    if type(t) ~= "table" then
        return false, err.new("%s is not a table (found %s)", name, type(t))
    end

    local lookup = {}
    for _,v in ipairs(ekeyvec) do
        lookup[v] = true
    end

    local e = nil
    for k,_ in pairs(t) do
        if not lookup[k] then
            if e then
                e:append("unexpected key %q in %s", tostring(k), name)
            else
                e = err.new("unexpected key %q in %s", tostring(k), name)
            end
        end
    end

    if e then
        return false, e
    end

    return true
end

--- Verify that a given table only contains numeric indicies, with no weird
-- holes or anything that throws ipairs() off.
-- @param t Table to verify
-- @param name Name of the table for error message.
-- @return True if t is a vector, false otherwise
-- @return Error object if false.
function e2lib.vrfy_vector(t, name)
    assert(type(name) == "string", "vrfy_vector: name must be a string")

    local i = 0

    if type(t) ~= "table" then
        return false, err.new("%s is not a table (found %s)", name,
            type(t))
    end

    for k,_ in pairs(t) do
        i = i + 1

        if type(k) ~= "number" then
            return false, err.new("table %s contains non-numeric index %q",
                name, tostring(k))
        end

        if k < 1 then
            return false, err.new("table %s index %q out of range", name,
                tostring(k))
        end
    end

    if i ~= #t then
        return false, err.new("table %s index has holes", name)
    end

    return true
end

--- Check (and optionally modify) that a table is a list of strings
-- @param t Table to check.
-- @param name Name of the table, for error message.
-- @param unique bool: require strings to be unique
-- @param unify bool: remove duplicate strings
-- @return True if the t is a list of strings, false otherwise.
-- @return Error object if false
function e2lib.vrfy_listofstrings(t, name, unique, unify)
    assert(type(unique) == "boolean", "vrfy_listofstrings: unique not a boolean")
    assert(type(unify) == "boolean", "vrfy_listofstrings: unify not a boolean")

    local ok, re

    ok, re = e2lib.vrfy_vector(t, name)
    if not ok then
        return false, re
    end


    local values = {}
    local unified = {}

    for i,s in ipairs(t) do
        if type(s) ~= "string" then
            return false, err.new("table %s contains non-string value %q",
                name, tostring(s))
        end

        if unique and values[s] then
            return false, err.new("table %s has non-unique value: %q", name, s)
        end

        if unify and not values[s] then
            table.insert(unified, s)
        end
        values[s] = true
    end

    if unify then
        while #t > 0 do
            table.remove(t, 1)
        end
        for i,s in ipairs(unified) do
            table.insert(t, s)
        end
    end
    return true
end

--- Check (and modify) a table according to a description table
-- @param t Table to check.
-- @param keys Attribute description table. See comments in code for details.
-- @param inherit Table with keys to inherit. See comments in code for details.
-- @return True on success, false on verification failure.
-- @return Error object if false.
function e2lib.vrfy_table_attributes(t, keys, inherit)
    local e = err.new("checking file configuration")

    if type(t) ~= "table" then
        return false, e:append("not a table")
    end

    -- keys = {
    --   location = {
    --     mandatory = true,
    --     type = "string",
    --     inherit = false,
    --   },
    -- }
    -- inherit = {
    --   location = "foo",
    -- }

    -- inherit keys
    for k,v in pairs(inherit) do
        if not t[k] and keys[k].inherit ~= false then
            t[k] = v
        end
    end

    -- check types and mandatory
    for k,v in pairs(keys) do
        if keys[k].mandatory and not t[k] then
            e:append("missing mandatory key: %s", k)
        elseif t[k] and keys[k].type ~= type(t[k]) then
            e:append("wrong type: %s", k)
        end
    end

    if e:getcount() > 1 then
        return false, e
    end
    return true
end

return strict.lock(e2lib)

-- vim:sw=4:sts=4:et:
