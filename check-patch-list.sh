#!/bin/bash

CMD=${0##*/}
SOURCE_DIR=$(cd $(dirname $0) && pwd)
REPO_NAME=systemd
REPO_DIR=${HOME}/git/${REPO_NAME}
PATCHES=$(awk '$1 !~ "^#" { print $2 }' ${SOURCE_DIR}/patch-list.txt)

if [[ -z $PATCHES ]]; then
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

TEST_BRANCH=test-patches-$(date '+%Y%m%d%H%M')
if ! git -C $REPO_DIR checkout main; then
    echo 'error: cannot checkout main'
    exit 201
fi

if ! git -C $REPO_DIR pull upstream main; then
    echo 'error: cannot pull upstream main' >&2
    exit 202
fi

if ! git -C $REPO_DIR checkout -b $TEST_BRANCH; then
    echo "error: cannot checkout $TEST_BRANCH branch" >&2
    exit 203
fi

for patch in $PATCHES; do
    if ! git -C $REPO_DIR am ${SOURCE_DIR}/$patch; then
        echo "error: cannot apply $patch" >&2
        git -C $REPO_DIR am --abort
        git -C $REPO_DIR checkout main && git -C $REPO_DIR branch -D $TEST_BRANCH
        exit 204
    fi
done

git -C $REPO_DIR checkout main && git -C $REPO_DIR branch -D $TEST_BRANCH
