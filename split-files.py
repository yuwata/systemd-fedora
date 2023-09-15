import re, sys, os, collections

buildroot = sys.argv[1]
known_files = sys.stdin.read().splitlines()
known_files = {line.split()[-1]:line for line in known_files}

def files(root):
    os.chdir(root)
    todo = collections.deque(['.'])
    while todo:
        n = todo.pop()
        files = os.scandir(n)
        for file in files:
            yield file
            if file.is_dir() and not file.is_symlink():
                todo.append(file)

o_libs = open('.file-list-libs', 'w')
o_udev = open('.file-list-udev', 'w')
o_ukify = open('.file-list-ukify', 'w')
o_boot = open('.file-list-boot', 'w')
o_pam = open('.file-list-pam', 'w')
o_rpm_macros = open('.file-list-rpm-macros', 'w')
o_devel = open('.file-list-devel', 'w')
o_container = open('.file-list-container', 'w')
o_networkd = open('.file-list-networkd', 'w')
o_oomd_defaults = open('.file-list-oomd-defaults', 'w')
o_remote = open('.file-list-remote', 'w')
o_resolve = open('.file-list-resolve', 'w')
o_tests = open('.file-list-tests', 'w')
o_standalone_repart = open('.file-list-standalone-repart', 'w')
o_standalone_tmpfiles = open('.file-list-standalone-tmpfiles', 'w')
o_standalone_sysusers = open('.file-list-standalone-sysusers', 'w')
o_standalone_shutdown = open('.file-list-standalone-shutdown', 'w')
o_main = open('.file-list-main', 'w')
for file in files(buildroot):
    n = file.path[1:]
    if re.match(r'''/usr/(share|include)$|
                    /usr/share/man(/man.|)$|
                    /usr/share/zsh(/site-functions|)$|
                    /usr/share/dbus-1$|
                    /usr/share/dbus-1/system.d$|
                    /usr/share/dbus-1/(system-|)services$|
                    /usr/share/polkit-1(/actions|/rules.d|)$|
                    /usr/share/pkgconfig$|
                    /usr/share/bash-completion(/completions|)$|
                    /usr(/lib|/lib64|/bin|/sbin|)$|
                    /usr/lib.*/(security|pkgconfig)$|
                    /usr/lib/rpm(/macros.d|)$|
                    /usr/lib/firewalld(/services|)$|
                    /usr/share/(locale|licenses|doc)|             # no $
                    /etc(/pam\.d|/xdg|/X11|/X11/xinit|/X11.*\.d|)$|
                    /etc/(dnf|dnf/protected.d)$|
                    /usr/(src|lib/debug)|                         # no $
                    /run$|
                    /var(/cache|/log|/lib|/run|)$
    ''', n, re.X):
        continue

    if n.endswith('.standalone'):
        if 'repart' in n:
            o = o_standalone_repart
        elif 'tmpfiles' in n:
            o = o_standalone_tmpfiles
        elif 'sysusers' in n:
            o = o_standalone_sysusers
        elif 'shutdown' in n:
            o = o_standalone_shutdown
        else:
            assert False, 'Found .standalone not belonging to known packages'

    elif '/security/pam_' in n or '/man8/pam_' in n:
        o = o_pam
    elif '/rpm/' in n:
        o = o_rpm_macros
    elif '/usr/lib/systemd/tests' in n:
        o = o_tests
    elif 'ukify' in n:
        o = o_ukify
    elif re.search(r'/libsystemd-(shared|core)-.*\.so$', n):
        o = o_main
    elif re.search(r'/libcryptsetup-token-systemd-.*\.so$', n):
        o = o_udev
    elif re.search(r'/lib.*\.pc|/man3/|/usr/include|\.so$', n):
        o = o_devel
    elif re.search(r'''journal-(remote|gateway|upload)|
                       systemd-remote\.conf|
                       /usr/share/systemd/gatewayd|
                       /var/log/journal/remote
    ''', n, re.X):
        o = o_remote

    elif re.search(r'''mymachines|
                       machinectl|
                       systemd-nspawn|
                       import-pubring.gpg|
                       systemd-(machined|import|pull)|
                       /machine.slice|
                       /machines.target|
                       var-lib-machines.mount|
                       org.freedesktop.(import|machine)1
    ''', n, re.X):
        o = o_container

    elif re.search(r'''/usr/lib/systemd/network/80-|
                       networkd|
                       networkctl|
                       org.freedesktop.network1|
                       sysusers\.d/systemd-network.conf|
                       tmpfiles\.d/systemd-network.conf|
                       systemd\.network|
                       systemd\.netdev
    ''', n, re.X):
        o = o_networkd

    elif '.so.' in n:
        o = o_libs

    elif re.search(r'''udev(?!\.pc)|
                       hwdb|
                       bootctl|
                       boot-update|
                       bless-boot|
                       boot-system-token|
                       kernel-install|
                       installkernel|
                       vconsole|
                       backlight|
                       rfkill|
                       random-seed|
                       modules-load|
                       timesync|
                       crypttab|
                       cryptenroll|
                       cryptsetup|
                       kmod|
                       quota|
                       pstore|
                       sleep|suspend|hibernate|
                       systemd-tmpfiles-setup-dev|
                       network/98-default-mac-none.link|
                       network/99-default.link|
                       growfs|makefs|makeswap|mkswap|
                       fsck|
                       repart|
                       gpt-auto|
                       volatile-root|
                       veritysetup|
                       integritysetup|
                       integritytab|
                       remount-fs|
                       /initrd|
                       systemd-pcrphase|
                       systemd-measure|
                       /boot$|
                       /kernel/|
                       /kernel$|
                       /modprobe.d|
                       binfmt|
                       sysctl|
                       coredump|
                       homed|home1|
                       portabled|portable1
    ''', n, re.X):     # coredumpctl, homectl, portablectl are included in the main package because
                       # they can be used to interact with remote daemons. Also, the user could be
                       # confused if those user-facing binaries are not available.
        o = o_udev

    elif re.search(r'''/boot/efi|
                       /usr/lib/systemd/boot|
                       sd-boot|systemd-boot\.|loader.conf
    ''', n, re.X):
        o = o_boot

    elif re.search(r'''resolved|resolve1|
                       systemd-resolve|
                       resolvconf|
                       systemd\.(positive|negative)
    ''', n, re.X):     # resolvectl and nss-resolve are in the main package.
        o = o_resolve

    elif re.search(r'10-oomd-.*defaults.conf|lib/systemd/oomd.conf.d', n, re.X):
        o = o_oomd_defaults

    else:
        o = o_main

    if n in known_files:
        prefix = ' '.join(known_files[n].split()[:-1])
        if prefix:
            prefix += ' '
    elif file.is_dir() and not file.is_symlink():
        prefix = '%dir '
    elif 'README' in n:
        prefix = '%doc '
    elif n.startswith('/etc'):
        prefix = '%config(noreplace) '
    else:
        prefix = ''

    suffix = '*' if '/man/' in n else ''

    print(f'{prefix}{n}{suffix}', file=o)
