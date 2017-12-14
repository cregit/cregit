#!/bin/sh
DEV_PATH=/home/justa/dev
# Example MASK can be: '\.([ch]|go|md|sh|yml|yaml|json)$'
if [ -z "$1" ] || [ -z "$2" ]
then
	echo "Need 2 arguments: 'repo_name' 'file_mask'"
	exit 1
fi
REPO=$1
MASK=$2
echo "Running on repo $1 with file mask $2"

# Clean up
echo 'Cleaning up...'
rm -rf /tmp/tmp.* ${DEV_PATH}/$REPO ${DEV_PATH}/${REPO}_token ${DEV_PATH}/${REPO}_blame ${DEV_PATH}/cregit_${REPO}_html ${DEV_PATH}/${REPO}_memo ${DEV_PATH}/${REPO}_token.bfg-report ${REPO}-*.db ${REPO}-*.xls
cd ..
# git clone https://github.com/lukaszgryglicki/testing_robot.git
# mv testing_robot ${REPO}_original
cp -R ${REPO}_original ${REPO}_token

# BFG part (longest)
cd cregit
mkdir ${DEV_PATH}/${REPO}_memo 2>/dev/null
BFG_MEMO_DIR=${DEV_PATH}/${REPO}_memo; export BFG_MEMO_DIR
BFG_TOKENIZE_CMD="${DEV_PATH}/cregit/tokenize/tokenizeSrcMl.pl --rtokenizer=${DEV_PATH}/rtokenize/rtokenize.sh --go2token=${DEV_PATH}/cregit/tokenize/goTokenizer/gotoken --simpleTokenizer=${DEV_PATH}/cregit/tokenize/text/simpleTokenizer.pl --srcml2token=srcml2token --srcml=srcml --ctags=ctags-exuberant"; export BFG_TOKENIZE_CMD
SBT_OPTS='-Xms100g -Xmx100g -XX:ReservedCodeCacheSize=2048m -XX:MaxMetaspaceSize=25g'; export SBT_OPTS
cd ../bfg-repo-cleaner/
rm perllog.txt rtokenize.log tmpfile* 2>/dev/null
echo 'Uncomment next two lines to have BFG compiled in every run'
# sbt clean
# sbt bfg/assembly
FILE=`find . -iname "*.jar"`
echo 'Running SBT...'
java $SBT_OPTS -jar $FILE "--blob-exec:${DEV_PATH}/cregit/tokenizeByBlobId/tokenBySha.pl=$MASK" --no-blob-protection ${DEV_PATH}/${REPO}_token

# Rewrite history
echo 'Rewritting history...'
cd ${DEV_PATH}/${REPO}_token
git reset --hard
git reflog expire --expire=now --all && git gc --prune=now --aggressive
cd ${DEV_PATH}/cregit

# cat ../bfg-repo-cleaner/perllog.txt
# exit 1

# Slick Git Log
echo 'SLick Git Log...'
cd slickGitLog
sbt "run ../${REPO}-token.db ${DEV_PATH}/${REPO}_token/"
sbt "run ../${REPO}-original.db ${DEV_PATH}/${REPO}_original/"
cd ..

# Remap commits
echo 'Remap commits...'
cd remapCommits
sbt "run ../${REPO}-token.db ${DEV_PATH}/${REPO}_token"
cd ..

# Persons DB
echo 'Persons DB...'
cd persons
sbt "run ${DEV_PATH}/${REPO}_token ../${REPO}-persons.xls ../${REPO}-persons.db"
cd ..

# Blame
echo 'Blame...'
cd blameRepo
mkdir ${DEV_PATH}/${REPO}_blame 2>/dev/null
perl blameRepoFilesMT.pl --verbose --formatBlame=./formatBlame.pl ${DEV_PATH}/${REPO}_token ${DEV_PATH}/${REPO}_blame "$MASK"
cd ..

# HTML generation
echo 'HTML...'
cd prettyPrint
mkdir ${DEV_PATH}/cregit_${REPO}_html 2>/dev/null
perl ./prettyPrintFilesMT.pl --verbose ../${REPO}-token.db ../${REPO}-persons.db ${DEV_PATH}/${REPO}_original ${DEV_PATH}/${REPO}_blame ${DEV_PATH}/cregit_${REPO}_html https://github.com/lukaszgryglicki/testing_robot/commit/ "$MASK"
cd ..

echo 'Final permissions...'
# Apache permissions
rm -rf prettyPrint/tmpfile*
find ${DEV_PATH}/cregit_${REPO}_html/ -type f -iname "*.html" -exec chmod ugo+r "{}" \;
find ${DEV_PATH}/${REPO}_token/ -type f -iname "*.html" -exec chmod ugo+r "{}" \;

echo 'All done.'
