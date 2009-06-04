#!/bin/bash

#E=echo
E=""
cat <<EOF
Release Checklist:

 * is the release string set correctly? (make.vars)
 * is the Changelog entry up-to-date (NEXT:) ?
 * is the configuration syntax list up-to-date? (make vars: SYNTAX)

EOF

vi make.vars
TAG=$(make showtag)
sed -i -r -e s,"^NEXT:.*","$TAG", Changelog
vi Changelog
echo "Release name will be: $TAG"
echo "Changes in the final commit:"
$E git diff HEAD Changelog make.vars
echo ""
read -p "Release? Type yes to proceed> " OK
if [ "$OK" != "yes" ] ; then
	exit 1
fi
$E git commit -s -m "release $TAG" Changelog make.vars
$E git tag "$TAG"
cat - Changelog >Changelog.new <<EOF
NEXT:

EOF
mv Changelog.new Changelog
$E git commit -s -m "create next changelog entry" Changelog

$E git archive --format=tar --prefix=$TAG/ refs/tags/$TAG |gzip >$TAG.tar.gz
