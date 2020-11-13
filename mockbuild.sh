#!/bin/bash

set -ex
set -o pipefail

source /etc/os-release

ARCH=x86_64
BRANCH=custom
DISTRO=$ID
PACKAGE=systemd
RELEASE=$VERSION_ID

while getopts a:b:d:p:r: OPT
do
    case $OPT in
        a ) ARCH=$OPTARG;;
        b ) BRANCH=$OPTARG;;
        d ) DISTRO=$OPTARG;;
        p ) PACKAGE=$OPTARG;;
        r ) RELEASE=$OPTARG;;
        * ) exit 255;;
    esac
done
shift $(($OPTIND - 1))

if [[ -z $PACKAGE ]]; then
    PACKAGE=$1
fi
if [[ -z $PACKAGE ]]; then
    echo 'error: no package name is specified.' >&2
    exit 2
fi

if [[ -z $BRANCH ]]; then
    echo 'error: no branch name is specified.' >&2
    exit 3
fi

if [[ -z $RELEASE ]]; then
    echo 'error: OS version ID is not specified.' >&2
    exit 4
fi

DEST_DIR=$HOME/rpms
SOURCE_DIR=$HOME/git/${PACKAGE}-${DISTRO}

if [[ -f $HOME/.mock/${DISTRO}-${RELEASE}-${ARCH}.cfg ]]; then
    MOCK="mock --dnf -r $HOME/.mock/${DISTRO}-${RELEASE}-${ARCH}.cfg --uniqueext=${PACKAGE}-${SLURM_JOB_ID} --no-bootstrap-chroot"
    echo "info: using mock config $HOME/.mock/${DISTRO}-${RELEASE}-${ARCH}.cfg"
elif [[ -f /etc/mock/${DISTRO}-${RELEASE}-${ARCH}.cfg ]]; then
    MOCK="mock --dnf -r ${DISTRO}-${RELEASE}-${ARCH} --uniqueext=${PACKAGE}-${SLURM_JOB_ID} --no-bootstrap-chroot"
    echo "info: using mock config /etc/mock/${DISTRO}-${RELEASE}-${ARCH}.cfg"
else
    echo "error: mock config ${DISTRO}-${RELEASE}-${ARCH} not found." >&2
    exit 5
fi

function finalize()
{
    local exit_code=$1
    if [[ -z $exit_code ]]; then
        exit_code=$?
    fi

    rm -rf $TMP_DIR
    date
    exit $exit_code
}

date
hostname

TMP_DIR=$(mktemp -q -d /tmp/mockbuild.${PACKAGE}.${SLURM_JOB_ID}.XXXXX)
mkdir -p $TMP_DIR/result $TMP_DIR/srpm
if ! git clone $SOURCE_DIR $TMP_DIR/${PACKAGE}; then
    echo "error: 'git clone $SOURCE_DIR $TMP_DIR/${PACKAGE}' failed." >&2
    finalize 10
fi

if ! git -C $TMP_DIR/${PACKAGE} checkout $BRANCH; then
    echo "error: 'git checkout $BRANCH' failed." >&2
    finalize 11
fi

if ! spectool -d "_sourcedir $TMP_DIR/${PACKAGE}" -g -C $TMP_DIR/${PACKAGE} $TMP_DIR/${PACKAGE}/${PACKAGE}.spec; then
    echo "error: spectool failed." >&2
    finalize 12
fi

echo "### Build SRPM ############################"
$MOCK --resultdir=$TMP_DIR/srpm --buildsrpm --spec $TMP_DIR/${PACKAGE}/${PACKAGE}.spec --sources $TMP_DIR/${PACKAGE}
RETVAL=$?

SRPM=$(ls $TMP_DIR/srpm/${PACKAGE}-*.src.rpm 2>/dev/null)
if [[ -z $SRPM ]]; then
    echo "error: srpm cannot be found." >&2
    RETVAL=12
fi
BUILD=${SRPM##*/}
BUILD=${BUILD%.src.rpm}

echo "### Backup logs ###########################"
SRPM_LOG_DEST=$HOME/.mock/log/$BUILD/srpm
if (( $RETVAL )); then
    SRPM_LOG_DEST=$HOME/.mock/log/${PACKAGE}-srpm-${DISTRO}-${RELEASE}
fi
LOGS=$(ls $TMP_DIR/srpm/*.log 2>/dev/null)
if [[ -n $LOGS ]]; then
    mkdir -p $SRPM_LOG_DEST
    rsync -v $LOGS $SRPM_LOG_DEST
fi
if (( $RETVAL )); then
    finalize $RETVAL
fi

echo "### Push SRPM to repository ###############"
mkdir -p $DEST_DIR/$RELEASE/SRPMS
rsync -v $SRPM $DEST_DIR/$RELEASE/SRPMS/.

echo "### Build RPMs ############################"
$MOCK --resultdir=$TMP_DIR/result --rebuild $SRPM
RETVAL=$?

echo "### Backup logs ###########################"
LOGS=$(ls $TMP_DIR/result/*.log 2>/dev/null)
if [[ -n $LOGS ]]; then
    mkdir -p $HOME/.mock/log/$BUILD/result
    rsync -v $LOGS $HOME/.mock/log/$BUILD/result/.
fi

if (( $RETVAL )); then
    finalize $RETVAL
fi

echo "### Push RPMs to repository ###############"
mkdir -p $DEST_DIR/$RELEASE/$ARCH/$BUILD
rsync -v --exclude ${SRPM##*/} $TMP_DIR/result/*.rpm $DEST_DIR/$RELEASE/$ARCH/$BUILD/.

finalize $RETVAL
