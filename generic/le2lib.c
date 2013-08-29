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

static int
lua_fork(lua_State *lua)
{
	int rc;
	fflush(0);
	rc = fork();

	if(rc < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushnumber(lua, rc);
	return 1;
}

static int
get_working_directory(lua_State *lua)
{
	char *cwd = getcwd(buffer, sizeof(buffer));

	if (cwd == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_pushstring(lua, buffer);

	return 1;
}

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
		lua_pushboolean(lua, 0);
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
	lua_pushstring(lua, "atime_nsec");
	lua_pushnumber(lua, statbuf.st_atim.tv_nsec);
	lua_rawset(lua, t);
	lua_pushstring(lua, "mtime");
	lua_pushnumber(lua, statbuf.st_mtim.tv_sec);
	lua_rawset(lua, t);
	lua_pushstring(lua, "mtime_nsec");
	lua_pushnumber(lua, statbuf.st_mtim.tv_nsec);
	lua_rawset(lua, t);
	lua_pushstring(lua, "ctime");
	lua_pushnumber(lua, statbuf.st_ctime);
	lua_rawset(lua, t);
	lua_pushstring(lua, "ctime_nsec");
	lua_pushnumber(lua, statbuf.st_ctim.tv_nsec);
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

static int
get_directory(lua_State *lua)
{
	const char *p = luaL_checkstring(lua, 1);
	int df = lua_gettop(lua) > 1 && lua_toboolean(lua, 2);
	DIR *dir = opendir(p);
	struct dirent *de;
	int i = 1;

	if (dir == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_newtable(lua);

	for (;;) {
		errno = 0;
		de = readdir(dir);

		if (de == NULL) {
			if (errno) {
				lua_pop(lua, 1); /* remove table */

				lua_pushboolean(lua, 0);
				lua_pushstring(lua, strerror(errno));

				closedir(dir);

				return 2;
			}

			break;
		}

		if (strcmp(de->d_name, ".") == 0 ||
		    strcmp(de->d_name, "..") == 0)
			    continue;

		if (df || de->d_name[0] != '.') {
			lua_pushstring(lua, de->d_name);
			lua_rawseti(lua, -2, i++);
		}
	}

	closedir(dir);

	return 1;
}

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
	return 1;
}

static int
create_symlink(lua_State *lua)
{
	const char *old = luaL_checkstring(lua, 1);
	const char *new = luaL_checkstring(lua, 2);

	 if (symlink(old, new) != 0) {
		 lua_pushboolean(lua, 0);
		 lua_pushstring(lua, strerror(errno));

		 return 2;
	 }

	lua_pushboolean(lua, 1);
	return 1;
}

static int
do_hardlink(lua_State *lua)
{
	const char *old = luaL_checkstring(lua, 1);
	const char *new = luaL_checkstring(lua, 2);

	 if (link(old, new) != 0) {
		 lua_pushboolean(lua, 0);
		 lua_pushstring(lua, strerror(errno));

		 return 2;
	 }

	lua_pushboolean(lua, 1);
	return 1;
}

static int
process_wait(lua_State *lua)
{
	pid_t pid = luaL_checkinteger(lua, 1);
	int rc, status;
	rc = waitpid(pid, &status, 0);
	if (rc < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushnumber(lua, WEXITSTATUS(status));
	lua_pushnumber(lua, rc);

	return 2;
}

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

static int
unblock_fd(lua_State *lua)
{
	int fd = luaL_checkinteger(lua, 1);
	int fl = fcntl(fd, F_GETFL);
	fcntl(fd, F_SETFL, fl | O_NONBLOCK);
	return 0;
}

static int
set_umask(lua_State *lua)
{
	int u = luaL_checkinteger(lua, 1);
	int pu = 0;
	pu = umask(u);
	lua_pushinteger(lua, pu);
	return 1;
}

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

static int
do_unsetenv(lua_State *lua)
{
	const char *var = luaL_checkstring(lua, 1);
	int rc;
	rc = unsetenv(var);
	lua_pushboolean(lua, rc == 0);

	return 1;
}

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

static int
do_getpid(lua_State *lua) {
	pid_t pid = getpid();
	lua_pushinteger(lua, pid);
	return 1;
}

static int
do_unlink(lua_State *lua)
{
	const char *pathname = luaL_checkstring(lua, 1);

	if (unlink(pathname) != 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

/* Reset all (possible) signals back to their default settings */
static int
signal_reset(lua_State *L)
{
	int s;
	struct sigaction act;

	for (s = 1; s < NSIG; s++) {
		if (sigaction(s, NULL, &act) < 0)
			break; /* end of signals */

		switch (s) {
		case SIGINT:
			/* used by e2factory */
			continue;
		case SIGFPE:
			act.sa_handler = SIG_IGN;
			break;
		case SIGKILL:
		case SIGSTOP:
		case SIGCONT:
			continue;
		default:
			act.sa_handler = SIG_DFL;
		}

		if (sigaction(s, &act, NULL) < 0) {
			lua_pushboolean(L, 0);
			lua_pushstring(L, strerror(errno));
			return 2;
		}
	}

	lua_pushboolean(L, 1);
	return 1;
}


/* closes all file descriptors >= fd */
static int
closefrom(lua_State *L)
{
	DIR *d = NULL;
	int myself, from, eno = 0;
	struct dirent *de;

	from = luaL_checkinteger(L, 1);

	d = opendir("/proc/self/fd");
	if (!d)
		goto error;
	/* make sure we don't close our directory fd yet */
	myself = dirfd(d);
	if (myself < 0)
		goto error;

	while ((de = readdir(d)) != NULL) {
		int fd;

		if (de->d_name[0] < '0' || de->d_name[0] > '9')
			continue;

		fd = atoi(de->d_name);
		if (fd < from || fd == myself)
			continue;

		close(fd);
	}

	closedir(d);
	lua_pushboolean(L, 1);
	return 1;
error:
	eno = errno;
	if (d)
		closedir(d);
	lua_pushboolean(L, 0);
	lua_pushstring(L, strerror(eno));
	return 2;
}

static int
do_rmdir(lua_State *lua)
{
	const char *pathname = luaL_checkstring(lua, 1);

	if (rmdir(pathname) != 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

static int
do_kill(lua_State *lua)
{
	pid_t pid = luaL_checkinteger(lua, 1);
	int sig = luaL_checkinteger(lua, 2);

	if (kill(pid, sig) < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}


/*
 * Hook that gets called once an interrupt has been requested.
 * Calls e2lib.interrupt_hook() to deal with any cleanup that might be required.
 */
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


/*
 * Interrupt handler sets a hook to stop the interpreter from
 * continuing normal execution at the next possible spot.
 */
static void
laction(int i) {
	/* Ignore further signals because lstop() should
	 * terminate the process in an orderly fashion */
	signal(i, SIG_IGN);
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}


static luaL_Reg lib[] = {
	{ "chdir", change_directory },
	{ "closefrom", closefrom },
	{ "cwd", get_working_directory },
	{ "directory", get_directory },
	{ "exists", file_exists },
	{ "fork", lua_fork },
	{ "getpid", do_getpid },
	{ "hardlink", do_hardlink },
	{ "kill", do_kill },
	{ "poll", poll_fd },
	{ "rmdir", do_rmdir },
	{ "setenv", do_setenv },
	{ "signal_reset", signal_reset },
	{ "stat", get_file_statistics },
	{ "symlink", create_symlink },
	{ "umask", set_umask },
	{ "unblock", unblock_fd },
	{ "unlink", do_unlink },
	{ "wait", process_wait },
	{ NULL, NULL }
};


int luaopen_le2lib(lua_State *lua)
{
	luaL_Reg *next;

	lua_newtable(lua);
	for (next = &lib; next->name != NULL; next++) {
		lua_pushcfunction(lua, next->func);
		lua_setfield(lua, -2, next->name);
	}

	/* Establish signal handler catching SIGINT for orderly shutdown */
	globalL = lua;
	signal(SIGINT, laction);

	return 1;
}
