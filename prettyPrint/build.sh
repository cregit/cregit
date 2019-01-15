#!/bin/bash

LOCAL_PREVIEW=no
OUTPUT_DIR="/home/zkchen/temp"
HOST_URL="http://o.cs.uvic.ca:20810/~zkchen"
GIT_URL="http://github.com/git/git"

HOME_REPO="/home/zkchen/cregit-data/git"
ORIGINAL_REPO="${HOME_REPO}/original.repo-v2.17/git"
BLAME_DIRECTORY="${HOME_REPO}/v2.17/blame"
TOKEN_DIRECTORY="${HOME_REPO}/v2.17/token.line"
PERSONS_DB="${HOME_REPO}/v2.17/persons.db"
TOKEN_DB="${HOME_REPO}/v2.17/token.db"
FLAGS="--filter-lang=c --git-url=${GIT_URL} --verbose" # enable debug mode

if [ "$LOCAL_PREVIEW" = "yes" ]; then
	FLAGS+=" --webroot-relative"
else
	FLAGS+=" --webroot=${HOST_URL}"
fi

set -x
perl prettyPrint.pl ${FLAGS} "${ORIGINAL_REPO}" "${BLAME_DIRECTORY}" "${TOKEN_DIRECTORY}" "${TOKEN_DB}" "${PERSONS_DB}" "${OUTPUT_DIR}"
#cp -r templates/public/. ${OUTPUT_DIR}/public

