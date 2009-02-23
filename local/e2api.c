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
   e2api.c 

   C-API for accessing project information
*/


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>

#include "e2api.h"


static char *error_message = NULL;


lua_State *
e2_init(char *project_path)
{
  char rpath[ PATH_MAX + 1 ];
  char buffer[ PATH_MAX + 1 ];
  lua_State *lua;

  if(realpath(project_path, rpath) == NULL) {
    free(error_message);
    error_message = strdup(strerror(errno));
    return NULL;
  }

  strcpy(buffer, rpath);
  strcat(buffer, "/.e2/lib/e2/?.lc;");
  strcat(buffer, rpath);
  strcat(buffer, "/.e2/lib/e2/?.lua");
  setenv("LUA_PATH", buffer, 1);
  strcpy(buffer, rpath);
  strcat(buffer, "/.e2/lib/e2/?.so");
  setenv("LUA_CPATH", buffer, 1);
  lua = lua_open();
  luaL_openlibs(lua);
  lua_newtable(lua);
  lua_setglobal(lua, "arg");
  lua_pushstring(lua, rpath);
  lua_setglobal(lua, "e2api_rpath");
  strcpy(buffer, rpath);
  strcat(buffer, "/.e2/lib/e2/e2local.lc");
  
  if(luaL_loadfile(lua, buffer) != 0) {
    free(error_message);
    error_message = strdup(lua_tostring(lua, -1));
    lua_close(lua);
    return NULL;
  }

  if(lua_pcall(lua, 0, 0, 0) != 0) {
    free(error_message);
    error_message = strdup(lua_tostring(lua, -1));
    lua_close(lua);
    return NULL;
  }

  return lua;
}


void 
e2_exit(lua_State *lua)
{
  free(error_message);
  lua_close(lua);
}
 

static int
exit_handler(lua_State *lua)
{
  free(error_message);
  error_message = strdup(lua_tostring(lua, -1));
  return luaL_error(lua, error_message);
}
 

int 
e2_info(lua_State *lua)
{
  lua_getglobal(lua, "e2lib");
  lua_pushstring(lua, "abort_with_message");
  lua_pushcfunction(lua, exit_handler);
  lua_rawset(lua, -3);
  lua_getglobal(lua, "e2tool");
  lua_pushstring(lua, "collect_project_info");
  lua_rawget(lua, -2);
  lua_remove(lua, -2);	/* remove e2tool table */
  lua_getglobal(lua, "e2api_rpath");

  if(lua_pcall(lua, 1, 1, 0) != 0) {
    free(error_message);
    error_message = strdup(lua_tostring(lua, -1));
    return 0;
  }

  return 1;
}


char *
e2_error(void)
{
  return error_message;
}
