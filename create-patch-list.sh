#!/bin/bash

CMD=${0##*/}
SOURCE_DIR=$(cd $(dirname $0) && pwd)
REPO_NAME=systemd
REPO_DIR=${HOME}/git/${REPO_NAME}
BRANCHES=$(awk '$1 !~ "^#" { print $1 }' ${SOURCE_DIR}/branch-list.txt)

rm -f ${SOURCE_DIR}/2???-*.patch ${SOURCE_DIR}/patch-list.txt

if [[ -z $BRANCHES ]]; then
    touch ${SOURCE_DIR}/patch-list.txt
    exit 0
fi

if [[ -z $1 || $1 != '--fetch=no' ]]; then
    if ! git -C $REPO_DIR fetch upstream --prune; then
        echo 'error: `git fetch upstream --prune` failed.' >&2
        exit 101
    fi

    if ! git -C $REPO_DIR fetch origin --prune; then
        echo "error: `git fetch origin --prune` failed." >&2
        exit 102
    fi
fi

start=2001
for branch in $BRANCHES; do
    PATCH_LIST=$(git -C $REPO_DIR format-patch -o ${SOURCE_DIR} --no-numbered --no-signature --start-number ${start} $(git -C $REPO_DIR show-branch --merge-base refs/remotes/upstream/main ${branch})..${branch})
    for patch in $PATCH_LIST; do
        printf "Patch%04d: ${patch##*/}\n" ${start}
        let start++
    done
done > ${SOURCE_DIR}/patch-list.txt
