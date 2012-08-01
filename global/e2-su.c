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
#include <pwd.h>
#include <limits.h>
#include <grp.h>

#ifndef TOOLDIR
#error TOOLDIR not defined
#endif
#ifndef E2_ROOT_TOOL_NAME
#define E2_ROOT_TOOL_NAME	"e2-root"
#endif
#ifndef E2_ROOT_TOOL_PATH
#define E2_ROOT_TOOL_PATH	TOOLDIR "/" E2_ROOT_TOOL_NAME
#endif

char *tool_name = E2_ROOT_TOOL_NAME;
char *tool_path = E2_ROOT_TOOL_PATH;

int main(int argc, char *argv[])
{
	int rc;
	int i;
	char *arg [ 1024 ];

	if(argc < 2) {
	  fprintf(stderr, "this tool is not intended to be executed directly\n");
	  exit(1);
	}

	int k = 0;
	arg[k++] = tool_name;
	for(i=1; argv[i]; i++) {
		if(argv[i][0] == '-')
			continue;
		arg[k++] = argv[i];
		//fprintf(stderr, "%s\n");
	}
	arg[k] = NULL;

	if(getenv("DEBUG")) {
		printf("%s\n", E2_ROOT_TOOL_PATH);
		for(i=0; arg[i]; i++) {
			printf("\"%s\"\n", arg[i]);
		}
	}

	rc = setuid(0);
	if(rc != 0) {
		perror("can't setuid(0)");
		exit(1);
	}

	rc = setgid(0);
	if(rc != 0) {
		perror("can't setgid(0)");
		exit(1);
	}

	rc = setgroups(0, NULL);
	if(rc != 0) {
		perror("can't setgroups()");
		exit(1);
	}

	rc = execvp(E2_ROOT_TOOL_PATH, arg);
	perror("can't exec");
	exit(3);
}
