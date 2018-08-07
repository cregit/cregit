#!/bin/bash

BUILD_LOCAL=yes
OUTPUT_DIR="Output"
GIT_URL="http://github.com/git/git"

ORIGINAL_REPO="../../original.repo/git"
BLAME_DIRECTORY="../../2.17/blame"
TOKEN_DIRECTORY="../../token"
PERSONS_DB="../../2.17/token.db"
TOKEN_DB="../../2.17/persons.db"
FLAGS="--filter-lang=c --git-url=${GIT_URL}"

if [ "$BUILD_LOCAL" = "yes" ]; then
	FLAGS+=" --webroot-relative"
fi

set -x
perl prettyPrint.pl ${FLAGS} "${ORIGINAL_REPO}" "${BLAME_DIRECTORY}" "${TOKEN_DIRECTORY}" "${PERSONS_DB}" "${TOKEN_DB}" "${OUTPUT_DIR}"
cp -r templates/public/. ${OUTPUT_DIR}/public

