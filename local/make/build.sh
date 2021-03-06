#!/bin/bash
#
# Copyright (C) 2007-2016 emlix GmbH, see file AUTHORS
#
# This file is part of e2factory, the emlix embedded build system.
# For more information see http://www.e2factory.org
#
# e2factory is a registered trademark of emlix GmbH.
#
# e2factory is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.

set -e
RESULT="$1"
source res/$RESULT/config  # set CHROOT, DEPEND, SOURCE
source proj/config
if [ "$chroot_arch" == "x86_64" ] &&
   [ $(uname -m) != "x86_64" ] ; then
	echo >&2 "need x86_64 host to build this project"
	exit 1
fi
chroot_base=/tmp/e2build.$RESULT.cp
chroot_path=$chroot_base/chroot
e2-su-2.2 remove_chroot_2_3 $chroot_base >/dev/null 2>&1 || true
mkdir -p $chroot_base/chroot
touch $chroot_base/e2factory-chroot
e2-su-2.2 set_permissions_2_3 $chroot_base
# install chroot groups
for g in $CHROOT ; do
	make chroot_base=$chroot_base -C chroot/$g place
done
# install sources
for s in $SOURCE ; do
	dst=$chroot_path/tmp/e2/build
	mkdir -p $dst
	make BUILD=$dst -C src/$s place
done
# install deps
for d in $DEPEND ; do
	dst=$chroot_path/tmp/e2/dep
	mkdir -p $dst
	cp -v -r out/$d $dst/
done
# install result stuff
mkdir -p $chroot_path/tmp/e2/{script,init,env,dep,build,out,root}
if [ ! "$(echo proj/init/*)" = 'proj/init/*' ]; then
	cp -v proj/init/* $chroot_path/tmp/e2/init
fi
cp -v res/$RESULT/{build-driver,buildrc,build-script} \
				$chroot_path/tmp/e2/script/
cp -v res/$RESULT/{builtin,env} $chroot_path/tmp/e2/env/
if [ "$chroot_arch" == "x86_32" ] ; then
	./linux32 \
	e2-su-2.2 chroot_2_3 $chroot_base \
	/bin/bash -e -x /tmp/e2/script/build-driver </dev/null
elif [ "$chroot_arch" == "x86_64" ] ; then
	e2-su-2.2 chroot_2_3 $chroot_base \
	/bin/bash -e -x /tmp/e2/script/build-driver </dev/null
fi
# fetch result
rm -fr out/$RESULT
mkdir -p out/$RESULT
cp -v $chroot_path/tmp/e2/out/* out/$RESULT/
e2-su-2.2 remove_chroot_2_3 $chroot_base
exit 0
