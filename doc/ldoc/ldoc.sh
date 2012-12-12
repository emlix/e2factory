#!/bin/sh -e

if [ -z "$LDOC_BASE" ]; then
	LDOC_BASE="@LDOC_BASE@"
fi

LUA_BIN="$LDOC_BASE/lua-5.1.3/src/lua"
LDOC_DIR="$LDOC_BASE/LDoc-1.2.0"
PL_DIR="$LDOC_BASE/Penlight-1.0.2"
LFS_DIR="$LDOC_BASE/luafilesystem-1.6.2"

env LUA_PATH="$PL_DIR/lua/?.lua;$PL_DIR/lua/?/init.lua" \
	LUA_CPATH="$LFS_DIR/src/lfs.so" "$LUA_BIN" "$LDOC_DIR/ldoc.lua" $@
