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
  testapi.c
*/


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "e2api.h"


int 
main(int argc, char *argv[])
{
  lua_State *lua;
  char rpath[ PATH_MAX + 1 ];

  if(argc > 1) strcpy(rpath, argv[ 1 ]);
  else strcpy(rpath, ".");

  lua = e2_init(rpath);

  if(lua == NULL) {
    fprintf(stderr, "[e2api] Error: %s\n", e2_error());
    exit(EXIT_FAILURE);
  }

  if(e2_info(lua)) {
    lua_pushnil(lua);
    
    while (lua_next(lua, -2) != 0) {
      printf("%s: %s\n", lua_tostring(lua, -2), lua_typename(lua, lua_type(lua, -1)));
      lua_pop(lua, 1);
    }

    lua_pop(lua, 1);
  }
  else {
    fprintf(stderr, "[e2api] Error: %s\n", e2_error());
    exit(EXIT_FAILURE);
  }
  
  e2_exit(lua);
  return 0;
}
