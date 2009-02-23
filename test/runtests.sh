#!/bin/bash
export PATH=$PWD/e2/bin:/bin:/usr/bin:/sbin:/usr/sbin
declare -i pass
declare -i fail
pass=0
fail=0
if [ -z "$TESTS" ] ; then
	TESTS=$(cd tests; ls *.test)
fi
rm -fr log
mkdir log
LOG=$PWD/log/test.log
export E2_CONFIG=$PWD/e2.conf
export E2_LOCAL_BRANCH="$(git branch | grep '^*' | sed s/'^* '/''/)"
echo "Testing: $(date)" >$LOG
for i in $TESTS ; do
	rm -fr ./tmp
	mkdir ./tmp
	cd ./tmp
	bash -e -x ../tests/$i >../log/$i.log 2>&1
	r=$?
	if [ "$r" == "0" ] ; then
		pass=$pass+1
		printf "%-40s %s\n" "$i" "OK" | tee -a $LOG
	else
		fail=$fail+1
		printf "%-40s %s\n" "$i" "FAIL" | tee -a $LOG
	fi
	cd ..
done
printf "Pass: %d\n" $pass | tee -a $LOG
printf "Fail: %d\n" $fail | tee -a $LOG
