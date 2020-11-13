#!/bin/bash

CMD=${0##*/}
SOURCE_DIR=$(cd $(dirname $0) && pwd)
REPO_NAME=systemd
REPO_DIR=${HOME}/git/${REPO_NAME}
BRANCHES=$(awk '$1 !~ "^#" { print $1 }' ${SOURCE_DIR}/branch-list.txt)

HASH_OLD=$(grep -e '^[%#]global commit' ${SOURCE_DIR}/${REPO_NAME}.spec | awk '{ print $3 }')
if [[ -z $HASH_OLD ]]; then
    echo 'error: cannot obtain old commit hash.' >&2
    exit 1
fi

if ! git -C $REPO_DIR fetch upstream --prune; then
    echo 'error: `git fetch upstream --prune` failed.' >&2
    exit 11
fi

if ! HASH_NEW=$(git -C $REPO_DIR show-ref --hash refs/remotes/upstream/main); then
    echo 'error: `git show-ref` failed.' >&2
    exit 12
fi

if [[ "$HASH_NEW" == "$HASH_OLD" && -z $BRANCHES ]]; then
    echo 'info: not necessary to update spec file.' >&2
    exit
fi

HASH_OLD_SHORT=${HASH_OLD:0:7}
HASH_NEW_SHORT=${HASH_NEW:0:7}

VERSION=$(grep -e '^Version:' ${SOURCE_DIR}/${REPO_NAME}.spec | awk '{ print $2 }')

RELEASE_OLD=$(grep -e '^Release:' ${SOURCE_DIR}/${REPO_NAME}.spec | sed -e 's/^Release:[[:space:]]*//; s/%.*$//;')
RELEASE_MAIN=$(echo $RELEASE_OLD | sed -e 's/\.[[:digit:]]*//')
RELEASE_SUB_OLD=$(echo $RELEASE_OLD | sed -e 's/[[:digit:]]*\.*//')
if [[ -z $RELEASE_SUB_OLD ]]; then
    RELEASE_SUB_OLD=0
fi
RELEASE_SUB_NEW=$(( $RELEASE_SUB_OLD + 1 ))
RELEASE_NEW=${RELEASE_MAIN}.${RELEASE_SUB_NEW}

WEEKDAY=$(date -u "+%a")
MONTH=$(date -u "+%b")
DAY=$(date -u "+%d")
YEAR=$(date -u "+%Y")

if [[ "$HASH_NEW" != "$HASH_OLD" ]]; then
    CHANGE_LOG="- Update to latest git snapshot ${HASH_NEW}\n"
    COMMIT_LOG="Update to latest git snapshot ${HASH_NEW}\n\n"
else
    COMMIT_LOG="Merge several branches\n\n"
fi
for branch in $BRANCHES; do
    CHANGE_LOG="${CHANGE_LOG}- Merge ${branch}\n"
    COMMIT_LOG="${COMMIT_LOG}- Merge ${branch}\n"
done

sed -e '/^[%#]global commit/ { s/^#/%/; s/'${HASH_OLD}'/'${HASH_NEW}'/ }' \
    -e '/^Release:/ s/'${RELEASE_OLD}'/'${RELEASE_NEW}'/' \
    -e "/^%changelog/ a\
* ${WEEKDAY} ${MONTH} ${DAY} ${YEAR} Yu Watanabe <watanabe.yu@gmail.com> - ${VERSION}-${RELEASE_NEW}.git${HASH_NEW_SHORT}\\
${CHANGE_LOG}" \
    -i ${SOURCE_DIR}/${REPO_NAME}.spec

if ! git -C $REPO_DIR fetch origin --prune; then
    echo 'error: `git fetch origin --prune` failed.' >&2
    exit 13
fi

if ! $SOURCE_DIR/create-patch-list.sh --fetch=no; then
    exit $?
fi

git -C $SOURCE_DIR add -A

if ! $SOURCE_DIR/check-patch-list.sh --fetch=no; then
    exit $?
fi

git -C $SOURCE_DIR commit -a -m "$(echo -e ${COMMIT_LOG})"
