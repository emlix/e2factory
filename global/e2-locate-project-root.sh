#!/bin/sh
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

export LC_ALL=C
while [ '!' -f .e2/e2version ] ; do
	if [ "$PWD" = "/" ] ; then
		echo >&2 \
		    "e2-locate-project-root: Not in a project environment."
		exit 1
	fi
	cd ..
done
echo $PWD
