/*
 * Copyright (C) 2007-2017 emlix GmbH, see file AUTHORS
 *
 * This file is part of e2factory, the emlix embedded build system.
 * For more information see http://www.e2factory.org
 *
 * e2factory is a registered trademark of emlix GmbH.
 *
 * e2factory is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 */

#include <sys/utsname.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <signal.h>
#include <string.h>
#include <poll.h>
#include <fcntl.h>
#include <ctype.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static char buffer[PATH_MAX + 1];

static int
lua_fork(lua_State *lua)
{
	int rc;

	rc = fork();
	if (rc < 0) {
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
		int e = errno;
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(e));
		lua_pushinteger(lua, e);
		return 3;
	}

	if (WIFEXITED(status)) {
		/* Normal exit case */
		lua_pushnumber(lua, WEXITSTATUS(status));
		lua_pushnumber(lua, rc);
		return 2;
	} else if (WIFSIGNALED(status)) {
		/* Signal exit case */
		lua_pushnumber(lua, WTERMSIG(status) + 128); // what dash does
		lua_pushnumber(lua, rc);
		lua_pushnumber(lua, WTERMSIG(status));
		return 3;
	}

	/* Job control status but option is unset */
	return luaL_error(lua, "process_wait: unhandled case, please report");
}

static int
poll_fd(lua_State *lua)
{
	int tmo = luaL_checkinteger(lua, 1);
	int nfds = 0, f, index = 0;
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
	if (f < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		free(fds);
		return 2;
	}

	/* We want to return a table containing all selected fds looking like
	 * this:
	 * {
	 *	{ fd = 3, fdvecpos=1, POLLIN = true, POLLOUT = false },
	 *	{ fd = 5, fdvecpos=2, POLLIN = false, POLLOUT = false },
	 *	...
	 * }
	 */

	lua_newtable(lua);

	while (index < f && --nfds >= 0) {
		if (fds[nfds].revents) {
			lua_createtable(lua, 0, 4); /* 4 elements */

			lua_pushliteral(lua, "fd");
			lua_pushnumber(lua, fds[nfds].fd);
			lua_rawset(lua, -3);

			lua_pushliteral(lua, "fdvecpos");
			lua_pushnumber(lua, nfds+1);
			lua_rawset(lua, -3);

			lua_pushliteral(lua, "POLLIN");
			lua_pushboolean(lua, fds[nfds].revents & POLLIN);
			lua_rawset(lua, -3);

			lua_pushliteral(lua, "POLLOUT");
			lua_pushboolean(lua, fds[nfds].revents & POLLOUT);
			lua_rawset(lua, -3);

			/* commit table to newtable at index */
			lua_rawseti(lua, -2, ++index);
		}
	}

	free(fds);
	return 1;
}

static int
do_rename(lua_State *L)
{
	int e;
	const char *src = luaL_checkstring(L, 1);
	const char *dst = luaL_checkstring(L, 2);

	if (rename(src, dst) == 0) {
		lua_pushboolean(L, 1);
		return 1;
	}

	e = errno;
	lua_pushboolean(L, 0);
	lua_pushstring(L, strerror(e));
	lua_pushinteger(L, e);
	return 3;
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
	rc = setenv(var, val, overwrite);
	if (rc != 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

#if 0
static int
do_unsetenv(lua_State *lua)
{
	const char *var = luaL_checkstring(lua, 1);
	int rc;
	rc = unsetenv(var);
	lua_pushboolean(lua, rc == 0);

	return 1;
}
#endif

static int
do_execvp(lua_State *L)
{
	const char *file;
	char **argv;
	size_t argc;
	int i = 0;

	file = lua_tostring(L, 1);
	if (file == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "do_execvp: missing/wrong file argument");
		return 2;
	}

	if (!lua_istable(L, 2)) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "do_execvp: missing/wrong argv argument");
		return 2;
	}

	argc = lua_objlen(L, 2);
	if (argc == 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "do_execvp: 1+ argv arguments required");
		return 2;
	}

	argv = malloc((argc+1) * sizeof(char *));
	if (argv == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "do_execvp: 1+ argv arguments required");
		return 2;
	}

	for (; i < argc; i++) {
		lua_rawgeti(L, 2, i+1); /* table index starts at 1 */
		argv[i] = (char *)lua_tostring(L, lua_gettop(L));
	}
	argv[i] = NULL;

	execvp(file, argv);

	/* If it returns, something is wrong */
	free(argv);
	lua_pushboolean(L, 0);
	lua_pushstring(L, strerror(errno));

	return 2;
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
do_mkdir(lua_State *lua)
{
	const char *pathname = luaL_checkstring(lua, 1);
	mode_t mode = 0777;

	if (lua_gettop(lua) > 1)
		mode = luaL_checkinteger(lua, 2);

	if (mkdir(pathname, mode) != 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		lua_pushinteger(lua, errno);

		return 3;
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

static int
do_uname_machine(lua_State *lua)
{
	struct utsname uts;

	if (uname(&uts) != 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));

		return 2;
	}

	lua_pushstring(lua, uts.machine);

	return 1;
}

static int
do_chmod(lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
	mode_t mode = luaL_checkinteger(L, 2);

	if (chmod(path, mode) != 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));

		return 2;
	}

	lua_pushboolean(L, 1);
	return 1;
}

static int
do_mkdtemp(lua_State *L)
{
	const char *template_in = luaL_checkstring(L, 1);
	char template[PATH_MAX];

	if (snprintf(template, PATH_MAX, "%s", template_in)
	    >= PATH_MAX) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "template does not fit in PATH_MAX");

		return 2;
	}

	if (mkdtemp(template) == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));

		return 2;
	}

	lua_pushboolean(L, 1);
	lua_pushnil(L);
	lua_pushstring(L, template);

	return 3;
}

static int
do_mkstemp(lua_State *L)
{
	char template[PATH_MAX];
	const char *template_in = luaL_checkstring(L, 1);
	int fd;

	if (snprintf(template, PATH_MAX, "%s", template_in)
	    >= PATH_MAX) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "template does not fit in PATH_MAX");

		return 2;
	}

	fd = mkstemp(template);
	if (fd < 0)  {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));

		return 2;
	}

	lua_pushboolean(L, 1);
	lua_pushnil(L);
	lua_pushstring(L, template);
	lua_pushnumber(L, fd);

	return 4;
}

/* Reset all (possible) signals to their default settings */
static int
signal_reset(lua_State *L)
{
	int s;
	struct sigaction act;

	if (prctl(PR_SET_PDEATHSIG, 0) < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
	}

	for (s = 1; s < NSIG; s++) {
		if (sigaction(s, NULL, &act) < 0)
			break; /* end of signals */

		switch (s) {
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
		/* No SA_RESTART */
		act.sa_flags = 0;
		if (sigaction(s, &act, NULL) < 0) {
			lua_pushboolean(L, 0);
			lua_pushstring(L, strerror(errno));
			return 2;
		}
	}

	lua_pushboolean(L, 1);
	return 1;
}

/*
 * Hook that gets called once an interrupt has been requested.
 * Calls e2lib.interrupt_hook() to deal with any cleanup that might be required.
 */
static void
lua_signal_handler(lua_State *L, lua_Debug *ar)
{
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
	fprintf(stderr, "e2: calling interrupt_hook failed, terminating\n");
	exit(1);
}

/* Lua context for signal handler */
static lua_State *globalL = NULL;
/* Are we in shutdown? */
static volatile sig_atomic_t signal_shutdown = 0;
/* First signal that triggered shutdown */
static volatile sig_atomic_t signal_received_first = 0;


/*
 * Interrupt handler sets a hook to stop the interpreter from
 * continuing normal execution at the next possible spot.
 */
static void
signal_handler(int sig)
{
	/*
	 * It's normal for subsequent signals to occur (eg. SIGPIPE)
	 * Ignore signals after they occurred once
	 */
	struct sigaction sa;
	sigaction(sig, NULL, &sa);
	sa.sa_handler = SIG_IGN;

	if (sigaction(sig, &sa, NULL) < 0)
		fprintf(stderr, "e2: signal_handler: sigaction failed!\n");

	/* Make sure we don't install lua_signal_handler more than once */
	if (signal_shutdown)
		return;

	signal_shutdown = 1;
	signal_received_first = sig;
	if (globalL) {
		lua_sethook(globalL, lua_signal_handler,
		    LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
	} else {
		fprintf(stderr, "e2: signal_handler: missing lua context\n");
		exit(1);
	}
}

/* Install signal handler for all signals of concern */
static int
signal_install(lua_State *L)
{
	int i;
	struct sigaction sa;
	int signals[] = {
		SIGINT,
		SIGTERM,
		SIGPIPE,
		SIGHUP,
		0
	};

	/* Lua context for use in signal handler */
	globalL = L;

	sa.sa_handler = signal_handler;
	sa.sa_flags = 0;
	sigemptyset(&sa.sa_mask);

	for (i = 0; signals[i] != 0; i++) {
		if (sigaction(signals[i], &sa, NULL) < 0) {
			lua_pushboolean(L, 0);
			lua_pushstring(L, strerror(errno));
			return 2;
		}
	}

	/* Notify us if the parent dies for whatever reason */
	if (prctl(PR_SET_PDEATHSIG, SIGINT) < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
	}

	lua_pushboolean(L, 1);
	return 1;
}

/* Return the first received signal  triggering shutdown */
static int
signal_received(lua_State *L)
{
	char *s = NULL;

	if (signal_received_first) {
		s = strsignal(signal_received_first);
	} else {
		s = "";
	}

	lua_pushstring(L, s);
	lua_pushinteger(L, signal_received_first);
	return 2;
}

static luaL_Reg lib[] = {
	{ "chdir", change_directory },
	{ "chmod", do_chmod },
	{ "closefrom", closefrom },
	{ "cwd", get_working_directory },
	{ "directory", get_directory },
	{ "execvp", do_execvp },
	{ "exists", file_exists },
	{ "fork", lua_fork },
	{ "getpid", do_getpid },
	{ "hardlink", do_hardlink },
	{ "kill", do_kill },
	{ "mkdir", do_mkdir },
	{ "mkdtemp", do_mkdtemp },
	{ "mkstemp", do_mkstemp },
	{ "poll", poll_fd },
	{ "rename", do_rename },
	{ "rmdir", do_rmdir },
	{ "setenv", do_setenv },
	{ "signal_reset", signal_reset },
	{ "signal_install", signal_install },
	{ "signal_received", signal_received },
	{ "stat", get_file_statistics },
	{ "symlink", create_symlink },
	{ "umask", set_umask },
	{ "uname_machine", do_uname_machine },
	{ "unblock", unblock_fd },
	{ "unlink", do_unlink },
	{ "wait", process_wait },
	{ NULL, NULL }
};


int
luaopen_le2lib(lua_State *lua)
{
	luaL_Reg *next;

	lua_newtable(lua);
	for (next = lib; next->name != NULL; next++) {
		lua_pushcfunction(lua, next->func);
		lua_setfield(lua, -2, next->name);
	}

	return 1;
}
