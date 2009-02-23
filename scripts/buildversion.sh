#!/bin/sh -e
#
# buildversion.sh (C) 2007 by emlix GmbH
#
# syntax:
#  buildversion.sh
#
# if .git is available use git describe to get a version identifier. 
# otherwise use the first line of ./VERSION as the version identifier.
#
# print the version identifier to stdout

if [ -d ./.git ] ; then
        VERSION=$(git describe --tags)
elif [ -f ./version ] ; then
	VERSION=$(head -n1 version)
else
        echo >&2 "can't find version identifier"
        exit 1
fi
echo "$VERSION"
exit 0
