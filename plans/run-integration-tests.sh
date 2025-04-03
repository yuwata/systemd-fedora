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
    koji download-task --noprogress --arch="src,noarch,$(rpm --eval '%{_arch}')" "$KOJI_TASK_ID"
elif [[ -n "${CBS_TASK_ID:-}" ]]; then
    cbs download-task --noprogress --arch="src,noarch,$(rpm --eval '%{_arch}')" "$CBS_TASK_ID"
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

mkdir systemd
rpm2cpio ./systemd-*.src.rpm | cpio --to-stdout --extract './*.tar.gz' | tar xz --strip-components=1 -C systemd

# Now prepare mkosi at the same version required by the systemd repo.
git clone https://github.com/systemd/mkosi /var/tmp/systemd-integration-tests-mkosi
mkosi_hash="$(grep systemd/mkosi@ systemd/.github/workflows/mkosi.yml | sed "s|.*systemd/mkosi@||g")"
git -C /var/tmp/systemd-integration-tests-mkosi checkout "$mkosi_hash"

export PATH="/var/tmp/systemd-integration-tests-mkosi/bin:$PATH"

pushd systemd

# shellcheck source=/dev/null
. /etc/os-release || . /usr/lib/os-release

if [[ -d mkosi ]]; then
    LOCAL_CONF=mkosi/mkosi.local.conf
else
    LOCAL_CONF=mkosi.local.conf
fi

tee "$LOCAL_CONF" <<EOF
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
    tee --append "$LOCAL_CONF" <<EOF
[Distribution]
Repositories=$MKOSI_REPOSITORIES

[Build]
ToolsTreeRepositories=$MKOSI_REPOSITORIES
EOF
fi

if [[ -n "${TEST_SELINUX_CHECK_AVCS:-}" ]]; then
    tee --append "$LOCAL_CONF" <<EOF
[Runtime]
KernelCommandLineExtra=systemd.setenv=TEST_SELINUX_CHECK_AVCS=$TEST_SELINUX_CHECK_AVCS
EOF
fi

# Create missing mountpoint for mkosi sandbox.
mkdir -p /etc/pacman.d/gnupg

# We don't bother with this change if the mkosi configuration is
# in mkosi/ as if that's the case then we know for sure that the
# upstream has this fix as well.
# TODO: drop once BTRFS regression is fixed.
if [[ -f mkosi.repart/10-root.conf ]]; then
    sed -i "s/Format=btrfs/Format=ext4/" mkosi.repart/10-root.conf
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
mkosi -f sandbox -- true
if [[ -d test/integration-tests/standalone ]]; then
    mkosi sandbox -- meson setup build test/integration-tests/standalone
else
    mkosi sandbox -- meson setup -Dintegration-tests=true build
fi
mkosi -f
mkosi sandbox -- \
    meson test \
    -C build \
    --no-rebuild \
    --suite integration-tests \
    --print-errorlogs \
    --no-stdsplit \
    --num-processes "$NPROC" && EC=0 || EC=$?

[[ -d build/meson-logs ]] && find build/meson-logs -type f -exec mv {} "$TMT_TEST_DATA" \;
[[ -d build/test/journal ]] && find build/test/journal -type f -exec mv {} "$TMT_TEST_DATA" \;

popd

exit "$EC"
