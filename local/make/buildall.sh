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
mkdir -p log
source proj/config
if [ "$chroot_arch" == "x86_64" ] &&
   [ $(uname -m) != "x86_64" ] ; then
	echo >&2 "Error: Need x86_64 host to build this project"
	exit 1
fi
for result in $(cat resultlist) ; do
	echo >&2 "logging to log/$result.log"
	bash -x ./build.sh $result >log/$result.log 2>&1
done
