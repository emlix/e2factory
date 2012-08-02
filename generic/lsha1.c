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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "sha1.h"

#define MODULE_NAME	"sha1"
#define MODULE_VERSION	"1"
#define LUA_OBJECT_ID	"sha1_ctx"

/*
 * __tostring(sha1_ctx) generate a string representation
 * returns a string
 */
static int sha1_tostring(lua_State *L)
{
	SHA1_CTX *ctx;
	ctx = luaL_checkudata(L, 1, LUA_OBJECT_ID);
	lua_pushfstring(L, "%s (%p)", LUA_OBJECT_ID, ctx);
	return 1;
}

/*
 * update(sha1_ctx, string) update a sha1 context with data from string
 * returns bool
 */
static int sha1_update(lua_State *L)
{
	const char *s;
	size_t len;
	SHA1_CTX *ctx;
	ctx = luaL_checkudata(L, 1, LUA_OBJECT_ID);
	s = luaL_checklstring(L, 2, &len);
	SHA1Update(ctx, (unsigned char *)s, len);
	return 0;
}

/*
 * final(sha1_ctx) finalizes the sha1 context
 * returns string: the digest
 */
static int sha1_final(lua_State *L)
{
	SHA1_CTX *ctx;
	unsigned char digest[20];
	char s[41];
	int i;
	ctx = luaL_checkudata(L, 1, LUA_OBJECT_ID);
	memset(digest, 0, sizeof(digest));
	SHA1Final(digest, ctx);
	for(i=0; i<20; i++) {
		sprintf(&s[2*i], "%02X", digest[i]);
	}
	lua_pushstring(L, s);
	return 1;
}

static const luaL_reg sha1_methods[] =
{
	{"update",		sha1_update},
	{"final",		sha1_final},
	{NULL,			NULL}
};

static const luaL_reg sha1_meta[] =
{
	{"__tostring",    sha1_tostring},
	{NULL,			NULL}
};

/*
 * init() initialize a sha1 context
 * returns sha1_ctx
 */
static int sha1_init(lua_State *L)
{
	SHA1_CTX *ctx = (SHA1_CTX *)lua_newuserdata(L, sizeof(SHA1_CTX));
	SHA1Init(ctx);

	if(luaL_newmetatable(L, LUA_OBJECT_ID)) {
		luaL_register(L, 0, sha1_meta);
		lua_pushliteral(L, "__index");
		lua_newtable(L);
		luaL_register(L, 0, sha1_methods);
		lua_rawset(L, -3);
	}
	lua_setmetatable(L, -2);
	return 1;
}

static const luaL_reg R[] =
{
	{"sha1_init",		sha1_init},
	{NULL,			NULL}
};

LUALIB_API int luaopen_sha1(lua_State *L)
{
	luaL_register(L, MODULE_NAME, R);
	lua_pushliteral(L, "version");
	lua_pushliteral(L, MODULE_VERSION);
	lua_settable(L,-3);
	return 1;
}
