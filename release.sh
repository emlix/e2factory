#!/bin/bash -e

if [ "$EDITOR" = "" ]; then
	EDITOR="vi"
fi

cat <<EOF
Release Checklist:

 * is the release string set correctly? (make.vars)
 * is the Changelog entry up-to-date (NEXT:) ?
 * is the configuration syntax list up-to-date? (make vars: SYNTAX)

EOF

$EDITOR make.vars
TAG=$(make showtag)
sed -i -r -e s,"^NEXT:.*","$TAG", Changelog
$EDITOR Changelog
echo "Release name will be: $TAG"
echo "Changes in the final commit:"
git diff HEAD Changelog make.vars
echo ""
read -p "Release? Type yes to proceed> " OK
if [ "$OK" != "yes" ] ; then
	exit 1
fi
git commit -s -m "release $TAG" Changelog make.vars
git tag "$TAG"
cat - Changelog >Changelog.new <<EOF
NEXT:

EOF
mv Changelog.new Changelog
git commit -s -m "create next changelog entry" Changelog

git archive --format=tar --prefix=$TAG/ refs/tags/$TAG |gzip >$TAG.tar.gz
sha1sum $TAG.tar.gz >$TAG.tar.gz.sha1


if [ -z "$TAG" ]; then
	echo "TAG not set"
	exit 1
fi
rm -rf "$TAG.git"
git init --bare "$TAG.git"
pushd "$TAG.git"
git fetch .. tag "$TAG"
 cp FETCH_HEAD HEAD # same effect as git reset --hard FETCH_HEAD
git gc --aggressive --prune=now
popd

tar czf "$TAG.git.tar.gz" "$TAG.git"
rm -rf "$TAG.git"
sha1sum "$TAG.git.tar.gz" > "$TAG.git.tar.gz.sha1"
