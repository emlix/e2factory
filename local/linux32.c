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
  linux32.c
*/


//#include <linux/personality.h>
//#undef personality
#include <sys/personality.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>

/* taken from x86_64 headers */
#define PER_LINUX32    0x0008

int main(int argc, char *argv[])
{
	int persona = PER_LINUX32;
	int rc;
	/* need to change personality on x86_64 systems, but no harm on i386 */
	rc = personality(persona);
        if (rc<0) {
		fprintf(stderr, "Cannot set %x personality: %s\n", persona,
				strerror(errno));
		exit(1);
	}
	if(argc < 2) {
		exit(0);
	}
	execvp(argv[1], &argv[1]);
	fprintf(stderr, "Cannot exec: %s\n", strerror(errno));
	exit(1);
}

