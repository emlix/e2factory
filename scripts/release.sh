#!/bin/sh -e
#
# release.sh (C) 2007 by emlix GmbH
#
# syntax: 
#  release.sh <release name>
#
# this script creates a release as follows:
#
#  1. write the release name to ./VERSION
#  2. create a commit tracking the change to the VERSION file
#  3. create a tag named VERSION
#
#  The VERSION file is used by buildversion.sh to create a name
#  describing the state of the working copy as detailed as possible.
#

VERSION="$1"

if [ -z "$VERSION" ] ; then
  echo "Error: empty version"
  exit 1
fi

TAG="$VERSION"

if git tag -l "^$TAG\$" ; then
  echo "Error: tag exists: $TAG"
  exit 1
fi

cat >VERSION <<EOF
$VERSION
EOF

git add VERSION
git commit -s -m "version $TAG" VERSION
git tag "$TAG"
