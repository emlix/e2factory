/*
   e2factory, the emlix embedded build system

   Copyright (C) 2009 Gordon Hecker <gh@emlix.com>, emlix GmbH

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

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "sha1.h"

static int
init(lua_State *L)
{
	SHA1_CTX *ctx = malloc(sizeof(SHA1_CTX));
	if (ctx == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, strerror(errno));
		return 2;
	}

	SHA1Init(ctx);
	lua_pushlightuserdata(L, ctx);
	return 1;
}

static int
update(lua_State *L)
{
	const char *s;
	size_t len;
	SHA1_CTX *ctx;

	ctx = lua_touserdata(L, 1);
	if (ctx == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "lsha1.update: missing sha1 context");
		return 2;
	}

	s = lua_tolstring(L, 2, &len);
	if (s == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "lsha1.update: data missing or of wrong type");
		return 2;
	}

	SHA1Update(ctx, (unsigned char *)s, len);
	lua_pushboolean(L, 1);

	return 1;
}

static int
final(lua_State *L)
{
	SHA1_CTX *ctx;
	unsigned char digest[20];
	char s[41];
	int i;

	ctx = lua_touserdata(L, 1);
	if (ctx == NULL) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "lsha1.final: missing sha1 context");
		return 2;
	}

	SHA1Final(digest, ctx);

	memset(ctx, 0, sizeof(SHA1_CTX));
	free(ctx);

	for (i = 0; i < 20; i++) {
		snprintf(s + i*2, 2+1,  "%02x", digest[i]);
	}
	lua_pushstring(L, s);

	return 1;
}

static luaL_reg lib[] = {
	{ "init",	init },
	{ "update",	update },
	{ "final",	final },
	{ NULL,		NULL }
};

int luaopen_lsha1(lua_State *L)
{
	luaL_Reg *next;

	lua_newtable(L);
	for (next = lib; next->name != NULL; next++) {
		lua_pushcfunction(L, next->func);
		lua_setfield(L, -2, next->name);
	}

	return 1;
}
