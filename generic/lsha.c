/*
 * Copyright (C) 2016 emlix GmbH, see file AUTHORS
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

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "sha1.h"
#include "sha2.h"

#define TYPE_SHA1 "SHA1_CTX"
#define TYPE_SHA256 "SHA256_CTX"

int
lsha1_init(lua_State *L)
{
	SHA1_CTX *ctx = lua_newuserdata(L, sizeof(SHA1_CTX));
	luaL_newmetatable(L, TYPE_SHA1);
	lua_setmetatable(L, 1);
	SHA1Init(ctx);
	return 1;
}

int
lsha1_update(lua_State *L)
{
	SHA1_CTX *ctx;
	const char* data;
	size_t sz;

	luaL_checktype(L, 1, LUA_TUSERDATA);
	ctx = luaL_checkudata(L, 1, TYPE_SHA1);
	luaL_checktype(L, 2, LUA_TSTRING);
	/* guard luaL_checklstring against number */
	data = luaL_checklstring(L, 2, &sz);
	if (sz > UINT_MAX)
		return luaL_error(L, "sha1_update: data exceeds UINT_MAX");
	SHA1Update(ctx, (unsigned char *)data, sz);
	return 0;
}

int
lsha1_final(lua_State *L)
{
	SHA1_CTX *ctx;
	unsigned char digest[20];
	const char *hexdigits = "0123456789abcdef";
	char strdigest[40+1];
	int i, j;

	luaL_checktype(L, 1, LUA_TUSERDATA);
	ctx = luaL_checkudata(L, 1, TYPE_SHA1);

	SHA1Final(digest, ctx);

	for (i = 0, j = 0; i < 20; i++) {
		strdigest[j++] = hexdigits[(digest[i] & 0xf0) >> 4];
		strdigest[j++] = hexdigits[digest[i] & 0x0f];
	}
	strdigest[j] = '\0';

	lua_pushstring(L, strdigest);
	return 1;
}

int
lsha256_init(lua_State *L)
{
	SHA256_CTX *ctx = lua_newuserdata(L, sizeof(SHA256_CTX));
	luaL_newmetatable(L, TYPE_SHA256);
	lua_setmetatable(L, 1);

	SHA256_Init(ctx);
	return 1;
}

int
lsha256_update(lua_State *L)
{
	SHA256_CTX *ctx;
	const char* data;
	size_t sz;

	luaL_checktype(L, 1, LUA_TUSERDATA);
	ctx = luaL_checkudata(L, 1, TYPE_SHA256);
	luaL_checktype(L, 2, LUA_TSTRING);
	/* guard luaL_checklstring against number */
	data = luaL_checklstring(L, 2, &sz);
	SHA256_Update(ctx, (const u_int8_t *)data, sz);
	return 0;
}

int
lsha256_final(lua_State *L)
{
	SHA256_CTX *ctx;
	char digest[SHA256_DIGEST_STRING_LENGTH];

	luaL_checktype(L, 1, LUA_TUSERDATA);
	ctx = luaL_checkudata(L, 1, TYPE_SHA256);

	SHA256_End(ctx, digest);
	lua_pushstring(L, digest);
	return 1;
}

static luaL_reg lib[] = {
	{ "sha1_init",		lsha1_init },
	{ "sha1_update",	lsha1_update },
	{ "sha1_final",		lsha1_final },
	{ "sha256_init",	lsha256_init },
	{ "sha256_update",	lsha256_update },
	{ "sha256_final",	lsha256_final },
	{ NULL,		NULL }
};

int
luaopen_lsha(lua_State *L)
{
	luaL_Reg *next;

	lua_newtable(L);
	for (next = lib; next->name != NULL; next++) {
		lua_pushcfunction(L, next->func);
		lua_setfield(L, -2, next->name);
	}

	return 1;
}
