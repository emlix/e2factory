/*
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
   */

/*
   Low-level file-system and process operations.
   */


#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <poll.h>
#include <fcntl.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>


static char buffer[PATH_MAX + 1];


/* e2util.fork() -> pid
   | nil, ERRORMESSAGE

   Forks a subprocess.
   */

static int
lua_fork(lua_State *lua)
{
	int rc;
	fflush(0);
	rc = fork();

	if(rc < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushnumber(lua, rc);
	return 1;
}


/* e2util.cwd() -> STRING

   Returns the current working directory.
   */

static int
get_working_directory(lua_State *lua)
{
	char *cwd = getcwd(buffer, sizeof(buffer));

	if (cwd == NULL)
		lua_pushnil(lua);
	else
		lua_pushstring(lua, buffer);

	return 1;
}


/* e2util.realpath(PATH) -> PATH' | nil

   If PATH names an existing object in the file-system, then this
   function will return the absolute, canonical representation of PATH,
   otherwise nil is returned.
   */

static int
get_realpath(lua_State *lua)
{
	const char *p = luaL_checkstring(lua, 1);

	if (realpath(p, buffer) == NULL)
		lua_pushnil(lua);
	else
		lua_pushstring(lua, buffer);

	return 1;
}


/* e2util.stat(PATH, [FOLLOWLINKS?]) -> TABLE | nil

   Returns stat(3) information for the file system object designated by PATH.
   If FOLLOWLINKS? is not given or false, then the returned information will
   apply to the actual symbolic link, if PATH designates one. Otherwise
   the file pointed to by the link is taken. Returns a table with the
   following entries:

   dev           device-id (number)
   ino           inode-number (number)
   mode          permissions and access mode (number)
   nlink         number of hard links (number)
   uid           user id (number)
   gid           group id (number)
   rdev          device id for char of block special files (number)
   size          file size (number)
   atime         access time (number)
   mtime         modification time (number)
   ctime         change time (number)
   blksize       block size (number)
   blocks        number of blocks (number)

   type          one of the following strings:

   block-special
   character-special
   fifo-special
   regular
   directory
   symbolic-link
   socket
   unknown
   */

static int
get_file_statistics(lua_State *lua)
{
	const char *p = luaL_checkstring(lua, 1);
	static struct stat statbuf;
	int fl = lua_gettop(lua) > 1 && lua_toboolean(lua, 2);
	int s;

	if (!fl) {
		s = lstat(p, &statbuf);
	} else {
		s = stat(p, &statbuf);
	}

	if (s < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_newtable(lua);
	int t = lua_gettop(lua);
	lua_pushstring(lua, "dev");
	lua_pushnumber(lua, statbuf.st_dev);
	lua_rawset(lua, t);
	lua_pushstring(lua, "ino");
	lua_pushnumber(lua, statbuf.st_ino);
	lua_rawset(lua, t);
	lua_pushstring(lua, "mode");
	lua_pushnumber(lua, statbuf.st_mode);
	lua_rawset(lua, t);
	lua_pushstring(lua, "nlink");
	lua_pushnumber(lua, statbuf.st_nlink);
	lua_rawset(lua, t);
	lua_pushstring(lua, "uid");
	lua_pushnumber(lua, statbuf.st_uid);
	lua_rawset(lua, t);
	lua_pushstring(lua, "gid");
	lua_pushnumber(lua, statbuf.st_gid);
	lua_rawset(lua, t);
	lua_pushstring(lua, "rdev");
	lua_pushnumber(lua, statbuf.st_rdev);
	lua_rawset(lua, t);
	lua_pushstring(lua, "size");
	lua_pushnumber(lua, statbuf.st_size);
	lua_rawset(lua, t);
	lua_pushstring(lua, "atime");
	lua_pushnumber(lua, statbuf.st_atime);
	lua_rawset(lua, t);
	lua_pushstring(lua, "mtime");
	lua_pushnumber(lua, statbuf.st_mtime);
	lua_rawset(lua, t);
	lua_pushstring(lua, "ctime");
	lua_pushnumber(lua, statbuf.st_ctime);
	lua_rawset(lua, t);
	lua_pushstring(lua, "blksize");
	lua_pushnumber(lua, statbuf.st_blksize);
	lua_rawset(lua, t);
	lua_pushstring(lua, "blocks");
	lua_pushnumber(lua, statbuf.st_blocks);
	lua_rawset(lua, t);
	lua_pushstring(lua, "type");

	switch(statbuf.st_mode & S_IFMT) {
	case S_IFBLK: lua_pushstring(lua, "block-special"); break;
	case S_IFCHR: lua_pushstring(lua, "character-special"); break;
	case S_IFIFO: lua_pushstring(lua, "fifo-special"); break;
	case S_IFREG: lua_pushstring(lua, "regular"); break;
	case S_IFDIR: lua_pushstring(lua, "directory"); break;
	case S_IFLNK: lua_pushstring(lua, "symbolic-link"); break;
	case S_IFSOCK: lua_pushstring(lua, "socket"); break;
	default: lua_pushstring(lua, "unknown");
	}

	lua_rawset(lua, t);
	return 1;
}


/* e2util.readlink(PATH) -> PATH' | nil

   Returns the path pointed to by the symbolic link PATH or nil, if the
   link does not exist.
   */

static int
read_symbolic_link(lua_State *lua)
{
	const char *p = luaL_checkstring(lua, 1);
	int len;

	len = readlink(p, buffer, sizeof(buffer));

	if (len > -1)
		lua_pushlstring(lua, buffer, len);
	else
		lua_pushnil(lua);

	return 1;
}


/* e2util.directory(PATH, [DOTFILES?]) -> TABLE | nil

   Returns an array with the contents of the directory designated by PATH.
   If DOTFILES? is given and true then files beginning with "." are also
   included in the directory listing.
   */

static int
get_directory(lua_State *lua)
{
	const char *p = luaL_checkstring(lua, 1);
	int df = lua_gettop(lua) > 1 && lua_toboolean(lua, 2);
	DIR *dir = opendir(p);

	if (dir == NULL)
		lua_pushnil(lua);
	else {
		struct dirent *de;
		int i = 1;

		lua_newtable(lua);

		for(;;) {
			de = readdir(dir);

			if(de == NULL) break;

			if(df || de->d_name[0] != '.') {
				lua_pushstring(lua, de->d_name);
				lua_rawseti(lua, -2, i++);
			}
		}

		closedir(dir);
	}

	return 1;
}


/* e2util.tempnam(DIR) -> PATH

   Returns a random temporary pathname.
   */

static int
create_temporary_filename(lua_State *lua)
{
	const char *dir = luaL_checkstring(lua, 1);
	lua_pushstring(lua, tempnam(dir, "e2"));
	return 1;
}


/* e2util.exists(PATH, [EXECUTABLE?]) -> BOOL

   Returns true if the file given in PATH exists. If EXECUTABLE? is given
   and true, then it is also checked whether the file is executable.
   */

static int
file_exists(lua_State *lua)
{
	int amode = R_OK;
	const char *f = luaL_checkstring(lua, 1);

	if (lua_gettop(lua) > 1 && lua_toboolean(lua, 2))
		amode = X_OK;

	lua_pushboolean(lua, access(f, amode) == 0);
	return 1;
}


/* e2util.cd(PATH)

   Changes the current working directory to PATH.
   */

static int
change_directory(lua_State *lua)
{
	int rc;
	const char *ptr = luaL_checkstring(lua, 1);
	rc = chdir(ptr);
	if (rc < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}
	lua_pushboolean(lua, 1);
	lua_pushnil(lua);
	return 2;
}

/* e2util.symlink(OLDPATH, NEWPATH)

   Creates a symbolic link named NEWPATH which contains the string OLDPATH.
   */

static int
create_symlink(lua_State *lua)
{
	const char *old = luaL_checkstring(lua, 1);
	const char *new = luaL_checkstring(lua, 2);

	lua_pushboolean(lua, symlink(old, new) == 0);
	return 1;
}


/* e2util.pipe(COMMAND, [ARG...]) -> FDIN, FDOUT, FDERR, PID
   |  nil, ERRORMESSAGE

   Invokes a subcommand and returns two file-descriptors for writing to stdin
   and/or reading from stdout/stderr of the executing subprocess, respectively.
   File-descriptors are named as viewn from the child process.
   */

static int
run_pipe(lua_State *lua)
{
	int in[2], out[2], err[2];
	char **argv;
	int n;

	if(pipe(in) != 0)
		return 0;

	else if(pipe(out) != 0) {
		close(in[0]);
		close(in[1]);
		return 0;
	}
	else if(pipe(err) != 0) {
		close(out[0]);
		close(out[1]);
		close(in[0]);
		close(in[1]);
		return 0;
	}
	else {
		fflush(0);
		pid_t child = fork();

		if (child < 0) {
			close(in[0]);
			close(in[1]);
			close(out[0]);
			close(out[1]);
			close(err[0]);
			close(err[1]);
			goto fail;
		}
		else if (child == 0) {
			close(in[1]);

			if(in[0] != STDIN_FILENO) {
				dup2(in[0], STDIN_FILENO);
				close(in[0]);
			}

			close(out[0]);

			if (out[1] != STDOUT_FILENO) {
				dup2(out[1], STDOUT_FILENO);
				close(out[1]);
			}

			close(err[0]);

			if (err[1] != STDERR_FILENO) {
				dup2(err[1], STDERR_FILENO);
				close(err[1]);
			}

			n = lua_gettop(lua);
			argv = alloca(sizeof(*argv) * (n+1));
			argv[n] = NULL;
			while (n > 0) {
				argv[n-1] = (char *)luaL_checkstring(lua, n);
				n -= 1;
			}
			execvp(argv[0], argv);
			goto fail;
		}
		else {
			close(in[0]);
			close(out[1]);
			close(err[1]);
			lua_pushnumber(lua, in[1]);
			lua_pushnumber(lua, out[0]);
			lua_pushnumber(lua, err[0]);
			lua_pushnumber(lua, child);
			return 4;
		}
	}

fail:
	lua_pushnil(lua);
	lua_pushstring(lua, strerror(errno));
	return 2;
}


/* e2util.wait(PID) -> STATUS, PID
   |  nil, ERRORMESSAGE

   waits for process to terminate and returns exit code.
   */

static int
process_wait(lua_State *lua)
{
	pid_t pid = luaL_checkinteger(lua, 1);
	int rc, status;
	rc = waitpid(pid, &status, 0);
	if (rc < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}
	lua_pushnumber(lua, WEXITSTATUS(status));
	lua_pushnumber(lua, rc);
	return 2;
}


/* e2util.read(FD, NUM) -> STRING
   |  nil, ERRORMESSAGE

   Reads characters from a file-descriptor.
   */

static int
read_fd(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);
	int n = luaL_checkinteger(lua, 2);
	char *buf = (char *)malloc(n);
	int m;

	if(buf == NULL) return 0;

	m = read(fd, buf, n);

	if (m < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		free(buf);
		return 2;
	}
	else
		lua_pushlstring(lua, buf, m);

	free(buf);
	return 1;
}


/* e2util.write(FD, STRING, [NUM]) -> NUM'
   |  nil, ERRORMESSAGE

   Writes characters to a file-descriptor.
   */

static int
write_fd(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);
	size_t len;
	const char *buf = luaL_checklstring(lua, 2, &len);
	int n = lua_gettop(lua) > 2 ? luaL_checkinteger(lua, 3) : len;
	int m;

	m = write(fd, buf, n);

	if (m < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushnumber(lua, m);
	return 1;
}


/* e2util.close(FD) -> true
   |  false, ERRORMESSAGE

   Close file-descriptor, returning "false" if an error occurred or "true"
   otherwise.
   */

static int
close_fd(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);

	if (close(fd) < 0) {
		lua_pushnil(lua);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

/* e2util.poll(TMO_MSEC, {FD...}) -> INDEX, POLLIN, POLLOUT
   Returns 0 on timeout, <0 on error, otherwise indicates which FD triggered.
   When muliple FDs triggered, only one is indicated.
   With a FD given, two boolean values indicate read/writeability.
   */

static int
poll_fd(lua_State *lua)
{
	int tmo = luaL_checkinteger(lua, 1);
	int nfds = 0, f;
	struct pollfd *fds = NULL;
	luaL_checktype(lua, 2, LUA_TTABLE);

	while (1) {
		lua_rawgeti(lua, 2, nfds+1);

		if (lua_isnil(lua, -1))
			break;

		f = luaL_checkinteger(lua, -1);
		lua_pop(lua, 1);
		fds = realloc(fds, (nfds+1) * sizeof(struct pollfd));
		fds[nfds].fd = f;
		fds[nfds].events = POLLIN | POLLOUT;
		fds[nfds].revents = 0;
		nfds += 1;
	}
	f = poll(fds, nfds, tmo);

	if (f > 0) {
		while (--nfds >= 0) {
			if (fds[nfds].revents) {
				free(fds);
				lua_pushnumber(lua, nfds+1);
				lua_pushboolean(lua, fds[nfds].revents & POLLIN);
				lua_pushboolean(lua, fds[nfds].revents & POLLOUT);
				return 3;
			}
		}
	}
	free(fds);
	lua_pushnumber(lua, f);
	return 1;
}

/* e2util.unblock(FD)
   Set file to nonblocking mode
   */

static int
unblock_fd(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);
	int fl = fcntl(fd, F_GETFL);
	fcntl(fd, F_SETFL, fl | O_NONBLOCK);
	return 0;
}


/* e2util.isatty(FD) -> BOOL

   Returns true, if FD refers to a terminal device.
   */

static int
is_terminal(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);
	lua_pushboolean(lua, isatty(fd));
	return 1;
}

/* e2util.umask(VAL)

   Set the umask to VAL
   Returns the previous value of umask
   */

static int
set_umask(lua_State *lua)
{
	int u = luaL_checkinteger(lua, 1);
	int pu = 0;
	pu = umask(u);
	lua_pushinteger(lua, pu);
	return 1;
}

/* e2util.setenv(var, val, overwrite)

*/

static int
do_setenv(lua_State *lua)
{
	const char *var = luaL_checkstring(lua, 1);
	const char *val = luaL_checkstring(lua, 2);
	int overwrite = lua_toboolean(lua, 3);
	int rc;
	rc = setenv(var, val, overwrite != 0);
	lua_pushboolean(lua, rc == 0);
	return 1;

}

/* e2util.unsetenv(var)

*/

static int
do_unsetenv(lua_State *lua)
{
	const char *var = luaL_checkstring(lua, 1);
	int rc;
	rc = unsetenv(var);
	lua_pushboolean(lua, rc == 0);

	return 1;
}

/* e2util.exec()

   call execvp() with the full argument list */

static int
do_exec(lua_State *lua)
{
	const int max_args = 256;
	const char *args[max_args+1];
	int rc, i;
	for (i=0; i<max_args+1; i++) {
		args[i] = luaL_optlstring(lua, i+1, NULL, NULL);
		if (!args[i]) {
			break;
		}
	}
	if( i > max_args) {
		lua_pushboolean(lua, 0);
		return 1;
	}
	args[i] = NULL;
	rc = execvp(args[0], (char * const*)args);
	lua_pushboolean(lua, rc == 0);

	return 1;
}

/* e2util.getpid()

   get the pid of the current process */

static int
do_getpid(lua_State *lua) {
	pid_t pid = getpid();
	if (pid < 0 )
		lua_pushnil(lua);
	else
		lua_pushinteger(lua, pid);
	return 1;
}

/* e2util.catch_interrupt()

   Establish signal handler for SIGINT that aborts. */

static void
lstop(lua_State *L, lua_Debug *ar) {
	lua_sethook(L, NULL, 0, 0);

	/* require e2lib */
	lua_getglobal(L, "require");
	lua_pushstring(L, "e2lib");
	lua_call(L, 1, 1);

	/* load and call interrupt_hook */
	lua_getfield(L, -1, "interrupt_hook");
	lua_remove(L, -2); /* remove e2lib, balance stack */
	lua_call(L, 0, 0);

	/* not reached under normal circumstances */
	fprintf(stderr, "e2: interrupt_hook failed, terminating\n");
	exit(1);
}

static lua_State *globalL;


static void
laction(int i) {
	/* Ignore further signals because lstop() should
	 * terminate the process in an orderly fashion */
	signal(i, SIG_IGN);
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}


static luaL_Reg lib[] = {
	{ "cwd", get_working_directory },
	{ "realpath", get_realpath },
	{ "stat", get_file_statistics },
	{ "readlink", read_symbolic_link },
	{ "directory", get_directory },
	{ "tempnam", create_temporary_filename },
	{ "exists", file_exists },
	{ "cd", change_directory },
	{ "symlink", create_symlink },
	{ "pipe", run_pipe },
	{ "wait", process_wait },
	{ "read", read_fd },
	{ "write", write_fd },
	{ "close", close_fd },
	{ "poll", poll_fd },
	{ "unblock", unblock_fd },
	{ "fork", lua_fork },
	{ "isatty", is_terminal },
	{ "umask", set_umask },
	{ "setenv", do_setenv },
	{ "unsetenv", do_unsetenv },
	{ "exec", do_exec },
	{ "getpid", do_getpid },
	{ NULL, NULL }
};


int luaopen_e2util(lua_State *lua)
{
	luaL_register(lua, "e2util", lib);
	globalL = lua;
	signal(SIGINT, laction);
	return 1;
}
