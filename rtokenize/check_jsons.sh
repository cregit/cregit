#!/bin/sh
for f in `find ../kubernetes_original/ -type f -iname "*.json"`
do
	ls -l "$f"
	#res=`./rtokenize.rb --split 50 --part-size 1 --json < $f > out`
	res=`./rtokenize.rb --json < $f > out`
	rc=$?
	if [ $rc -ne 0 ]
	then
		echo "Tokenize $f ==> $rc"
	fi
	res=`./rlocalize.rb json out "$f" 0`
	rc=$?
	if [ $rc -ne 0 ]
	then
		echo "Localize $f => $rc"
	fi
done
rm -f ./out
