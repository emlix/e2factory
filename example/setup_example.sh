#!/bin/bash
set -e

E=e2factory-example
rm -fr $E

e2-create-project $E
e2-fetch-project $E

# merge the example project into the new project
tar -C example -cf - . | tar -C $E -xf -

pushd $E
git add .
git commit -m 'configure example project'
git push
e2-new-source --git helloworld

pushd in/helloworld
cat >hello.sh <<EOF
#!/bin/bash
echo "Hello World!"
EOF
git add hello.sh
git commit -m 'hello world script'
git push origin master
git tag helloworld-0.1
git push --tags
popd
popd

rm -fr $E
