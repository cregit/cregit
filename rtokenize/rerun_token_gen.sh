#!/bin/sh
for f in *.yaml; do ./rtokenize.sh y < "$f" > "$f.token"; done
for f in *.json; do ./rtokenize.sh j < "$f" > "$f.token"; done
