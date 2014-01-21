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
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static int
eio_fopen(lua_State *lua)
{
	FILE *f;
	const char *file, *mode;
	int fd = -1;

	file = luaL_checkstring(lua, 1);
	mode = luaL_checkstring(lua, 2);

	f = fopen(file, mode);
	if (f == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	fd = fileno(f);
	if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0) {
		lua_pushfstring(lua, "%s: fcntl(%d): %s: %s", __func__,
		    fd, file, strerror(errno));
		lua_error(lua);
	}

	lua_pushlightuserdata(lua, f);
	return 1;
}

static int
eio_fclose(lua_State *lua)
{
	FILE *f;

	f = lua_touserdata(lua, 1);
	if (f == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua,
		    "eio_fclose: one or more arguments of wrong type/missing");
		return 2;
	}

	if (fclose(f) == EOF) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

static int
eio_close(lua_State *L)
{
	int fd, rc;

	fd = luaL_checkinteger(L, 1);
	rc = close(fd);
	if (rc < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
	}

	lua_pushboolean(L, 1);
	return 1;
}

static int
eio_fdopen(lua_State *lua)
{
	FILE *f;
	int fd;
	const char *mode;

	fd = luaL_checkinteger(lua, 1);
	mode = luaL_checkstring(lua, 2);

	f = fdopen(fd, mode);
	if (f == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushlightuserdata(lua, f);
	return 1;
}

static int
eio_fwrite(lua_State *lua)
{
	FILE *f;
	const char *b;
	size_t sz, ret;

	f = lua_touserdata(lua, 1);
	b = lua_tolstring(lua, 2, &sz);
	if (f == NULL || b == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua,
		    "eio_fwrite: one or more arguments of wrong type/missing");
		return 2;
	}

	ret = fwrite(b, 1, sz, f);
	if (ret != sz) {
		if (ferror(f)) {
			lua_pushboolean(lua, 0);
			lua_pushstring(lua, strerror(errno));
			return 2;
		}

		if (feof(f)) {
			/* What does end of file on write mean?
			 * Signal an error */
			lua_pushboolean(lua, 0);
			lua_pushstring(lua, "eio_fwrite: end of file");
			return 2;
		}
	}

	lua_pushboolean(lua, 1);
	return 1;
}

static int
eio_write(lua_State *L)
{
	int fd;
	const char *buf;
	size_t sz;
	ssize_t wsz;

	fd = luaL_checkinteger(L, 1);
	buf = lua_tolstring(L, 2, &sz);

	wsz = write(fd, buf, sz);
	if (wsz < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		lua_pushinteger(L, errno);
		return 3;
	}

	lua_pushinteger(L, wsz);
	return 1;
}

static char *
get_read_buf(size_t sz)
{
	static char *buf;
	static size_t bufsz;

	if (sz > bufsz) {
		free(buf);
		bufsz = 0;
		buf = malloc(sz);
		if (!buf)
			return NULL;

		bufsz = sz;
	}

	return buf;
}

static int
eio_fread(lua_State *lua)
{
	char *buf;
	FILE *f;
	size_t ret, sz;

	f = lua_touserdata(lua, 1);
	sz = lua_tointeger(lua, 2);
	if (f == NULL || sz == 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua,
		    "eio_fread: one or more arguments of wrong type/missing");
		return 2;
	}

	buf = get_read_buf(sz);
	if (buf == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	ret = fread(buf, 1, sz, f);
	if (ret != sz) {
		if (ferror(f)) {
			lua_pushboolean(lua, 0);
			lua_pushstring(lua, strerror(errno));
			return 2;
		}

		if (ret <= 0 && feof(f)) {
			/* ret <= 0: do not discard data on short reads,
			 * only signal EOF when all data is returned. */
			lua_pushstring(lua, "");
			return 1;
		}
	}

	lua_pushlstring(lua, buf, ret);
	return 1;
}

static int
eio_read(lua_State *L)
{
	int fd;
	size_t sz;
	ssize_t rsz;
	char *buf;


	fd = luaL_checkinteger(L, 1);
	sz = luaL_checkinteger(L, 2);

	buf = get_read_buf(sz);
	if (buf == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
	}

	rsz = read(fd, buf, sz);
	if (rsz < 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		lua_pushinteger(L, errno);
		return 3;
	}

	lua_pushlstring(L, buf, rsz);
	return 1;
}

static int
eio_fgetc(lua_State *L)
{
	FILE *f;
	int c;
	char ch;

	f = lua_touserdata(L, 1);
	if (f == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L,
		    "eio_fgetc: argument of wrong type or missing");
		return 2;
	}

	c = fgetc(f);
	if (c == EOF) {
		if (feof(f)) {
			lua_pushstring(L, "");
			return 1;
		}

		if (ferror(f)) {
			lua_pushboolean(L, 0);
			lua_pushstring(L, strerror(errno));
			return 2;
		}

	}

	ch = (char)c;
	lua_pushlstring(L, &ch, 1);
	return 1;
}

static int
eio_pipe(lua_State *L)
{
	int fd[2];
	int rc;

	rc = pipe(fd);
	if (rc != 0) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
	}

	lua_pushnumber(L, fd[0]);
	lua_pushnumber(L, fd[1]);
	return 2;
}

static int
eio_fileno(lua_State *lua)
{
	FILE *f;
	int fd;

	f = lua_touserdata(lua, 1);
	if (f == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua,
		    "eio_fileno: one or more arguments of wrong type/missing");
		return 2;
	}
	fd = fileno(f);
	lua_pushinteger(lua, fd);
	return 1;
}

static int
eio_feof(lua_State *lua)
{
	FILE *f;

	f = lua_touserdata(lua, 1);
	if (f == NULL) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua,
		    "eio_feof: arguments wrong type or missing");
		return 2;
	}

	lua_pushboolean(lua, feof(f));
	return 1;
}

static int
eio_setlinebuf(lua_State *lua)
{
	FILE *f;

	f = lua_touserdata(lua, 1);
	if (!f) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, "eio_setlinebuf: one or more arguments "
		    "of wrong type/missing");
		return 2;
	}

	setlinebuf(f);
	lua_pushboolean(lua, 1);
	return 1;
}

static int
eio_setunbuffered(lua_State *lua)
{
	FILE *f;

	f = lua_touserdata(lua, 1);
	if (!f) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, "eio_setunbuffered: one or more arguments "
		    "of wrong type/missing");
		return 2;
	}

	setbuf(f, NULL);
	lua_pushboolean(lua, 1);
	return 1;
}

static int
eio_dup2(lua_State *lua)
{
	int oldfd, newfd, rc;

	oldfd = luaL_checkinteger(lua, 1);
	newfd = luaL_checkinteger(lua, 2);

	rc = dup2(oldfd, newfd);
	if (rc < 0) {
		lua_pushboolean(lua, 0);
		lua_pushstring(lua, strerror(errno));
		return 2;
	}

	lua_pushboolean(lua, 1);
	return 1;
}

static int
eio_cloexec(lua_State *lua)
{
	int fd = -1, rc, cloexec;
	FILE *f = NULL;

	if (lua_isnumber(lua, 1)) {
		fd = luaL_checkint(lua, 1);
	} else if (lua_istable(lua, 1)) {
		lua_pushstring(lua, "handle"); // key
		lua_gettable(lua, 1);
		if (!lua_islightuserdata(lua, -1))
		    luaL_argerror(lua, 1, "not a eio table");
		f = (FILE *)lua_topointer(lua, -1);
	} else if (lua_isuserdata(lua, 1)) {
		FILE **p;
		p = (FILE **)luaL_checkudata(lua, 1, LUA_FILEHANDLE);
		if (*p == NULL) {
			lua_pushfstring(lua, "%s: closed lua filehandle",
			    __func__);
			lua_error(lua);
		}
		f = *p;
	}

	if (f) {
		fd = fileno(f);
	}

	if (fd < 0) {
		luaL_argerror(lua, 1, "fd/eio/io file required");
	}

	if (lua_isboolean(lua, 2)) {
		cloexec = lua_toboolean(lua, 2);
	} else {
		luaL_argerror(lua, 2, "boolean required");
	}

	rc = fcntl(fd, F_SETFD, cloexec ? FD_CLOEXEC : 0);
	lua_pushboolean(lua, (rc == 0));
	return 1;
}

static luaL_Reg lib[] = {
  { "cloexec", eio_cloexec },
  { "close", eio_close },
  { "dup2", eio_dup2 },
  { "fclose", eio_fclose },
  { "fdopen", eio_fdopen },
  { "feof", eio_feof },
  { "fgetc", eio_fgetc },
  { "fileno", eio_fileno },
  { "fopen", eio_fopen },
  { "fread", eio_fread },
  { "fwrite", eio_fwrite },
  { "pipe", eio_pipe },
  { "read", eio_read },
  { "setlinebuf", eio_setlinebuf },
  { "setunbuffered", eio_setunbuffered },
  { "write", eio_write },
  { NULL, NULL }
};

int
luaopen_leio(lua_State *lua)
{
	luaL_Reg *next;

	lua_newtable(lua);
	for (next = lib; next->name != NULL; next++) {
		lua_pushcfunction(lua, next->func);
		lua_setfield(lua, -2, next->name);
	}

	return 1;
}

