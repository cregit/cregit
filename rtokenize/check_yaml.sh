#!/bin/sh
# ./rtokenize.rb --split 50 --part-size 1 --yaml < "$1" > out.yaml.token && ./rlocalize.rb yaml out.yaml.token "$1" 0
./rtokenize.rb --yaml < "$1" > out.yaml.token && ./rlocalize.rb yaml out.yaml.token "$1" 0
