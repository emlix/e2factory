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
#include <libgen.h>

/* #define DEBUG 1 */

#ifndef CHROOT_TOOL
#error CHROOT_TOOL is not set
#endif

#ifndef TAR_TOOL
#error TAR_TOOL is not defined
#endif

#ifndef CHOWN_TOOL
#error CHOWN_TOOL is not defined
#endif

#ifndef RM_TOOL
#error RM_TOOL is not defined
#endif

char *chroot_tool = CHROOT_TOOL;
char *tar_tool = TAR_TOOL;
char *chown_tool = CHOWN_TOOL;
char *rm_tool = RM_TOOL;

void setuid_root()
{
	int rc;
	rc = clearenv();
	if(rc != 0) {
		perror("can't clearenv()");
		exit(99);
	}
	rc = setuid(0);
	if(rc != 0) {
		perror("can't setuid(0)");
		exit(99);
	}
	rc = setgid(0);
	if(rc != 0) {
		perror("can't setgid(0)");
		exit(99);
	}
	rc = setgroups(0, NULL);
	if(rc != 0) {
		perror("can't setgroups()");
		exit(99);
	}
}

void perr(char *msg)
{
	puts(msg);
	exit(99);
}

void print_arg(char *arg[])
{
#ifdef DEBUG
	int i;
	for(i=0; arg[i]; i++) {
		printf("%s\n", arg[i]);
	}
#endif
}

void assert_chroot_environment(char *path)
{
	char name[PATH_MAX];
	snprintf(name, sizeof(name), "%s/emlix-chroot", path);
	name[sizeof(name)-1]=0;
	if(access(name, R_OK)) {
		perr("not a chroot environment");
	}
	return;
}

int main(int argc, char *argv[])
{
	int rc;
	if(argc < 3) {
		perr("too few arguments");
	}
	if(argc > 128) {
		perr("too many arguments");
	}
	char *cmd = argv[1];
	char *path = argv[2];
	assert_chroot_environment(path);
	if(!strcmp(cmd, "chroot_2_2")) {
		/* chroot_2_2 <path> ... */
		int i;
		char *arg[256];
		if(argc < 3) {
			perr("too few arguments");
		}
		arg[0] = basename(chroot_tool);
		arg[1] = path;
		for (i=3; i < argc; i++) {
			arg[i-1] = argv[i];
		}
		arg[i-1] = 0;
		print_arg(arg);
		setuid_root();
		rc = execv(chroot_tool, arg);
		perror("can't exec");
		exit(99);
	} else if(!strcmp(cmd, "extract_tar_2_2")) {
		/* extract_tar_2_2 <path> <tartype> <file> */
		char *arg[256];
		if(argc != 5) {
			perr("wrong number of arguments");
		}
		char *tartype = argv[3];
		char *file = argv[4];
		char *tararg = NULL;
		if(!strcmp(tartype, "tar.gz")) {
			tararg = "-xzf";
		} else if(!strcmp(tartype, "tar.bz2")) {
			tararg = "-xjf";
		} else if(!strcmp(tartype, "tar")) {
			tararg = "-xf";
		} else {
			perr("wrong tararg argument");
		}
		arg[0] = basename(tar_tool);
		arg[1] = "-C";
		arg[2] = path;
		arg[3] = tararg;
		arg[4] = file;
		arg[5] = NULL;
		print_arg(arg);
		setuid_root();
		rc = execv(tar_tool, arg);
		perror("can't exec");
		exit(99);
	} else if(!strcmp(cmd, "set_permissions_2_2")) {
		/* set_permissions_2_2 <path> */
		char *arg[256];
		if(argc != 3) {
			perr("wrong number of arguments");
		}
		arg[0] = basename(chown_tool);
		arg[1] = "root:root";
		arg[2] = path;
		arg[3] = NULL;
		print_arg(arg);
		setuid_root();
		rc = execv(chown_tool, arg);
		perror("can't exec");
		exit(99);
	} else if(!strcmp(cmd, "remove_chroot_2_2")) {
		/* remove_chroot_2_2 <path> */
		char *arg[256];
		if(argc != 3) {
			perr("wrong number of arguments");
		}
		arg[0] = basename(rm_tool);
		arg[1] = "-r";
		arg[2] = "-f";
		arg[3] = path;
		arg[4] = NULL;
		print_arg(arg);
		setuid_root();
		rc = execv(rm_tool, arg);
		perror("can't exec");
		exit(99);
	}
	perr("unknown command");
	exit(99);
}
