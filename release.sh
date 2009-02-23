#E=echo
E=""
cat <<EOF
Release Checklist:

 * is the configuration syntax list up-to-date? (see syntax, local/e2tool.lua)

EOF
read -p "type yes to proceed> " OK
if [ "$OK" != "yes" ] ; then
	exit 1
fi
echo "Example: 2.2pre7"
read -p "VERSION:" VERSION
RELEASE_NAME="e2factory-$VERSION"
echo $VERSION >./version
vi Changelog # edit the release string
echo ==================
echo Changelog:
head Changelog
echo Version: $VERSION
echo Release Name: $RELEASE_NAME
echo ==================
read -p "commit, tag, push?"
$E git commit -m "release $RELEASE_NAME" version Changelog
$E git tag "$RELEASE_NAME"
$E git push origin "$RELEASE_NAME"

VERSION=${VERSION}-wip
RELEASE_NAME="e2factory-$VERSION"
echo $VERSION >./version
mv Changelog Changelog.tmp
cat - Changelog.tmp > Changelog <<EOF
$RELEASE_NAME

EOF
vi Changelog # edit the release string: wip again
echo ==================
echo Changelog:
head Changelog
echo Version: $VERSION
echo Release Name: $RELEASE_NAME
echo ==================
read -p "commit, push?"
$E git commit -m "work in progress $RELEASE_NAME" version Changelog
$E git push

