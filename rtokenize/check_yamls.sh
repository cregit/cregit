#!/bin/sh
for f in `find ../kubernetes_original/ -type f -iname "*.y*ml"`
do
	ls -l "$f"
	# res=`./rtokenize.rb --split 50 --part-size 1 --yaml < "$f" > out`
	res=`./rtokenize.rb --yaml < "$f" > out`
	rc=$?
	if [ $rc -ne 0 ]
	then
		echo "Tokenize $f => $rc"
		#read c
	fi
	res=`./rlocalize.rb yaml out "$f" 0`
	rc=$?
	if [ $rc -ne 0 ]
	then
		echo "Localize $f => $rc"
	fi
done
rm -f ./out
