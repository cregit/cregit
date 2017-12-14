#!/bin/sh
input=`mktemp`
output=`mktemp`
# echo "start: $input $output" > rtokenize.log
# start: to remove
# cat
# rm -f $input $output 2>/dev/null
# echo "end: $input $output" >> rtokenize.log
# exit 0
# end: to remove
cat > $input
/home/justa/dev/rtokenize/rtokenize.rb -$1 < $input > $output
rc=$?
if [ $rc -ne 0 ]
then
	cat $input
	rm -f $input $output 2>/dev/null
	# echo "err1: $input $output" >> rtokenize.log
	exit 0
fi
/home/justa/dev/rtokenize/rlocalize.rb $1 $output $input
rc=$?
if [ $rc -ne 0 ]
then
	cat $input
	rm -f $input $output 2>/dev/null
	# echo "err2: $input $output" >> rtokenize.log
	exit 0
fi
cat $output
rm -f $input $output 2>/dev/null
# echo "end: $input $output" >> rtokenize.log
exit 0
