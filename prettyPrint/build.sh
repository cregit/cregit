#!/bin/bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

LOCAL_PREVIEW=yes
OUTPUT_DIR="Output"
HOST_URL="http://o.cs.uvic.ca:20810/~limja"
GIT_URL="http://github.com/git/git"

ORIGINAL_REPO="../../original.repo/git"
BLAME_DIRECTORY="../../2.17/blame"
TOKEN_DIRECTORY="../../token"
PERSONS_DB="../../2.17/token.db"
TOKEN_DB="../../2.17/persons.db"
FLAGS="--filter-lang=c --git-url=${GIT_URL}"

if [ "$LOCAL_PREVIEW" = "yes" ]; then
	FLAGS+=" --webroot-relative"
else
	FLAGS+=" --webroot=${HOST_URL}"
fi

set -x
perl prettyPrint.pl ${FLAGS} "${ORIGINAL_REPO}" "${BLAME_DIRECTORY}" "${TOKEN_DIRECTORY}" "${PERSONS_DB}" "${TOKEN_DB}" "${OUTPUT_DIR}"
cp -r templates/public/. ${OUTPUT_DIR}/public

