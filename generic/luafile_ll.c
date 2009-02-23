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
#include <string.h>
#include <unistd.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#ifndef LOCAL
# define ENTRY_POINT luaopen_luafile_ll_global
#else
# define ENTRY_POINT luaopen_luafile_ll_local
#endif

static int 
lua_fopen(lua_State *lua)
{
	FILE *f;
	const char *file, *mode;
	file = luaL_checkstring(lua, 1);
	mode = luaL_checkstring(lua, 2);
	f = fopen(file, mode);
	if(f == NULL) {
		lua_pushnil(lua);
	} else {
		lua_pushlightuserdata(lua, (void *)f);
	}
	return 1;
}

static int
lua_fclose(lua_State *lua)
{
	FILE *f;
	int rc;
	f = (FILE *)lua_topointer(lua, 1);
	if(f) {
		rc = fclose(f);
		lua_pushboolean(lua, (rc == 0));
	} else {
		lua_pushboolean(lua, 0);
	}
	return 1;
}

static int 
lua_fdopen(lua_State *lua)
{
	FILE *f;
	int fd;
	const char *mode;
	fd = luaL_checkinteger(lua, 1);
	mode = luaL_checkstring(lua, 2);
	f = fdopen(fd, mode);
	if(f == NULL) {
		lua_pushnil(lua);
	} else {
		lua_pushlightuserdata(lua, (void *)f);
	}
	return 1;
}

static int
lua_fwrite(lua_State *lua)
{
	FILE *f;
	const char *b;
	int n = 0, rc;
	f = (FILE *)lua_topointer(lua, 1);
	b = luaL_checkstring(lua, 2);
	if(!f || !b) {
		lua_pushboolean(lua, 0);
		return 1;
	}
	n = strlen(b);
	rc = fwrite(b, 1, n, f);
	lua_pushboolean(lua, (rc == n));
	return 1;
}

static int
lua_fread(lua_State *lua)
{
	char buf[16384];
	int rc;
	FILE *f;
	f = (FILE *)lua_topointer(lua, 1);
	rc = fread(buf, 1, sizeof(buf), f);
	if(rc>0) {
	  lua_pushlstring(lua, buf, rc);
	} else if (rc == 0) {
		lua_pushstring(lua, "");
	} else {
		lua_pushnil(lua);
	}
	return 1;
}

static int
lua_fgets(lua_State *lua)
{
	FILE *f;
	char buf[16384], *rc;
	f = (FILE *)lua_topointer(lua, 1);
	if(!f) {
		lua_pushnil(lua);
		return 1;
	}
	rc = fgets(buf, sizeof(buf), f);
	if(!rc) {
		lua_pushnil(lua);
		return 1;
	}
	lua_pushstring(lua, buf);
	return 1;
}

static int
lua_fseek(lua_State *lua)
{
	int rc;
	long offset;
	FILE *f;
	f = (FILE *)lua_topointer(lua, 1);
	offset = luaL_checklong(lua, 2);
	if(!f) {
		lua_pushboolean(lua, 0);
		return 1;
	}
	rc = fseek(f, offset, SEEK_SET);
	lua_pushboolean(lua, rc == 0);
	return 1;
}

static int
lua_fflush(lua_State *lua)
{
	int rc;
	FILE *f;
	f = (FILE *)lua_topointer(lua, 1);
	if(!f) {
		lua_pushnil(lua);
		return 1;
	}
	rc = fflush(f);
	lua_pushboolean(lua, rc == 0);
	return 1;
}

static int
lua_pipe(lua_State *lua)
{
	int fd[2];
	int rc;
	rc = pipe(fd);
	lua_pushboolean(lua, rc == 0);
	lua_pushnumber(lua, fd[0]);
	lua_pushnumber(lua, fd[1]);
	return 3;
}

static int
lua_fileno(lua_State *lua)
{
	FILE *f;
	int fd;
	f = (FILE *)lua_topointer(lua, 1);
	if(!f) {
		lua_pushnil(lua);
		return 1;
	}
	fd = fileno(f);
	lua_pushinteger(lua, fd);
	return 1;
}

static int
lua_eof(lua_State *lua)
{
	FILE *f;
	int eof;
	f = (FILE *)lua_topointer(lua, 1);
	if(!f) {
		lua_pushnil(lua);
		return 1;
	}
	eof = feof(f);
	lua_pushboolean(lua, eof);
	return 1;
}

static int
lua_setlinebuf(lua_State *lua)
{
	FILE *f;
	f = (FILE *)lua_topointer(lua, 1);
	if(!f) {
		lua_pushboolean(lua, 0);
		return 1;
	}	
	setlinebuf(f);
	lua_pushboolean(lua, 1);
	return 1;
}

static int
lua_dup2(lua_State *lua)
{
	int oldfd, newfd, rc;
	oldfd = luaL_checkinteger(lua, 1);
	newfd = luaL_checkinteger(lua, 2);
	rc = dup2(oldfd, newfd);
	lua_pushboolean(lua, (rc == 0));
	return 1;
}

static luaL_Reg lib[] = {
  { "fopen", lua_fopen },
  { "fdopen", lua_fdopen },
  { "fclose", lua_fclose },
  { "fwrite", lua_fwrite },
  { "fread", lua_fread },
  { "fseek", lua_fseek },
  { "fflush", lua_fflush },
  { "fileno", lua_fileno },
  { "feof", lua_eof },
  { "fgets", lua_fgets },
  { "setlinebuf", lua_setlinebuf },
  { "pipe", lua_pipe },
  { "dup2", lua_dup2 },
  { NULL, NULL }
};

int ENTRY_POINT(lua_State *lua)
{
  luaL_register(lua, "luafile_ll", lib);
  return 1;
}

