#!/bin/bash

set -eux
set -o pipefail

# Switch SELinux to permissive if possible, since the tests don't set proper contexts
setenforce 0 || true

echo "CPU and Memory information:"
lscpu
lsmem

echo "Clock source: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"

# Bump inotify limits if we can so nspawn containers don't run out of inotify file descriptors.
sysctl fs.inotify.max_user_watches=65536 || true
sysctl fs.inotify.max_user_instances=1024 || true

if [[ -n "${KOJI_TASK_ID:-}" ]]; then
    koji download-task --noprogress --arch="noarch,$(rpm --eval '%{_arch}')" "$KOJI_TASK_ID"
elif [[ -n "${CBS_TASK_ID:-}" ]]; then
    cbs download-task --noprogress --arch="noarch,$(rpm --eval '%{_arch}')" "$CBS_TASK_ID"
elif [[ -n "${PACKIT_SRPM_URL:-}" ]]; then
    COPR_BUILD_ID="$(basename "$(dirname "$PACKIT_SRPM_URL")")"
    COPR_CHROOT="$(basename "$(dirname "$(dirname "$PACKIT_BUILD_LOG_URL")")")"
    copr download-build --rpms --chroot "$COPR_CHROOT" "$COPR_BUILD_ID"
    mv "$COPR_CHROOT"/* .
else
    echo "Not running within packit and no CBS/koji task ID provided"
    exit 1
fi

PACKAGEDIR="$PWD"

# This will match both the regular and the debuginfo rpm so make sure we select only the
# non-debuginfo rpm.
RPMS=(systemd-tests-*.rpm)
rpm2cpio "${RPMS[0]}" | cpio --make-directories --extract
pushd usr/lib/systemd/tests
mkosi_hash="$(grep "MinimumVersion=commit:" mkosi/mkosi.conf | sed "s|MinimumVersion=commit:||g")"

# Now prepare mkosi at the same version required by the systemd repo.
git clone https://github.com/systemd/mkosi /var/tmp/systemd-integration-tests-mkosi
git -C /var/tmp/systemd-integration-tests-mkosi checkout "$mkosi_hash"

export PATH="/var/tmp/systemd-integration-tests-mkosi/bin:$PATH"

# shellcheck source=/dev/null
. /etc/os-release || . /usr/lib/os-release

tee mkosi/mkosi.local.conf <<EOF
[Distribution]
Distribution=${MKOSI_DISTRIBUTION:-$ID}
Release=${MKOSI_RELEASE:-${VERSION_ID:-rawhide}}

[Content]
PackageDirectories=$PACKAGEDIR
SELinuxRelabel=yes

[Build]
ToolsTreeDistribution=${MKOSI_DISTRIBUTION:-$ID}
ToolsTreeRelease=${MKOSI_RELEASE:-${VERSION_ID:-rawhide}}
ToolsTreePackageDirectories=$PACKAGEDIR
Environment=NO_BUILD=1
WithTests=yes
EOF

if [[ -n "${MKOSI_REPOSITORIES:-}" ]]; then
    tee --append mkosi/mkosi.local.conf <<EOF
[Distribution]
Repositories=$MKOSI_REPOSITORIES

[Build]
ToolsTreeRepositories=$MKOSI_REPOSITORIES
EOF
fi

if [[ -n "${TEST_SELINUX_CHECK_AVCS:-}" ]]; then
    tee --append mkosi/mkosi.local.conf <<EOF
[Runtime]
KernelCommandLineExtra=systemd.setenv=TEST_SELINUX_CHECK_AVCS=$TEST_SELINUX_CHECK_AVCS
EOF
fi

# If we don't have KVM, skip running in qemu, as it's too slow. But try to load the module first.
modprobe kvm || true
if [[ ! -e /dev/kvm ]]; then
    export TEST_NO_QEMU=1
fi

NPROC="$(nproc)"
if [[ "$NPROC" -ge 10 ]]; then
    export TEST_JOURNAL_USE_TMP=1
    NPROC="$((NPROC / 3))"
else
    NPROC="$((NPROC - 1))"
fi

# This test is only really useful if we're building with sanitizers and takes a long time, so let's skip it
# for now.
export TEST_SKIP="TEST-21-DFUZZER"

mkosi genkey
mkosi summary
mkosi -f box -- true
mkosi box -- meson setup build integration-tests/standalone
mkosi -f
mkosi box -- \
    meson test \
        -C build \
        --setup=integration \
        --print-errorlogs \
        --no-stdsplit \
        --max-lines 300 \
        --num-processes "$NPROC" && EC=0 || EC=$?

[[ -d build/meson-logs ]] && find build/meson-logs -type f -exec mv {} "$TMT_TEST_DATA" \;
[[ -d build/test/journal ]] && find build/test/journal -type f -exec mv {} "$TMT_TEST_DATA" \;

popd

exit "$EC"
