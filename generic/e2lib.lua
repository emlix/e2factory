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

_version = "e2factory, the emlix embedded build system, version " .. 
							buildconfig.VERSION

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
along with this program.  If not, see <http://www.gnu.org/licenses/>.]]

-- Module-level global variables
--
--   e2lib.interactive -> BOOL
--
--     True, when lua was started in interactive mode (either by giving
--     the "-i" option or by starting lua and loading the e2 files
--     manually).

e2lib = { 
  logflags = {
    { "v1", true },    -- minimal
    { "v2", true },    -- verbose
    { "v3", false },   -- verbose-build
    { "v4", false }    -- tooldebug
  },
  log_debug = false,
  debug = false, 
  playground = false,
  interactive = arg and (arg[ -1 ] == "-i"),
  -- variables initialized in e2lib.init()
  username = nil, 
  homedir = nil, 
  hostname = nil,
  termwidth = 72,
  env = {},
  last_output = false,
  tmpdirs = {},
  tmpfiles = {},
  enable_invocation_log = false,
  default_projects_server = "projects",
  default_project_version = "2",
  local_e2_branch = nil,
  local_e2_tag = nil,
  --- command line arguments that influence global settings are stored here
  -- @class table
  -- @name cmdline
  cmdline = {},
  git_skip_checkout = true,
  buildnumber_server_url = nil,
  template_path = string.format("%s/templates", buildconfig.SYSCONFDIR),
  extension_config = ".e2/extensions",
  global_interface_version_file = ".e2/global-version",
  lock = nil,
  logrotate = 5,   -- configurable via config.log.logrotate
}

-- Interrupt handling
--
-- e2util sets up a SIGINT handler that calls back into this function.

function e2lib.interrupt_hook()
  e2lib.abort("*interrupted by user*")
end


-- Extended error checking for module bindings
--
--   e2lib.module(NAME, [TABLE]) -> TABLE
--
--     Manipulates the meta-table of TABLE to signal an error, when a
--     non-existant field of it is accessed. Also sets the "name" entry for
--     TABLE to the given argument. If no table argument is given, a new
--     table is returned.

function e2lib.module(name, t)
  t = t or {}
  t.name = name
  local mt = {}
  function mt.__index(t, k)
    error("access to non-existant module binding `" .. k .. "' in `" .. t.name .. "'")
  end
  setmetatable(t, mt)
  return t
end

--- make sure the environment variables inside the e2lib table are
-- initialized properly, and abort otherwise
-- This function always succeeds or aborts.
function e2lib.init()
  e2lib.log(4, "e2lib.init()")

  e2lib.warn_category = {
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
	{ name = "E2_LOCAL_BRANCH", required = false },
	{ name = "E2_LOCAL_TAG", required = false },
  }

  local osenv = {}
  for _, var in pairs(getenv) do
    var.val = os.getenv(var.name)
    if var.required and not var.val then
      e2lib.abort(string.format("%s is not set in the environment", var.name))
    end
    if var.default and not var.val then
      var.val = var.default
    end
    osenv[var.name] = var.val
  end
  e2lib.osenv = osenv

  -- assign some frequently used environment variables
  e2lib.homedir = e2lib.osenv["HOME"]
  e2lib.username = e2lib.osenv["USER"]
  e2lib.terminal = e2lib.osenv["TERM"]
  if e2lib.osenv["E2TMPDIR"] then
    e2lib.tmpdir = e2lib.osenv["E2TMPDIR"]
  else
    e2lib.tmpdir = e2lib.osenv["TMPDIR"]
  end

  -- get the host name
  e2lib.hostname = e2lib.program_output("hostname")
  if not e2lib.hostname then
    e2lib.abort("hostname ist not set")
  end

  e2lib.lock = lock.new()
end

function e2lib.init2()
  local rc, re
  local e = new_error("initializing e2lib (step2)")

  -- get the global configuration
  local config = e2lib.get_global_config()

  -- honour tool customizations from the config file
  if config.tools then
    for k,v in pairs(config.tools) do
      tools.set_tool(k, v.name, v.flags)
    end
  end

  -- handle E2_SSH environment setting
  local ssh = nil
  ssh  = e2lib.osenv["E2_SSH"]
  if ssh then
    e2lib.log(3, string.format(
	"using ssh command from the E2_SSH environment variable: %s", ssh))
    tools.set_tool("ssh", ssh)
  end

  -- initialize the tools library after resetting tools
  local rc, re = tools.init()
  if not rc then
    e2lib.abort(e:cat(re))
  end

  -- get host system architecture
  e2lib.host_system_arch, re = e2lib.get_sys_arch()
  if not e2lib.host_system_arch then
    e2lib.abort(e:cat(re))
  end
end

--- return the output of a program, abort if the call fails
-- @param cmd string: the program to call
-- @return string: the program output
function e2lib.program_output(cmd)
  local i = io.popen(cmd)
  if not i then
    e2lib.abort("invocation of program failed:  ", cmd) 
  else
    local input = i:read("*a")
    return input
  end
end

--- print a warning, composed by concatenating all arguments to a string
-- @param ... any number of strings
-- @return nil
function e2lib.warn(category, ...)
  local msg = table.concat({...})
  return e2lib.warnf(category, "%s", msg)
end

--- print a warning
-- @param format string: a format string
-- @param ... arguments required for the format string
-- @return nil
function e2lib.warnf(category, format, ...)
  if (format:len() == 0) or (not format) then
    e2lib.bomb("calling e2lib.warnf() with zero length format")
  end
  if type(e2lib.warn_category[category]) ~= "boolean" then
    e2lib.bomb("calling e2lib.warnf() with invalid warning category")
  end
  if e2lib.warn_category[category] == true then
    local prefix = "Warning: "
    if e2lib.log_debug then
      prefix = string.format("Warning [%s]: ", category)
    end
    e2lib.log(1, prefix .. string.format(format, ...))
  end
  return nil
end

--- exit, cleaning up temporary files and directories. 
-- Return code is '1' and cannot be overrided.
-- This function takes any number of strings or an error object as arguments.
-- Please pass error objects to this function in the future.
-- @param ... an error object, or any number of strings
-- @return This function does not return
function e2lib.abort(...)
  local t = { ... }
  local e = t[1]
  if e and e.print then
    e:print()
  else
    local msg = table.concat(t)
    if msg:len() == 0 then
      e2lib.bomb("calling e2lib.abort() with zero length message")
    end
    e2lib.log(1, "Error: " .. msg)
  end
  e2lib.rmtempdirs()
  e2lib.rmtempfiles()
  e2lib.lock:cleanup()
  os.exit(1)
end

--- write a message about an internal error, including a traceback
-- and exit. Return code is 32.
-- @param ... any number of strings
-- @return This function does not return
function e2lib.bomb(...)
  local msg = table.concat({...})
  io.stderr:write(
	 "Internal Error:\n" ..
	 msg .. "\n" ..
	 "\n" ..
	 "You encountered an internal error in the e2 tool.\n" ..
	 "Please send a description of the problem, including the\n" ..
	 "stacktrace below to <bugs@e2factory.org>.\n" ..
	 "If possible include a copy of the project in the bug report.\n" ..
	 "\n" ..
         "Thank you - the e2factory team.\n")
  io.stderr:write(debug.traceback().."\n")
  os.exit(32)
end

function e2lib.sete2config(file)
  e2util.setenv("E2_CONFIG", file, 1)
  e2lib.osenv["E2_CONFIG"] = file
  e2lib.cmdline["e2-config"] = file
end

--- enable or disable logging for level.
-- @param level number: loglevel
-- @param value bool
-- @return nil
function e2lib.setlog(level, value)
  e2lib.logflags[level][2] = value
end

--- get logging setting for level
-- @param level number: loglevel
-- @return bool
function e2lib.getlog(level)
  return e2lib.logflags[level][2]
end

--- return highest loglevel that is enabled
-- @return number
function e2lib.maxloglevel()
  local level = 0
  for i = 1, 4 do
    if e2lib.getlog(i) then level = i end
  end
  return level
end

--- get log flags for calling subtools with the same log settings
-- @return string: a string holding command line flags
function e2lib.getlogflags()
  local logflags = ""
  if e2lib.getlog(1) then
    logflags = "--v1"
  end
  if e2lib.getlog(2) then
    logflags = logflags .. " --v2"
  end
  if e2lib.getlog(3) then
    logflags = logflags .. " --v3"
  end
  if e2lib.getlog(4) then
    logflags = logflags .. " --v4"
  end
  if e2lib.log_debug then
    logflags = logflags .. " --log-debug"
  end
  return " " .. logflags
end

--- log to the debug logfile, and log to console if e2lib.getlog(level)
-- @param level number: loglevel
-- @param format string: format string
-- @param ... additional parameters to pass to string.format
-- @return nil
function e2lib.logf(level, format, ...)
  if not format then
    e2lib.bomb("calling e2lib.log() without format string")
  end
  local msg = string.format(format, ...)
  return e2lib.log(level, msg)
end

--- log to the debug logfile, and log to console if e2lib.getlog(level) 
-- is true
-- @param level number: loglevel
-- @param msg string: log message
-- @param ... strings: arguments required for the format string
-- @return nil
function e2lib.log(level, msg)
  if level < 1 or level > 4 then
    e2lib.bomb("invalid log level")
  end
  if not msg then
    e2lib.bomb("calling e2lib.log() without log message")
  end
  local log_prefix = "[" .. level .. "] "
  -- remove end of line if it exists
  if msg:match("\n$") then
    msg = msg:sub(1, msg:len() - 1)
  end
  -- always write log level to debug logfile
  e2lib.debuglogfile:write(log_prefix .. msg)
  e2lib.debuglogfile:write("\n")
  e2lib.debuglogfile:flush()
  if e2lib.getlog(level) then
    if e2lib.log_debug then
      io.stderr:write(log_prefix)
    end
    io.stderr:write(msg)
    io.stderr:write("\n")
  end
  return nil
end

function e2lib.rotate_log(file)
  local e = new_error("rotating logfile: %s", file)
  local rc, re
  local logdir = e2lib.dirname(file)
  local logfile = e2lib.basename(file)
  local dir = e2util.directory(logdir, false)
  if not dir then
    return false, e:cat(string.format("%s: can't read directory", dir))
  end
  local files = {}
  for _,f in ipairs(dir) do
    local match = f:match(string.format("%s.[0-9]+", logfile))
    if match then
      table.insert(files, 1, match)
    end
  end
  -- sort in reverse order
  local function comp(a, b)
    local na = a:match(string.format("%s.([0-9]+)", logfile))
    local nb = b:match(string.format("%s.([0-9]+)", logfile))
    return tonumber(na) > tonumber(nb)
  end
  table.sort(files, comp)
  for _,f in ipairs(files) do
    local n = f:match(string.format("%s.([0-9]+)", logfile))
    if n then
      n = tonumber(n)
      if n >= e2lib.logrotate - 1 then
	local del = string.format("%s/%s.%d", logdir, logfile, n)
	rc, re = e2lib.rm(del)
	if not rc then
	  return false, e:cat(re)
	end
      else
	local src = string.format("%s/%s.%d", logdir, logfile, n)
	local dst = string.format("%s/%s.%d", logdir, logfile, n + 1)
	rc, re = e2lib.mv(src, dst)
	if not rc then
	  return false, e:cat(re)
	end
      end
    end
  end
  local src = file
  local dst = string.format("%s/%s.0", logdir, logfile)
  if e2lib.isfile(src) then
    rc, re = e2lib.mv(src, dst)
    if not rc then
      return false, e:cat(re)
    end
  end
  return true, nil
end

--- append a line to a file
-- @param file string: filename
-- @param line string: a line to append to the file
-- @return bool
-- @return nil, an error string on error
local function append_to_file(file, line)
  local f, msg = io.open(file, "a+")
  if not f then
    return false, msg
  end
  f:write(line)
  f:close()
  return true, nil
end

--- log tool invocations
-- this function always succeeds or aborts
-- @param info
-- @param args
-- @return nothing
function e2lib.log_invocation(info, args)
  local pname = "<none>"
  if info then
    pname = info.name
  end
  local logstring = string.format(
	"%s %s %s %s \"%s %s\"\n",
	pname, os.date(), buildconfig.VERSIONSTRING,
	e2lib.username, arg[0], table.concat(args, " "))

  -- always log to the user logfile
  local ulogdir = string.format("%s/.e2", e2lib.homedir)
  local ulogfile = string.format("%s/run.log", ulogdir)
  e2lib.mkdir(ulogdir, "-p")
  local rc, e = append_to_file(ulogfile, logstring)
  if not rc then
    e2lib.abort(string.format("can't log to file %s: %s", ulogfile, e))
  end

  -- log to the project logfile
  if info then
    local plogdir = string.format("%s/.e2", info.root)
    local plogfile = string.format("%s/run.log", plogdir)
    e2lib.mkdir(plogdir, "-p")
    rc, e = append_to_file(plogfile, logstring)
    if not rc then
      e2lib.abort(string.format("can't log to file %s: %s", plogfile, e))
    end
  end

  -- send the queued logs from the user logfile to the server
  local args = string.format(
	"--silent --fail -0 -q -f " ..
	"--header 'Content-type: text/plain' " ..
	"--data-binary '@%s' --connect-timeout 1 " ..
	"'http://e2data:6532/store-run-log.lua?project=%s&user=%s&host=%s' " ..
	">/dev/null",
	ulogfile, pname, e2lib.username, e2lib.hostname)
  local rc = true
  local re = nil
  if e2lib.enable_invocation_log == true then
    -- really send logs only if enabled
    rc, re = e2lib.curl(args)
  end
  if not rc then
    local ulogfile_backup = ulogfile .. ".backup"
    local args = string.format("'%s' >>'%s'", ulogfile, ulogfile_backup)
    e2lib.cat(args)
    e2lib.rm(ulogfile, "-f")
  else
    e2lib.log(3, "failed sending queued logs to the server")
  end
end

--- exit from the tool, cleaning up temporary files and directories
-- @param rc number: return code (optional, defaults to 0)
-- @return This function does not return.
function e2lib.finish(returncode)
  if not returncode then
    returncode = 0
  end
  local rc, re = plugin.exit_plugins()
  if not rc then
    e2lib.logf(1, "deinitializing plugins failed (ignoring)")
  end
  e2lib.rmtempdirs()
  e2lib.rmtempfiles()
  e2lib.lock:cleanup()
  os.exit(returncode)
end


-- Pathname operations
--
--   e2lib.dirname(PATH) -> STRING
--
--     Returns the directory part of the string PATH.
--
--   e2lib.basename(PATH, [EXTENSION]) -> STRING
--
--     Returns the filename part of PATH by stripping the directory part.
--     if EXTENSION is given and if it matches the file-extension of PATH,
--     then the extension part is also removed.
--
--   e2lib.splitpath(PATH) -> DIR, BASE, TYPE
--
--     Checks PATH for trailing "/" for a directory,
--     splits up the real path into dir and base to ensure that
--     DIR .. BASE will address the file, as DIR always ends in "/"
--     TYPE is set to stat.type. return nil for non existing file
--

function e2lib.dirname(path)
  local s, e, dir = string.find(path, "^(.*)/[^/]*$")
  if dir == "" then return "/"
  else return dir or "." end
end

function e2lib.basename(path, ext)
  local s, e, base = string.find(path, "^.*/([^/]+)[/]?$")
  if not base then base = path end
  if ext then
    if string.sub(base, -#ext) == ext then
      return string.sub(base, 1, -#ext - 1)
    end
  end
  return base
end

function e2lib.splitpath(path)
  local p = e2util.realpath(path)
  if not p then return nil, "path does not exist" end
  local st = e2util.stat(p)
  local sf = string.sub(path, -1) ~= "/"
  if (st.type == "directory") == sf then
    return nil, "is " .. (sf and "" or "not ") .. "a directory"
  end
  local s, e, d, b = string.find(p, "^(.*/)([^/]*)$")
  return d, b == "" and "." or b, st.type
end

function e2lib.is_backup_file(path)
  return string.find(path, "~$") or string.find(path, "^#.*#$")
end

function e2lib.chomp(str, chr)
  local chr = chr or "/"
  if string.sub(str, -1, -1) == chr then
    return string.sub(str, 1, -2)
  else
    return str
  end
end

-- determines the type of an archive
-- say "z" for gzip, "j" for bzip2, "" for tar archive
-- nil is returned for unknown data
function e2lib.tartype(path)
  local f, e = io.open(path, "r")
  if not f then
    e2lib.abort(e)
  end
  local d = f and f:read(512)
  local l = d and string.len(d) or 0
  local c = nil
  f:close()
  if l > 261 and string.sub(d, 258, 262) == "ustar" then c = ""
  elseif l > 1 and string.sub(d, 1, 2) == "\031\139" then c = "--gzip"
  elseif l > 2 and string.sub(d, 1, 3) == "BZh" then c = "--bzip2"
  elseif l > 3 and string.sub(d, 1, 4) == "PK\003\004" then c = "zip"
  end
  return c
end

--- translate filename suffixes to valid tartypes for e2-su-2.2
-- @filename string: filename
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
		e = new_error("unknown suffix for filename: %s", filename)
		return false, e
	end
	return tartype
end

-- generates a command to unpack an archive file
-- physpath is the current location and filename to be unpacked later
-- virtpath is the location and name of the file at the time of unpacking
-- destdir is the path to where the unpacked files shall be put
-- return unix command on success, nil otherwise
function e2lib.howtounpack(physpath, virtpath, destdir)
  local c = e2lib.tartype(physpath)
  if c == "zip" then
    c = "unzip \"" .. virtpath .. "\" -d \"" .. destdir .. "\""
  elseif c then
    c = string.format("tar -C '%s' %s -xf '%s'", destdir, c, virtpath)
  end
  return c
end

-- Input/Output operations
--
--   e2lib.read_line(PATHNAME)
--
--     Reads a single line from the given file and returns it.
--
--   e2lib.read_all(FD, [BLOCKSIZE]) -> STRING
--
--     Reads all remaining input from a given file-descriptor. BLOCKSIZE
--     specifies the size of subsequently read blocks and defaults to 1024.

function e2lib.read_line(path)
  local f, msg = io.open(path)
  if not f then
    return nil, new_error("%s", msg)
  end
  local l, msg = f:read("*l")
  if not l then
    return nil, new_error("%s", msg)
  end
  f:close()
  return l
end

function e2lib.read_all(fd, blocksize)
  local input = {}
  local blocksize = blocksize or 1024
  while true do
    local s, msg = e2util.read(fd, blocksize)
    if not s then e2lib.bomb("read error: ", msg) 
    elseif #s == 0 then break
    else table.insert(input, s) end
  end
  return table.concat(input)
end


-- Iterators
--
-- These iterators are convenience functions for use in "for" statements.
--
--   e2lib.read_configuration(PATH)
--
--     Returns the successive non-empty lines contained in the file PATH.
--     Comments (of the form "# ...") are removed.
--
--   e2lib.directory(PATH, [DOTFILES, [NOERROR]])
--
--     Successively returns the files in the directory designated by
--     PATH. If DOTFILES is given and true, then files beginning with "."
--     are also included in the listing.

function e2lib.read_configuration(p)
  if e2util.exists(p) then
    local function nextline(s)
      while true do
	local ln = s:read("*l")
	if not ln then 
	  s:close()
	  return nil
	elseif not string.find(ln, "^%s*#") and string.find(ln, "%S") then
	  local s = string.find(ln, "#.*")
	  if s then return string.sub(ln, 1, s - 1)
	  else return ln end
	end
      end
    end
    return nextline, io.open(p)
  else
    e2lib.abort("no such file: " .. p)
  end
end

--- read the global config file
-- local tools call this function inside collect_project_info()
-- global tools must call this function after parsing command line options
-- @param e2_config_file string: config file path (optional)
-- @return bool
-- @return error string on error
function e2lib.read_global_config(e2_config_file)
  e2lib.log(4, "e2lib.read_global_config()")
  local cf = get_first_val({
	e2lib.cmdline["e2-config"],   -- command line
	e2lib.osenv["E2_CONFIG"],     -- environment
  })
  local cf_path
  if cf then
    cf_path = { cf }
  elseif e2_config_file then
    cf_path = { e2_config_file }
  else
    cf_path = {
	-- this is ordered by priority
	string.format("%s/.e2/e2.conf-%s.%s.%s", e2lib.homedir,
		buildconfig.MAJOR, buildconfig.MINOR, buildconfig.PATCHLEVEL),
	string.format("%s/.e2/e2.conf-%s.%s", e2lib.homedir, buildconfig.MAJOR,
							buildconfig.MINOR),
	string.format("%s/.e2/e2.conf", e2lib.homedir),
	string.format("%s/e2.conf-%s.%s.%s", buildconfig.SYSCONFDIR,
		buildconfig.MAJOR, buildconfig.MINOR, buildconfig.PATCHLEVEL),
	string.format("%s/e2.conf-%s.%s", buildconfig.SYSCONFDIR,
				buildconfig.MAJOR, buildconfig.MINOR),
	string.format("%s/e2.conf", buildconfig.SYSCONFDIR),
    }
  end
  -- use ipairs to keep the list entries ordered
  for _,path in ipairs(cf_path) do
    local c = {}
    c.config = function(x)
	c.data = x
	end
    e2lib.log(4, string.format("reading global config file: %s", path))
    local rc = e2util.exists(path)
    if rc then
      e2lib.log(3, string.format("using global config file: %s", path))
      local rc, e = e2lib.dofile_protected(path, c, true)
      if not rc then
	return nil, e
      end
      if not c.data then
        return false, "invalid configuration"
      end
      e2lib.global_config = c.data
      e2lib.use_global_config()
      return true, nil
    else
      e2lib.log(4, string.format(
	"global config file does not exist: %s", path))
    end
  end
  return false, "no config file available"
end

function e2lib.write_extension_config(extensions)
  local e = new_error("writing extensions config: %s", e2lib.extension_config)
  local f, re = io.open(e2lib.extension_config, "w")
  if not f then
    return false, e:cat(re)
  end
  f:write(string.format("extensions {\n"))
  for _,ex in ipairs(extensions) do
    f:write(string.format("  {\n"))
    for k,v in pairs(ex) do
      f:write(string.format("    %s=\"%s\",\n", k, v))
    end
    f:write(string.format("  },\n"))
  end
  f:write(string.format("}\n"))
  f:close()
  return true, nil
end

--- read the local extension configuration
-- This function must run while being located in the projects root directory
-- @param root string: path to project
-- @return the extension configuration table
-- @return an error object on failure
function e2lib.read_extension_config()
  local e = new_error("reading extension config file: %s",
						e2lib.extension_config)
  local rc = e2util.exists(e2lib.extension_config)
  if not rc then
    return false, e:append("config file does not exist")
  end
  e2lib.logf(3, "reading extension file: %s", e2lib.extension_config)
  local c = {}
  c.extensions = function(x)
    c.data = x
  end
  local rc, re = e2lib.dofile_protected(e2lib.extension_config, c, true)
  if not rc then
    return false, e:cat(re)
  end
  local extension = c.data
  if not extension then
    return false, e:append("invalid extension configuration")
  end
  return extension, nil
end

--- use the global parameters from the global configuration
-- this function always succeeds or aborts
-- @return nothing
function e2lib.use_global_config()

  -- check if type(x) == t, and abort if not.
  local function assert_type(x, d, t1)
    local t2 = type(x)
    if t1 ~= t2 then
      e2lib.abort(
        string.format("configuration error: %s (expected %s got %s)", d, t1, t2))
    end
  end

  local config = e2lib.global_config
  if not config then
    e2lib.abort("global config not available")
  end
  if config.log and config.log.enable ~= nil then
    e2lib.enable_invocation_log = config.log.enable
    e2lib.log(3, string.format(
		"e2lib.enable_invocation_log=%s", tostring(config.log.enable)))
  end
  if config.log then
    assert_type(config.log, "config.log", "table")
    if config.log.logrotate then
      assert_type(config.log.logrotate, "config.log.logrotate", "number")
      e2lib.logrotate = config.log.logrotate
    end
  end
  if config.site and config.site.buildnumber_server_url ~= nil then
    e2lib.buildnumber_server_url = config.site.buildnumber_server_url
    e2lib.log(3, string.format("e2lib.buildnumber_server_url=%s", 
				tostring(config.site.buildnumber_server_url)))
  end
  assert_type(config.site, "config.site", "table")
  assert_type(config.site.e2_branch, "config.site.e2_branch", "string")
  assert_type(config.site.e2_tag, "config.site.e2_tag", "string")
  assert_type(config.site.e2_server, "config.site.e2_server", "string")
  assert_type(config.site.e2_base, "config.site.e2_base", "string")
  assert_type(config.site.default_extensions, "config.site.default_extensions", "table")
end

--- get the global configuration
-- this function always succeeds or aborts
-- @return the global configuration
function e2lib.get_global_config()
  local config = e2lib.global_config
  if not config then
    e2lib.abort("global config not available")
  end
  return config
end

function e2lib.directory(p, dotfiles, noerror)
  local dir = e2util.directory(p, dotfiles)
  if not dir then
    if noerror then dir = {}
    else e2lib.abort("directory `", p, "' does not exist")
    end
  end
  table.sort(dir)
  local i = 1
  local function nextfile(s)
    if i > #s then return nil
    else
      local j = i
      i = i + 1
      return s[ j ]
    end
  end
  return nextfile, dir
end


-- Hash value computation
--
--   Computes some hash value from data, which is fed into it
--   using an iterator function to be provided. The iterator
--   function is expected to accept one parameter value.
--
--     e2lib.compute_hash(ITER, [VALUE...])

function e2lib.compute_hash(iter, ...)
  local n, f, s 
  local i, o, e, p = e2util.pipe("sha1sum")
  if not i then e2lib.bomb("cannot calculate hash sum: " .. o) end
  for x in iter(...) do
    n, f = e2util.write(i, x)
    if not n then e2lib.bomb(f) end
  end
  n, f = e2util.close(i)
  if not n then e2lib.bomb(f) end
  s, f = e2util.read(o, 40)
  if not s then e2lib.bomb(f) end
  n, f = e2util.close(o)
  if not n then e2lib.bomb(f) end
  n, f = e2util.wait(p)
  if not n then e2lib.bomb(f) end
  return s 
end

-- Iterator functions
--
--   e2lib.impairs(TABLE)
--
--    iterates on a table, returning only the value for each entry, not the key
--    To be used like: for v in e2lib.impairs(table) do ... end
--
--   e2lib.pairs(TABLE)
--
--    iterates on a table, returning both key and value, not simultaneously but
--    one by one, suitable for hash computation. This function iterates twice
--    as often as entries are in the table. To be used like:
--    for kv in e2lib.pairs(table) do ... end

function e2lib.impairs(table)
  local k = nil
  local function value(t)
    k = next(t, k)
    return k and t[k]
  end
  return value, table
end

function e2lib.pairs(table)
  local k = nil
  local v = nil
  local function value(t)
    local r = v
    if v then
      v = nil
      return r
    end
    k = next(t, k)
    v = k and t[k]
    return k
  end
  return value, table
end

-- callcmd: call a command, connecting
--  stdin, stdout, stderr to luafile objects

function e2lib.callcmd(infile, outfile, errfile, cmd)
  -- redirect stdin
  io.stdin:close()
  luafile.dup2(infile:fileno(), 0)
  -- redirect stdout
  io.stdout:close()
  luafile.dup2(outfile:fileno(), 1)
  -- redirect stderr
  io.stderr:close()
  luafile.dup2(errfile:fileno(), 2)
  -- run the command
  local rc = os.execute(cmd)
  return (rc/256)
end

-- callcmd_redirect: call a command with 
--  stdin redirected from /dev/null 
--  stdout/stderr redirected to a luafile object

function e2lib.callcmd_redirect(cmd, out)
  local devnull, pid, rc
  devnull = luafile.open("/dev/null", "r")
  e2lib.log(3, "+ " .. cmd)
  pid = e2util.fork()
  if pid == 0 then
    rc = e2lib.callcmd(devnull, out, out, cmd)
    os.exit(rc)
  else
    rc = e2util.wait(pid)
    luafile.close(devnull)
    return rc
  end
end

-- callcmd_pipe: call several commands in a pipe
--  cmds is a table of unix commands
--  redirect endpoints to /dev/null, unless given
--  return nil on success, descriptive string on error

function e2lib.callcmd_pipe(cmds, infile, outfile)
  local i = infile or luafile.open("/dev/null", "r")
  local c = #cmds
  local rc = nil
  local rcs = {}
  local pids = {}
  local ers = {}
  for n = 1, c do
    local o, pr, fr, er, ew
    pr, er, ew = luafile.pipe()
    if not pr then e2lib.abort("failed to open pipe (error)") end
    if n < c then
      pr, fr, o = luafile.pipe()
      if not pr then e2lib.abort("failed to open pipe") end
    else
      o = outfile or ew
    end
    e2lib.log(3, "+ " .. cmds[n])
    local pid = e2util.fork()
    if pid == 0 then
      if n < c then fr:close() end
      er:close()
      rc = e2lib.callcmd(i, o, ew, cmds[n])
      os.exit(rc)
    end
    pids[pid] = n
    e2util.unblock(er:fileno())
    ers[n] = er
    ew:close()
    if n < c then o:close() end
    if n > 1 or not infile then i:close() end
    i = fr
  end
  while c > 0 do
    local fds = {}
    local ifd = {}
    for i, f in pairs(ers) do
      local n = f:fileno()
      table.insert(fds, n)
      ifd[n] = i
    end
    local i, r = e2util.poll(-1, fds)
    if i <= 0 then e2lib.abort("fatal poll abort " .. tostring(i)) end
    i = ifd[fds[i]]
    if r then
      local x
      repeat
	x = ers[i]:readline()
        if x then
	  e2lib.log(3, x)
        end
      until not x
    else
      ers[i]:close()
      ers[i] = nil
      c = c - 1
    end
  end
  c = #cmds
  while c > 0 do
    local r, p = e2util.wait(-1)
    if not r then e2lib.abort(p) end
    local n = pids[p]
    if n then
      if r ~= 0 then rc = rc or r end
      rcs[n] = r
      pids[p] = nil
      c = c - 1
    end
  end
  return rc and "failed to execute commands in a pipe, exit codes are: "
		.. table.concat(rcs, ", ")
end

--- call a command with stdin redirected from /dev/null, stdout/stderr 
-- captured via a pipe
-- the capture function is called for every chunk of output that
-- is captured from the pipe.
-- @return unknown
function e2lib.callcmd_capture(cmd, capture)
  local rc, oread, owrite, devnull, pid
  local function autocapture(...)
    local msg = table.concat({...})
    e2lib.log(3, msg)
    e2lib.last_output = msg
  end
  e2lib.last_output = false
  capture = capture or autocapture
  rc, oread, owrite = luafile.pipe()
  owrite:setlinebuf()
  oread:setlinebuf()
  devnull = luafile.open("/dev/null", "r")
  e2lib.log(4, "+ " .. cmd)
  pid = e2util.fork()
  if pid == 0 then
    oread:close()
    rc = e2lib.callcmd(devnull, owrite, owrite, cmd)
    os.exit(rc)
  else
    owrite:close()
    --e2lib.log("capturing...")
    while not oread:eof() do
      local x = oread:readline()
      if x then
        --print("read: '" .. x .. "'")
        capture(x)
     end
    end
    oread:close()
    rc = e2util.wait(pid)
    luafile.close(devnull)
    --e2lib.log("capturing done...")
    --e2lib.log("exit status was " .. rc)
  end
  return rc
end

--- call a command, log its output to a loglevel, catch the last line of
-- output and return it in addition to the commands return code
-- @param cmd string: the command
-- @param loglevel number: loglevel (optional, defaults to 3)
-- @return number: the return code
-- @return string: the program output, or nil
function e2lib.callcmd_log(cmd, loglevel)
	local e = ""
	if not loglevel then
		loglevel = 3
	end
	local function logto(output)
		e2lib.log(loglevel, output)
		e = e .. output
	end
	local rc = e2lib.callcmd_capture(cmd, logto)
	return rc, e
end

-- Protected execution of Lua code
--
--   e2lib.dofile_protected(PATH, TABLE, [ALLOWNEWDEFS])
--
--     Runs the code in the Lua file at PATH with a restricted global environment.
--     TABLE contains a table with the initial global environment. If ALLOWNEWDEFS
--     is given and true, then the code may define new global variables.

function e2lib.dofile_protected(path, gtable, allownewdefs)
  local chunk, msg = loadfile(path)
  if not chunk then
    return false, msg
  end
  local t = gtable
  -- t._G = t
  local function checkread(t, k)
    local x = rawget(t, k)
    if x then return x
    else e2lib.abort(path, ": attempt to reference undefined global variable '",
		     k, "'")
    end
  end
  local function checkwrite(t, k, v)
    e2lib.abort(path, ": attempt to set new global variable `", k, "' to ", v)
  end
  if not allownewdefs then
    setmetatable(t, { __newindex = checkwrite, __index = checkread })
  end
  setfenv(chunk, t)
  local s, msg = pcall(chunk)
  if not s then
    e2lib.abort(msg)
  end
  return true, nil
end

function e2lib.dofile2(path, gtable)
  local e = new_error("error loading config file: %s", path)
  local chunk, msg = loadfile(path)
  if not chunk then
    return false, e:cat(msg)
  end
  setfenv(chunk, gtable)
  local s, msg = pcall(chunk)
  if not s then
    return false, e:cat(msg)
  end
  return true, nil
end

--   e2lib.locate_project_root([PATH]) -> PATH | nil
--
--     Locates the root directory of current project. If PATH is not given,
--     then the current working directory is taken as the base directory from
--     where to start.
--

function e2lib.locate_project_root(path)
  local rc, re
  local e = new_error("checking for project directory failed")
  local save_path = e2util.cwd()
  if not save_path then
    return nil, e:append("cannot get current working directory")
  end
  if path then
    rc = e2lib.chdir(path)
    if not rc then
      e2lib.chdir(save_path)
      return nil, e:cat(re)
    end
  else
    path = e2util.cwd()
    if not path then
      e2lib.chdir(save_path)
      return nil, e:append("cannot get current working directory")
    end
  end
  while true do
    if e2util.exists(".e2") then
      e2lib.logf(3, "project is located in: %s", path)
      e2lib.chdir(save_path)
      return path
    end
    if path == "/" then
      break
    end
    rc = e2lib.chdir("..")
    if not rc then
      e2lib.chdir(save_path)
      return nil, e:cat(re)
    end
    path = e2util.cwd()
    if not path then
      e2lib.chdir(save_path)
      return nil, e:append("cannot get current working directory")
    end
  end
  e2lib.chdir(save_path)
  return nil, new_error("not in a project directory")
end

-- parse version files:

function e2lib.parse_versionfile(filename)
  local f = luafile.open(filename, "r")
  if not f then
    e2lib.abort("can't open version file: " .. filename)
  end
  local l = f:readline()
  if not l then
    e2lib.abort("can't parse version file: " .. filename)
  end
  local v = l:match("[0-9]+")
  if not v then
    e2lib.abort("invalid format of project version `" .. l .. "' in " .. filename)
  end
  --e2lib.log(4, "project version is " .. v)
  return v
end

function e2lib.parse_e2versionfile(filename)
  local f = luafile.open(filename, "r")
  if not f then
    e2lib.abort("can't open e2version file: " .. filename)
  end
  local l = f:readline()
  if not l then
    e2lib.abort("can't parse e2version file: " .. filename)
  end
  local match = l:gmatch("[^%s]+")
  local v = {}
  v.branch = match() or e2lib.abort("invalid branch name `", l, "' in e2 version file ",
				    filename)
  v.tag = match() or e2lib.abort("invalid tag name `", l, "' in e2 version file ",
			       filename)
  --table.print(v)
  e2lib.log(3, "using e2 branch " .. v.branch .. " tag " .. v.tag)
  return v
end

--- Create a temporary file.
-- The template string is passed to the mktemp tool, which replaces
-- trailing X characters by some random string to create a unique name.
-- This function always succeeds (or aborts immediately).
-- @param template string: template name (optional)
-- @return string: name of the file
function e2lib.mktempfile(template)
  if not template then
    template = string.format("%s/e2tmp.%d.XXXXXXXX", e2lib.tmpdir,
							e2util.getpid())
  end
  local cmd = string.format("mktemp '%s'", template)
  local mktemp = io.popen(cmd, "r")
  if not mktemp then
    e2lib.abort("can't mktemp")
  end
  local tmp = mktemp:read()
  if not tmp then
    e2lib.abort("can't mktemp")
  end
  mktemp:close()
  -- register tmp for removing with rmtempfiles() later on
  table.insert(e2lib.tmpfiles, tmp)
  e2lib.log(4, string.format("creating temporary file: %s", tmp))
  return tmp
end

--- remove a temporary file and remove it from the builtin list of
-- temporary files
-- This function always succeeds (or aborts immediately)
-- @param path
function e2lib.rmtempfile(tmpfile)
  for i,v in ipairs(e2lib.tmpfiles) do
    if v == tmpfile then
      table.remove(e2lib.tmpfiles, i)
      e2lib.log(4, string.format("removing temporary file: %s", tmpfile))
      e2lib.rm(tmpfile, "-f")
    end
  end
end

--- Create a temporary directory.
-- The template string is passed to the mktemp tool, which replaces
-- trailing X characters by some random string to create a unique name.
-- This function always succeeds (or aborts immediately).
-- @param template string: template name (optional)
-- @return string: name of the directory
function e2lib.mktempdir(template)
  if not template then
    template = string.format("%s/e2tmp.%d.XXXXXXXX", e2lib.tmpdir,
							e2util.getpid())
  end
  local cmd = string.format("mktemp -d '%s'", template)
  local mktemp = io.popen(cmd, "r")
  if not mktemp then
    e2lib.abort("can't mktemp")
  end
  local tmpdir = mktemp:read()
  if not tmpdir then
    e2lib.abort("can't mktemp")
  end
  mktemp:close()
  -- register tmpdir for removing with rmtempdirs() later on
  table.insert(e2lib.tmpdirs, tmpdir)
  e2lib.log(4, string.format("creating temporary directory: %s", tmpdir))
  return tmpdir
end

-- remove a temporary directory and remove it from the builtin list of
-- temporary directories
-- This function always succeeds (or aborts immediately)
-- @param path
function e2lib.rmtempdir(tmpdir)
  for i,v in ipairs(e2lib.tmpdirs) do
    if v == tmpdir then
      table.remove(e2lib.tmpdirs, i)
      e2lib.log(4, string.format("removing temporary directory: %s", tmpdir))
      e2lib.rm(tmpdir, "-fr")
    end
  end
end

--- remove temporary directories registered with e2lib.mktempdir()
-- This function does not support error checking and is intended to be
-- called from the e2lib.finish() function.
function e2lib.rmtempdirs()
  e2lib.chdir("/")  -- avoid being inside a temporary directory
  while #e2lib.tmpdirs > 0 do
    e2lib.rmtempdir(e2lib.tmpdirs[1])
  end
end

--- remove temporary files registered with e2lib.mktempfile()
-- This function does not support error checking and is intended to be
-- called from the e2lib.finish() function.
function e2lib.rmtempfiles()
  while #e2lib.tmpfiles > 0 do
    e2lib.rmtempfile(e2lib.tmpfiles[1])
  end
end

--- call the rm tool with flags and filename
-- @param file string: the file parameter
-- @param flags string: flags to pass to rm (optional)
-- @return bool
-- @return an error object on failure
function e2lib.rm(file, flags)
  if not flags then
    flags = ""
  end
  local args = string.format("%s %s", flags, file)
  return e2lib.call_tool("rm", args)
end

--- call the touch tool with flags and filename
-- @param file string: the file parameter
-- @param flags string: flags to pass to touch (optional)
-- @returns bool
function e2lib.touch(file, flags)
  if not flags then
    flags = ""
  end
  local args = string.format("%s %s", flags, file)
  return e2lib.call_tool("touch", args)
end

--- call the rmdir command
-- @param dir string: the directory name
-- @param flags string: flags to pass to rmdir
-- @return bool
-- @return the last line ouf captured output
function e2lib.rmdir(dir, flags)
	if not flags then
		flags = ""
	end
	local args = string.format("%s %s", flags, dir)
	return e2lib.call_tool("rmdir", args)
end

--- call the mkdir command
-- @param dir string: the directory name
-- @param flags string: flags to pass to mkdir
-- @return bool
-- @return the last line ouf captured output
function e2lib.mkdir(dir, flags)
	if not flags then
		flags = ""
	end
	local args = string.format("%s %s", flags, dir)
	return e2lib.call_tool("mkdir", args)
end

--- call the patch command
-- @param dir string: the directory name
-- @param flags string: flags to pass to mkdir
-- @return bool
-- @return the last line ouf captured output
function e2lib.patch(args)
	return e2lib.call_tool("patch", args)
end

--- call a tool
-- @param tool string: tool name as registered in the tools library
-- @param args string: arguments
-- @return bool
-- @return string: the last line ouf captured output
function e2lib.call_tool(tool, args)
	local cmd = tools.get_tool(tool)
	if not tool then
		e2lib.bomb("trying to call invalid tool: " .. tostring(tool))
	end
	local flags = tools.get_tool_flags(tool)
	if not flags then
		e2lib.bomb("invalid tool flags for tool: " .. tostring(tool))
	end
	local call = string.format("%s %s %s", cmd, flags, args)
	local rc, e = e2lib.callcmd_log(call)
        if rc ~= 0 then
                return false, e
        end
	return true, e
end

--- call git
-- @param gitdir string: GIT_DIR (optional, defaults to ".git")
-- @param subtool string: git tool name
-- @param args string: arguments to pass to the tool (optional)
-- @return bool
-- @return an error object on failure
function e2lib.git(gitdir, subtool, args)
	local rc, re
	local e = new_error("calling git failed")
	if not gitdir then
		gitdir = ".git"
	end
	if not args then
		args = ""
	end
	local git, re = tools.get_tool("git")
	if not git then
		return false, e:cat(re)
	end
	local call = string.format("GIT_DIR='%s' %s %s %s", gitdir, git,
								subtool, args)
	rc, re = e2lib.callcmd_log(call)
	if rc ~= 0 then
		e:append(call)
		return false, e:cat(re)
	end
	return true, e
end

--- call the svn command
-- @param args string
-- @return bool
function e2lib.svn(args)
  return e2lib.call_tool("svn", args)
end

--- call the ln command
-- @param destination string: destination name
-- @param link string: link name
-- @return bool
-- @return the last line of captured output
function e2lib.symlink(dst, link)
	local args = string.format("-s '%s' '%s'", dst, link)
	return e2lib.call_tool("ln", args)
end

--- call the chmod command
-- @param mode string: the new mode
-- @param path string: path
-- @return bool
-- @return the last line ouf captured output
function e2lib.chmod(mode, path)
	local args = string.format("'%s' '%s'", mode, path)
	return e2lib.call_tool("chmod", args)
end

--- call the mv command
-- @param src string: source name
-- @param dst string: destination name
-- @return bool
-- @return the last line ouf captured output
function e2lib.mv(src, dst)
	local args = string.format("'%s' '%s'", src, dst)
	return e2lib.call_tool("mv", args)
end

--- call the cp command
-- @param src string: source name
-- @param dst string: destination name
-- @param flags string: additional flags
-- @return bool
-- @return the last line ouf captured output
function e2lib.cp(src, dst, flags)
	if not flags then
		flags = ""
	end
	local args = string.format("%s '%s' '%s'", flags, src, dst)
	return e2lib.call_tool("cp", args)
end

--- call the ln command
-- @param src string: source name
-- @param dst string: destination name
-- @param flags string: additional flags
-- @return bool
-- @return the last line ouf captured output
function e2lib.ln(src, dst, flags)
	if not flags then
		flags = ""
	end
	local args = string.format("%s '%s' '%s'", flags, src, dst)
	return e2lib.call_tool("ln", args)
end

--- call the curl command
-- @param args
-- @return bool
-- @return an error object on failure
function e2lib.curl(args)
        return e2lib.call_tool("curl", args)
end

--- call the ssh command
-- @param args
-- @return bool
-- @return an error object on failure
function e2lib.ssh(args)
        return e2lib.call_tool("ssh", args)
end

--- call the scp command
-- @param args
-- @return bool
-- @return an error object on failure
function e2lib.scp(args)
        return e2lib.call_tool("scp", args)
end

--- call the rsync command
-- @param args
-- @return bool
-- @return an error object on failure
function e2lib.rsync(args)
        return e2lib.call_tool("rsync", args)
end

--- call the catcommand
-- @param args
-- @return bool
-- @return an error object on failure
function e2lib.cat(args)
	return e2lib.call_tool("cat", args)
end

--- check if dir is a directory
-- @param dir string: path
-- @return bool
function e2lib.isdir(dir)
  local args = string.format("-d '%s'", dir)
  return e2lib.call_tool("test", args)
end
 
--- check if path is a file
-- @param dir string: path
-- @return bool
function e2lib.isfile(path)
  local t = e2util.stat(path, true)
  if not t or t.type ~= "regular" then
    return false
  end
  return true
end

--- calculate sha1sum for a file
-- @param path string: path
-- @return bool
function e2lib.sha1sum(path)
  local args = string.format("'%s'", path)
  local sha1sum, re = tools.get_tool("sha1sum")
  if not sha1sum then
    return nil, re
  end
  local sha1sum_flags, re = tools.get_tool_flags("sha1sum")
  if not sha1sum_flags then
    return nil, re
  end
  local cmd = string.format("%s %s %s", sha1sum, sha1sum_flags, args)
  local p, msg = io.popen(cmd, "r")
  if not p then
    return nil, new_error(msg)
  end
  local out, msg = p:read("*l")
  p:close()
  local sha1, file = out:match("(%S+)  (%S+)")
  if type(sha1) ~= "string" then
    return nil, new_error(msg)
  end
  return sha1
end

--- call the e2-su command
-- @param args string
-- @return bool
function e2lib.e2_su(args)
  return e2lib.call_tool("e2-su", args)
end

--- call the e2-su-2.2 command
-- @param args string
-- @return bool
function e2lib.e2_su_2_2(args)
  return e2lib.call_tool("e2-su-2.2", args)
end

--- call the tar command
-- @param args string
-- @return bool
function e2lib.tar(args)
  return e2lib.call_tool("tar", args)
end

--- get system architecture
function e2lib.get_sys_arch()
  local rc, re
  local e = new_error("getting host system architecture failed")
  local uname = tools.get_tool("uname")
  local cmd = string.format("%s -m", uname)
  local p, msg = io.popen(cmd, "r")
  if not p then
    return nil, e:cat(msg)
  end
  local l, msg = p:read()
  if not l then
    return nil, e:cat(msg)
  end
  local arch = l:match("(%S+)")
  if not arch then
    return nil, e:append("%s: %s: cannot parse", cmd, l)
  end
  return arch, nil
end

--- return a table of parent directories
-- @param path string: path
-- @return a table of parent directories, including path.
function e2lib.parentdirs(path)
	local i = 2
	local t = {}
	local stop = false
	while true do
		local px
		local p = path:find("/", i)
		if not p then
			p = #path
			stop = true
		end
		px = path:sub(1, p)
		table.insert(t, px)
		i = p + 1
		if stop then
			break
		end
	end
	return t
end

--- write a string to a file
-- @param file string: filename
-- @param data string: data
-- @return bool
-- @return nil, or an error string
function e2lib.write_file(file, data)
  local f, msg = io.open(file, "w")
  if not f then
    return false, string.format("open failed: %s", msg)
  end
  local rc, msg = f:write(data)
  if not rc then
    f:close()
    return false, string.format("write failed: %s", msg)
  end
  f:close()
  return true, nil
end

--- read a file into a string
-- @param file string: filename
-- @return string: the file content
-- @return nil, or an error object
function e2lib.read_file(file)
  local f, msg = io.open(file, "r")
  if not f then
    return nil, new_error("%s", msg)
  end
  local s, msg = f:read("*a")
  if not s then
    return nil, new_error("%s", msg)
  end
  f:close()
  return s, nil
end

--- read a template file, located relative to the current template directory
-- @param file string: relative filename
-- @return string: the file content
-- @return an error object on failure
function e2lib.read_template(file)
  local e = new_error("error reading template file")
  local filename = string.format("%s/%s", e2lib.template_path, file)
  local template, re = e2lib.read_file(filename)
  if not template then
    return nil, e:cat(re)
  end
  return template, nil
end

--- generate an error string from an error string and a token
-- @param e string: error string
-- @param token string: the token leading to the error
-- @return string: an error string suitable for printing
function estring(e, token)
  return string.format("%s: %s", tostring(token), tostring(e))
end

--- parse a server:location string, taking a default server into account
-- @param arg string: the string to parse
-- @param dafault server string: the default server name
-- @return a table with fields server and location, nil on error
-- @return nil, an error string on error
function e2lib.parse_server_location(arg, default_server)
	local sl = {}
	sl.server, sl.location = arg:match("(%S+):(%S+)")
	if sl.server and sl.location then
		return sl
	end
	sl.location = arg:match("(%S+)")
	if sl.location and default_server then
		sl.server = default_server
		return sl
	end
	return nil, "can't parse location"
end

--- setup cache from the global server configuration
-- @return a cache object
-- @return an error object on failure
function e2lib.setup_cache()
  local e = new_error("setting up cache failed")
  local config = e2lib.get_global_config()
  if type(config.cache) ~= "table" or type(config.cache.path) ~= "string" then
    return false, e:append("invalid cache configuration: config.cache.path")
  end
  local replace = { u=e2lib.username }
  local cache_path = e2lib.format_replace(config.cache.path, replace)
  local cache_url = string.format("file://%s", cache_path)
  local c, re = cache.new_cache("local cache", cache_url)
  if not c then
    return nil, e:cat(re)
  end
  for name,server in pairs(config.servers) do
    local flags = {}
    flags.cachable = server.cachable
    flags.cache = server.cache
    flags.islocal = server.islocal
    flags.writeback = server.writeback
    flags.push_permissions = server.push_permissions
    local rc, re = cache.new_cache_entry(c, name, server.url, flags)
    if not rc then
      return nil, e:cat(re)
    end
  end
  return c, nil
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

--- take a table of values, with integer keys and return the first string
-- value
-- @param a table of values
function get_first_val(t)
  for k, v in pairs(t) do
    if type(v) == "string" then
      return v
    end
  end
  return nil
end

--- change directory
-- @param path
-- @return bool
-- @return an error object on failure
function e2lib.chdir(path)
  local rc, re
  rc, re = e2util.cd(path)
  if not rc then
    return false, new_error("chdir %s failed: %s", path, re)
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

--------------------------------------------------------------------------------

-- "seal" modules e2util and e2lib

e2lib.module("e2util", e2util)
e2lib.module("e2lib", e2lib)

e2lib.debuglogfile = io.open("/dev/null", "w")
