#!/bin/sh
# ./rtokenize.rb --split 50 --part-size 1 --json < "$1" > out.json.token && ./rlocalize.rb json out.json.token "$1" 0
./rtokenize.rb --json < "$1" > out.json.token && ./rlocalize.rb json out.json.token "$1" 0
