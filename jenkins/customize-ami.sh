#!/bin/sh
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Script to take a normal EC2 AMI and make it OMPI Jenkins-ified,
# intended to be run on a stock instance.  This script should probably
# not be called directly (except when debugging), but instead called
# from the packer.json file included in this directory.  Packer will
# automate creating all current AMIs, using this script to configure
# all the in-AMI bits.
#
# It is recommended that you use build-amis.sh to build a current set
# of AMIs; see build-amis.sh for usage details.
#

set -e

pandoc_x86_url="https://github.com/jgm/pandoc/releases/download/3.12/pandoc-3.12-linux-amd64.tar.gz"
pandoc_arm_url="https://github.com/jgm/pandoc/releases/download/3.12/pandoc-3.12-linux-arm64.tar.gz"
awscli_x86_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
awscli_arm_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"

libfabric_url="https://github.com/ofiwg/libfabric/releases/download/v2.7.0/libfabric-2.7.0.tar.bz2"
ucx_url="https://github.com/openucx/ucx/releases/download/v1.22.0/ucx-1.22.0.tar.gz"
xpmem_repo="https://github.com/hpc/xpmem.git"
kdreg2_repo="https://github.com/HewlettPackard/shs-kdreg2.git"

labels="ec2"

os=`uname -s`
arch=`uname -m`
if test "${os}" = "Linux"; then
    eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
    eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"
else
    PLATFORM_ID=`uname -s`
    VERSION_ID=`uname -r`
fi

if test "${arch}" = "x86_64" ; then
    # seriously, Corretto?
    corretto_arch="x64"
else
    corretto_arch=${arch}
fi

echo "==> Platform: $PLATFORM_ID"
echo "==> Version:  $VERSION_ID"
echo "==> Architecture: $arch"

OPTIND=1         # Reset in case getopts has been used previously in the shell.
run_test=1       # -b runs an ompi build test; useful for testing new AMIs
ompi_compiler_script=${HOME}/ompi-compiler-setup.sh

while getopts "h?b" opt; do
    case "$opt" in
    h|\?)
        echo "usage: customize-ami.sh [-t]"
        exit 1
        ;;
    b)
        run_test=1
        ;;
    esac
done

pandoc_installed=0

skip_make_check=0
skip_make_dist=0
venv_preflight_modules=

# Distribution-tarball builder AMI.  When the Packer provisioner sets
# JENKINS_DIST_BUILDER=1, this is the AL2023 "dist" variant: it must NOT leave
# pandoc, the GNU Autotools, Flex, or M4 installed in system paths (the dist
# tarball jobs build their own version-pinned Autotools and must not pick up
# the distro's copies).  We still install everything normally -- including the
# "Development Tools" group -- and then remove those packages at the very end,
# rather than teasing them out of the group install.  Because removing the
# Autotools makes the in-AMI Open MPI build test impossible (it needs
# autogen.pl -> autoconf/automake/libtool), that test is also skipped here.
dist_builder=0
if test "${JENKINS_DIST_BUILDER}" = "1" ; then
    dist_builder=1
    run_test=0
    echo "==> Distribution-tarball builder: will remove pandoc/Autotools/Flex/M4 and skip build test"
fi

# Whether to build and install the XPMEM / kdreg2 *kernel modules* (in addition
# to the userspace library/headers, which are always installed on Linux).
# Building a kernel module requires a kernel-devel/headers package that matches
# the running kernel and source that compiles against it; only platforms known
# to satisfy both opt in below.
build_xpmem_kmod=0
build_kdreg2_kmod=0

# Extra configure argument used when building XPMEM, to force its install
# libdir.  XPMEM installs into /usr and lets its autotools choose libdir from
# the system config.site.  On a 64-bit multilib distro the library must land in
# ${exec_prefix}/lib64 to be on the dynamic linker's default search path; most
# such distros (RHEL, SUSE, Amazon Linux 2023) ship a config.site that sets
# that, but Amazon Linux 2 does not, so it defaults to ${exec_prefix}/lib
# (/usr/lib) -- which AL2's loader does not search -- and Open MPI's "make
# check" then fails with "libxpmem.so.0: cannot open shared object file".  Only
# the platform(s) with that broken default set this below; everywhere else the
# autotools default is already correct and this stays empty.
xpmem_libdir_arg=

PIP_CMD="pip3"
MAKE_CMD="make"
# Interpreter used to create the Open MPI venv.  Some distros ship an old
# default python3 (e.g. RHEL 8 / Python 3.6) that cannot satisfy Open MPI's
# newer doc requirements (requests>=2.33.0 needs Python >=3.10); such platforms
# override this with a newer interpreter installed below.
VENV_PYTHON="python3"


echo "==> Waiting for cloud-init to complete"
sudo cloud-init status --wait || true


# Disable password-based SSH authentication *first*, before any of the long
# package-install and compile steps below.  Automated security scanners probe
# fresh instances within minutes of launch and will isolate (and enable
# termination protection on) any instance that still accepts password logins;
# because the full customize run takes 15-20+ minutes, hardening sshd at the
# end leaves a long window in which the build instance gets quarantined
# mid-provision and Packer fails with "Script disconnected unexpectedly".
# Doing it here shrinks that window to a few seconds.
#
# Some base images allow password-based SSH login: most set
# PasswordAuthentication no but, e.g., SLES 15 ships
# KbdInteractiveAuthentication yes, which (via PAM) still permits interactive
# password logins.  Disable both forms on every AMI.  Prefer a drop-in in
# sshd_config.d (honored by all current platforms), then verify with
# "sshd -T" and fall back to editing the main sshd_config if the drop-in is
# not picked up.
echo "==> Disabling password-based SSH authentication"
ssh_hardening_conf="/etc/ssh/sshd_config.d/99-open-mpi-disable-password-auth.conf"
sudo mkdir -p /etc/ssh/sshd_config.d
sudo sh -c "cat > ${ssh_hardening_conf}" <<'SSHEOF'
# Added by Open MPI customize-ami.sh: never allow password-based logins.
PasswordAuthentication no
KbdInteractiveAuthentication no
SSHEOF
sudo chmod 644 "${ssh_hardening_conf}"

# sshd is in /usr/sbin on Linux, /usr/sbin on FreeBSD too.
sshd_bin=`command -v sshd || echo /usr/sbin/sshd`
effective=`sudo ${sshd_bin} -T 2>/dev/null | grep -iE '^(passwordauthentication|kbdinteractiveauthentication)'`
echo "--> Effective after drop-in:"
echo "${effective}"
if echo "${effective}" | grep -qi 'authentication yes' || test -z "${effective}" ; then
    # Drop-in not honored (or sshd -T unavailable); force the setting in the
    # main config file as well.
    echo "--> Drop-in not fully effective; editing main sshd_config"
    for opt in PasswordAuthentication KbdInteractiveAuthentication ChallengeResponseAuthentication ; do
        if sudo grep -qiE "^[[:space:]]*#?[[:space:]]*${opt}[[:space:]]" /etc/ssh/sshd_config ; then
            # Rewrite any existing (possibly commented) directive to "<opt> no".
            # Use a temp file instead of "sed -i" for GNU/BSD portability.
            sudo sed -E "s/^[[:space:]]*#?[[:space:]]*${opt}[[:space:]].*/${opt} no/I" \
                /etc/ssh/sshd_config > /tmp/sshd_config.new
            sudo sh -c "cat /tmp/sshd_config.new > /etc/ssh/sshd_config"
            rm -f /tmp/sshd_config.new
        else
            sudo sh -c "echo '${opt} no' >> /etc/ssh/sshd_config"
        fi
    done
    echo "--> Effective after sshd_config edit:"
    sudo ${sshd_bin} -T 2>/dev/null | grep -iE '^(passwordauthentication|kbdinteractiveauthentication)' || true
fi

# The running sshd still has the old configuration cached, so the changes
# above do not take effect until it re-reads its configuration.  Reload it now
# so the hardened config applies to new connections immediately -- this is the
# whole point of doing it early, so the scanner never sees password auth
# enabled.
#
# Prefer "reload" over "restart": a reload makes sshd re-read its config and
# apply it to all *new* connections (which is all we need -- future scanner
# probes), while leaving already-established sessions untouched.  This matters
# because Packer is driving this script over an SSH session; a full "restart"
# can tear that control connection down and make Packer fail the build with
# "Script disconnected unexpectedly".  Fall back to a restart only if the
# platform's init system cannot reload sshd.
echo "--> Reloading sshd to apply the new configuration"
if test "${PLATFORM_ID}" = "FreeBSD" ; then
    # rc.d sshd supports "reload" (HUPs the daemon) and keeps current sessions.
    sudo service sshd reload || sudo service sshd restart
else
    # Linux distros name the unit either "sshd" (Amazon Linux, RHEL, SLES) or
    # "ssh" (Debian/Ubuntu).  Reload whichever one this platform provides,
    # falling back to a restart if reload is unsupported.
    sshd_reloaded=0
    for svc in sshd ssh ; do
        if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "^${svc}.service" ; then
            sudo systemctl reload "${svc}.service" \
                || sudo systemctl restart "${svc}.service"
            sshd_reloaded=1
            break
        fi
    done
    if test "${sshd_reloaded}" -eq 0 ; then
        echo "ERROR: could not find an sshd/ssh systemd unit to reload"
        exit 1
    fi
fi
echo "--> Effective after sshd reload:"
sudo ${sshd_bin} -T 2>/dev/null | grep -iE '^(passwordauthentication|kbdinteractiveauthentication)' || true


# Create a scriptlet on each AMI that can be used by CI jobs to translate a
# compiler version into CC/CXX/FC variables.  Each OS likes to name their
# versioned compilers a bit differently, and this is the sanest step at which to
# create and verify the mapping, saving us from updating the CI scripts every
# time a new compiler version is added to a distro.
cat <<'EOF' > ${ompi_compiler_script}
activate_compiler() {
    compiler=${1}

    if test "${compiler}" = "" ; then
        echo "No argument to activate_compiler()"
        exit 1
    fi

    echo "Activating compiler ${compiler}"
    eval compiler_found=\${AMI_${compiler}_CONFIG}
    if test "${compiler_found}" = "" ; then
        echo "Could not find compiler information for ${compiler}"
        exit 1
    fi
    eval CC=\${AMI_${compiler}_CC}
    if test "${CC}" = "" ; then
        echo "Could not find C compiler for ${compiler}"
        exit 1
    fi
    eval CPP=\${AMI_${compiler}_CPP}
    if test "${CPP}" = "" ; then
        unset CPP
    fi
    eval CXX=\${AMI_${compiler}_CXX}
    if test "${CXX}" = "" ; then
        unset CXX
    fi
    eval FC=\${AMI_${compiler}_FC}
    if test "${FC}" = "" ; then
        unset FC
    fi
}

EOF



case $PLATFORM_ID in
    rhel|centos)
        echo "==> Installing packages"
        # RHEL's default repos only include the "base" compiler
        # version, so don't worry about script version
        # differentiation.
        sudo yum -y update
        sudo yum -y group install "Development Tools"
        sudo yum -y install libevent hwloc hwloc-libs gdb
        # rdma-core development packages are required to build libfabric's efa
        # provider.  Always use the system-provided rdma-core packages.
        sudo yum -y install rdma-core-devel libibverbs-devel librdmacm-devel
        case $VERSION_ID in
            8.*)
                # RHEL 8's default python3 is 3.6, which is too old for Open
                # MPI's doc requirements (requests>=2.33.0 needs Python >=3.10).
                # Install python3.11 from AppStream and use it for the venv.
                sudo yum -y install python3.8 python3.11 python3.11-pip \
                  gcc gcc-c++ gcc-gfortran \
                  java-21-openjdk-headless
                sudo yum -y remove java-1.8.0-openjdk-headless
                sudo alternatives --set python /usr/bin/python3
                PIP_CMD=pip3.11
                VENV_PYTHON=python3.11
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme sphobjinv
                labels="${labels} linux rhel8 rhel8-${arch}"
                ;;
            9.*)
                sudo yum -y install python3 \
                  gcc gcc-c++ gcc-gfortran \
                  java-21-openjdk-headless
                sudo yum -y remove java-1.8.0-openjdk-headless
                PIP_CMD=pip3
                labels="${labels} linux rhel9 rhel9-${arch}"
                ;;
            10.*)
                sudo yum -y install python3 \
                  gcc gcc-c++ gcc-gfortran \
                  java-25-openjdk-headless
                PIP_CMD=pip3
                labels="${labels} linux rhel10 rhel10-${arch}"
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
        if test "$arch" = "x86_64" ; then
            awscli_url="${awscli_x86_url}"
        else
            awscli_url="${awscli_arm_url}"
        fi
        (cd /tmp && \
         curl "${awscli_url}" -o "awscliv2.zip" && \
         unzip awscliv2.zip && \
         sudo ./aws/install &&
         rm -rf aws)
        ;;

    amzn)
        echo "==> Installing packages"
        sudo yum -y update
        sudo yum -y groupinstall "Development Tools"
        # rdma-core development packages are required to build libfabric's efa
        # provider.  Always use the system-provided rdma-core packages.
        sudo yum -y install rdma-core-devel libibverbs-devel librdmacm-devel
        case $VERSION_ID in
            2)
                sudo yum -y install clang hwloc-devel \
                  python2-pip python2 python2-boto3 python3-pip python3 \
                  libevent-devel hwloc-devel \
                  hwloc gdb python3-pip python3-devel
                  sudo pip install mock
                # system python3 is linked against openssl 1.0, which doesn't work with
                # urllib3 2.0 or later.  So pin to an older version of urllib :(.
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme 'urllib3<2' sphobjinv
                curl -LO https://corretto.aws/downloads/latest/amazon-corretto-25-${corretto_arch}-linux-jdk.rpm
                sudo rpm -ivh amazon-corretto-25-${corretto_arch}-linux-jdk.rpm
                rm amazon-corretto-25-${corretto_arch}-linux-jdk.rpm
		venv_preflight_modules='urllib3<2'
                # Amazon Linux 2 ships no config.site, so XPMEM's autotools
                # default libdir to /usr/lib instead of /usr/lib64; force the
                # 64-bit libdir so libxpmem lands on the loader's search path.
                xpmem_libdir_arg="--libdir=\${exec_prefix}/lib64"
                labels="${labels} linux amazon_linux_2 amazon_linux_2-${arch}"
                ;;
            2023)
                sudo yum -y install clang gdb \
                  java-25-amazon-corretto-headless \
                  python3 python3-devel python3-pip \
                  hwloc hwloc-devel libevent libevent-devel \
                  python3-mock python3-boto3
                # AL2023's default python3 is 3.9 and stays there for the life
                # of the release, which is too old for Open MPI's doc
                # requirements (requests>=2.33.0 needs Python >=3.10).  Install
                # python3.11 from the AL2023 repos and use it for the venv.
                sudo yum -y install python3.11 python3.11-pip
                PIP_CMD=pip3.11
                VENV_PYTHON=python3.11
                # Build the XPMEM and kdreg2 kernel modules on AL2023: the CI
                # tests exercise both.  AL2023 ships its kernel-devel/headers
                # under a version-prefixed package name (e.g. kernel6.18-devel),
                # not the generic "kernel-devel" (which tracks a different,
                # older kernel stream).  Derive the prefix from the running
                # kernel's major.minor so this keeps working as the kernel moves.
                kver_mm=`uname -r | grep -oE '^[0-9]+\.[0-9]+'`
                sudo yum -y install "kernel${kver_mm}-devel" "kernel${kver_mm}-headers" \
                  elfutils-libelf-devel
                build_xpmem_kmod=1
                build_kdreg2_kmod=1
                labels="${labels} linux amazon_linux_2023-${arch}"
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
        echo "==> Disabling Security Updates"
        sed -e 's/repo_upgrade: security/repo_upgrade: none/g' /etc/cloud/cloud.cfg > /tmp/cloud.cfg.new
        sudo mv -f /tmp/cloud.cfg.new /etc/cloud/cloud.cfg
        ;;

    ubuntu)
        echo "==> Installing packages"
        sudo DEBIAN_FRONTEND=noninteractive apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential gfortran \
             autoconf automake libtool flex hwloc libhwloc-dev git libevent-dev \
             rman pandoc
        # rdma-core development packages are required to build libfabric's efa
        # provider.  Always use the system-provided rdma-core packages.  On
        # Debian/Ubuntu the rdma-core source package ships these as
        # libibverbs-dev and librdmacm-dev.
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y install libibverbs-dev librdmacm-dev
        pandoc_installed=1
        labels="${labels} linux ubuntu_${VERSION_ID}-${arch}"
        case $VERSION_ID in
            20.04)
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     awscli python-is-python3 python3-boto3 python3-mock \
                     python3-pip python3-venv\
                     openjdk-21-jdk-headless \
                     gcc-7 g++-7 gfortran-7 \
                     gcc-8 g++-8 gfortran-8 \
                     gcc-9 g++-9 gfortran-9 \
                     gcc-10 g++-10 gfortran-10 \
                     clang-6.0 clang-7 clang-8 clang-9 clang-10 \
                     clang-format-11 bsdutils
                sudo ${PIP_CMD} install -U sphinx recommonmark docutils sphinx-rtd-theme sphobjinv

                for i in 7 8 9 10 ; do
                    echo "AMI_gcc${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CC=gcc-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CPP=cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CXX=g++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_FC=gfortran-${i}" >> ${ompi_compiler_script}
                    labels="${labels} gcc${i}"
                done
                # Clang 6 binaries are named slightly different than later versions
                echo "AMI_clang6_CONFIG=1" >> ${ompi_compiler_script}
                echo "AMI_clang6_CC=clang-6.0" >> ${ompi_compiler_script}
                echo "AMI_clang6_CPP=clang-cpp-6.0" >> ${ompi_compiler_script}
                echo "AMI_clang6_CXX=clang++-6.0" >> ${ompi_compiler_script}
                labels="${labels} clang6"
                for i in 7 8 9 10 ; do
                    echo "AMI_clang${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CC=clang-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CPP=clang-cpp${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CXX=clang++-${i}" >> ${ompi_compiler_script}
                    labels="${labels} clang${i}"
                done
                labels="${labels} ubuntu_${VERSION_ID}"
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
                ;;
            22.04)
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     awscli python-is-python3 python3-boto3 python3-mock \
                     python3-pip python3-venv\
                     openjdk-25-jre-headless \
                     gcc-9 g++-9 gfortran-9 \
                     gcc-10 g++-10 gfortran-10 \
                     gcc-11 g++-11 gfortran-11 \
                     gcc-12 g++-12 gfortran-12 \
                     clang-11 clang-12 clang-13 clang-14 \
                     clang-format-14 bsdutils
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme sphobjinv

                for i in 9 10 11 12 ; do
                    echo "AMI_gcc${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CC=gcc-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CPP=cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CXX=g++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_FC=gfortran-${i}" >> ${ompi_compiler_script}
                    labels="${labels} gcc${i}"
                done
                for i in 11 12 13 14 ; do
                    echo "AMI_clang${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CC=clang-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CPP=clang-cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CXX=clang++-${i}" >> ${ompi_compiler_script}
                    labels="${labels} clang${i}"
                done
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
                ;;
            24.04)
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     python-is-python3 python3-boto3 python3-mock \
                     python3-pip python3-venv python3-recommonmark python3-docutils \
                     python3-sphinx python3-sphinx-rtd-theme  \
                     openjdk-25-jdk-headless \
                     gcc-9 g++-9 gfortran-9 \
                     gcc-10 g++-10 gfortran-10 \
                     gcc-11 g++-11 gfortran-11 \
                     gcc-12 g++-12 gfortran-12 \
                     gcc-13 g++-13 gfortran-13 \
                     gcc-14 g++-14 gfortran-14 \
                     clang-15 flang-15 clang-16 flang-16 \
                     clang-17 flang-17 clang-18 flang-18 \
                     clang-format bsdutils unzip
                sudo ${PIP_CMD} install --break-system-packages sphobjinv
                ( cd $HOME
                  if test "$arch" = "x86_64" ; then awscli_url="${awscli_x86_url}" ; else awscli_url="${awscli_arm_url}" ; fi
                  curl "${awscli_url}" -o "awscliv2.zip"
                  unzip awscliv2.zip
                  sudo ./aws/install
                  rm -rf awscliv2.zip aws
                )
                for i in 9 10 11 12 13 14 ; do
                    echo "AMI_gcc${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CC=gcc-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CPP=cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CXX=g++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_FC=gfortran-${i}" >> ${ompi_compiler_script}
                    labels="${labels} gcc${i}"
                done
                for i in 15 16 17 18 ; do
                    echo "AMI_clang${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CC=clang-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CPP=clang-cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CXX=clang++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_FC=flang-new-${i}" >> ${ompi_compiler_script}
                    labels="${labels} clang${i}"
                done
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
                ;;
            26.04)
                # we skip clang 20, because Ubuntu's 26.04 doesn't allow flang
                # 20 and flang 21 to be installed at the same time.
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     python3-boto3 python3-mock \
                     python3-pip python3-venv openjdk-25-jdk-headless \
                     gcc-11 g++-11 gfortran-11 \
                     gcc-12 g++-12 gfortran-12 \
                     gcc-13 g++-13 gfortran-13 \
                     gcc-14 g++-14 gfortran-14 \
                     gcc-15 g++-15 gfortran-15 \
                     clang-17 flang-17 clang-18 flang-18 \
                     clang-19 flang-19 \
                     clang-21 flang-21 \
                     clang-format bsdutils unzip
                ( cd $HOME
                  if test "$arch" = "x86_64" ; then awscli_url="${awscli_x86_url}" ; else awscli_url="${awscli_arm_url}" ; fi
                  curl "${awscli_url}" -o "awscliv2.zip"
                  unzip awscliv2.zip
                  sudo ./aws/install
                  rm -rf awscliv2.zip aws
                )
                for i in 11 12 13 14 15; do
                    echo "AMI_gcc${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CC=gcc-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CPP=cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_CXX=g++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_gcc${i}_FC=gfortran-${i}" >> ${ompi_compiler_script}
                    labels="${labels} gcc${i}"
                done
                for i in 17 18 19 21 ; do
                    echo "AMI_clang${i}_CONFIG=1" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CC=clang-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CPP=clang-cpp-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_CXX=clang++-${i}" >> ${ompi_compiler_script}
                    echo "AMI_clang${i}_FC=flang-new-${i}" >> ${ompi_compiler_script}
                    labels="${labels} clang${i}"
                done
                # Build the kdreg2 kernel module on Ubuntu 26.04 (its header is
                # installed on all Linux AMIs, but here we also build the
                # module).  XPMEM's kernel module is intentionally NOT built
                # here: hpc/xpmem does not compile against the 7.x kernel
                # (it still references task_struct.cpus_allowed).
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "linux-headers-$(uname -r)"
                build_kdreg2_kmod=1
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
        echo "==> Disabling Security Updates"
        sed -e 's/APT::Periodic::Update-Package-Lists "1";/APT::Periodic::Update-Package-Lists "0";/g' /etc/apt/apt.conf.d/20auto-upgrades | sed -e 's/APT::Periodic::Unattended-Upgrade "1";/APT::Periodic::Unattended-Upgrade "0";/g' > /tmp/20auto-upgrades
        sudo mv -f /tmp/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
        ;;

    sles)
        echo "==> Installing packages"
        sudo zypper -n update
        sudo zypper -n install gcc gcc-c++ gcc-fortran \
             autoconf automake libtool flex make gdb git bzip2
        # rdma-core development packages are required to build libfabric's efa
        # provider.  Always use the system-provided rdma-core packages.
        sudo zypper -n install rdma-core-devel libibverbs-devel librdmacm-devel
        case $VERSION_ID in
            15.*)
                # SLES 15's default python3 is 3.6, too old for Open MPI's doc
                # requirements (requests>=2.33.0 needs Python >=3.10).  Install
                # python311 and use it for the venv.
                sudo zypper -n install \
                     java-25-openjdk-headless \
                     python3-pip python311 python311-pip
                PIP_CMD=pip3.11
                VENV_PYTHON=python3.11
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme \
		     importlib_resources dataclasses sphobjinv
                labels="${labels} linux sles_15-${arch}"
                ;;
            16.*)
                sudo zypper -n install \
                     java-25-openjdk-headless \
                     python3-pip
                labels="${labels} linux sles_16-${arch}"
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
        ;;

    FreeBSD)
        echo "==> Configuring FreeBSD to be more Linux like"
        if ! grep -q '/dev/fd' /etc/fstab ; then
            echo "Adding /dev/fd entry to /etc/fstab"
            sudo sh -c 'echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab'
        fi
        if ! grep -q '/proc' /etc/fstab ; then
            echo "Adding /proc entry to /etc/fstab"
            sudo sh -c 'echo "proc /proc procfs rw 0 0 " >> /etc/fstab'
        fi

        echo "==> Installing packages"
        case $VERSION_ID in
            15.*)
                # Install the base toolchain plus the default Python 3.  We do
                # not hard-code the pip package name (py311-pip): the correct
                # py3XX-pip name tracks whatever Python version "lang/python3"
                # pulls in, so derive it at runtime and install that.
                sudo pkg install -y openjdk25 autoconf automake libtool gcc wget \
                     curl git hs-pandoc libevent-devel hwloc2 rust \
                     lang/python3 gmake bash
                pip_pkg=`python3 -c 'import sys; print("py%d%d-pip" % sys.version_info[:2])'`
                echo "--> Installing pip package ${pip_pkg} for default python3"
                sudo pkg install -y "${pip_pkg}"

                MAKE_CMD=gmake
                PIP_CMD=pip

                skip_make_check=1
                skip_make_dist=1
                pandoc_installed=1
                labels="${labels} freebsd freebsd-15-${arch}"
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac

        if test ! -r /bin/bash ; then
            sudo ln -s /usr/local/bin/bash /bin/bash
        fi

        ;;
    *)
        echo "ERROR: Unkonwn platform ${PLATFORM_ID}"
        exit 1
esac

if test $pandoc_installed -eq 0 ; then
    if test $arch == "x86_64" ; then
        pandoc_url=${pandoc_x86_url}
    else
        pandoc_url=${pandoc_arm_url}
    fi
    pandoc_tarname=`basename ${pandoc_url}`

    curl -OL "${pandoc_url}"
    tar xf "${pandoc_tarname}"
    # Pandoc does not name its directories exactly the same name
    # as the tarball.  Sigh.
    pandoc_dir=`find . -maxdepth 1 -name "pandoc*" -type d -print`
    sudo cp "${pandoc_dir}/bin/pandoc" "/usr/local/bin/pandoc"
    rm -rf "${pandoc_tarname}" "${pandoc_dir}"
fi


echo "==> Double Checking Compiler Setup"
. ${ompi_compiler_script}
for compiler in `grep '^AMI_.*_CONFIG' ${ompi_compiler_script} | cut -f2 -d_` ; do
    echo "--> ${compiler}"
    activate_compiler ${compiler}
    echo "${CC} --version"
    ${CC} --version
    if test "${CXX}" = "" ; then
        echo "CXX not set"
    else
        echo "${CXX} --version"
        ${CXX} --version
    fi
    if test "${FC}" = "" ; then
        echo "FC not set"
    else
        echo "${FC} --version"
        ${FC} --version
    fi
done


echo "==> Building pyenv"
cd ${HOME}
# Inside the activated venv the correct pip is always "pip", regardless of
# which versioned python/pip name the distro used for its system packages
# above.  Downstream CI jobs source this file and run "${PIP_CMD} install", so
# pin PIP_CMD to the venv's pip here.
cat <<EOF > ${HOME}/ompi-setup-python.sh
PIP_CMD=pip
. ${HOME}/ompi-venv/bin/activate
EOF
${VENV_PYTHON} -m venv ompi-venv
. ${HOME}/ompi-setup-python.sh
# The pip bundled with the system python (and therefore with the venv) can be
# quite old on some distros.  An old pip fails to resolve newer wheels --
# notably "requests>=2.33.0" pulled in by Open MPI's doc requirements -- which
# in turn means transitive deps such as importlib_resources never get
# installed.  On older pythons that breaks the build (pympistandard needs
# importlib_resources), so always upgrade pip first.
${PIP_CMD} install --upgrade pip setuptools wheel
git clone --recurse-submodules https://github.com/open-mpi/ompi.git
if test "${venv_preflight_modules}" != "" ; then
    ${PIP_CMD} install ${venv_preflight_modules}
fi
find ompi -name "requirements.txt" -exec ${PIP_CMD} install -r {} \;

ompi_configure_args=""

if test "$PLATFORM_ID" != "FreeBSD" ; then
    echo "==> Installing dependency packages"
    cd  ${HOME}
    mkdir -p ${HOME}/packages/src

    if ! test -f /usr/include/xpmem.h ; then
        echo "--> Installing XPMEM"
        cd ${HOME}/packages/src
        git clone ${xpmem_repo} xpmem
        cd xpmem
        ./autogen.sh
        # xpmem_libdir_arg (set per-platform above) forces XPMEM's install
        # libdir on distros whose config.site misdefaults it; see its definition
        # near the top of this script.  It is empty on platforms where the
        # autotools default is already correct.
        if test "${build_xpmem_kmod}" = "1" ; then
            # Build the kernel module (default) plus the userspace library and
            # headers, all installed into /usr.  The CI tests exercise XPMEM,
            # so the module needs to be present and loaded.
            if ! test -e /lib/modules/`uname -r`/build/Module.symvers ; then
                echo "ERROR: no kernel build tree for `uname -r`; cannot build XPMEM module"
                exit 1
            fi
            ./configure --prefix=/usr ${xpmem_libdir_arg}
            ${MAKE_CMD} -j 4 all
            sudo ${MAKE_CMD} install
            # Load the module now and on every boot.
            echo xpmem | sudo tee /etc/modules-load.d/xpmem.conf > /dev/null
            sudo depmod -a
            sudo modprobe xpmem || true
        else
            # Build only the userspace library and headers.  The kernel module
            # is skipped where a matching kernel-devel package is unavailable or
            # the module does not compile against the running kernel; downstream
            # libraries (libfabric, UCX, Open MPI) only need libxpmem and
            # <xpmem.h>.
            ./configure --prefix=/usr --disable-kernel-module ${xpmem_libdir_arg}
            ${MAKE_CMD} -j 4 all
            sudo ${MAKE_CMD} install
        fi
    else
        echo "--> XPMEM already installed"
    fi
    ompi_configure_args="${ompi_configure_args} --with-xpmem"

    if ! test -f /usr/include/linux/kdreg2.h ; then
        echo "--> Installing kdreg2"
        cd ${HOME}/packages/src
        git clone ${kdreg2_repo} kdreg2
        # The userspace header is self-contained and is what downstream
        # libraries (libfabric, UCX) need to detect and compile kdreg2
        # support, so install it on every Linux AMI.  It must land at
        # /usr/include/linux/kdreg2.h: libfabric's --with-kdreg2 probes for
        # <linux/kdreg2.h>, so a flat /usr/include/kdreg2.h is not found and
        # configure fails with "KDREG2 header not found".
        sudo install -D -m 0644 kdreg2/include/kdreg2.h /usr/include/linux/kdreg2.h
        if test "${build_kdreg2_kmod}" = "1" ; then
            # The CI tests exercise kdreg2, so also build and install the
            # kernel module and load it at boot.  kdreg2 uses a plain Kbuild
            # Makefile rather than autotools.
            cd kdreg2
            kver=`uname -r`
            if ! test -e /lib/modules/${kver}/build/Module.symvers ; then
                echo "ERROR: no kernel build tree for ${kver}; cannot build kdreg2 module"
                exit 1
            fi
            ${MAKE_CMD} modules
            sudo ${MAKE_CMD} -C /lib/modules/${kver}/build M=`pwd` modules_install
            echo kdreg2 | sudo tee /etc/modules-load.d/kdreg2.conf > /dev/null
            sudo depmod -a
            sudo modprobe kdreg2 || true
        fi
    else
        echo "--> kdreg2 already installed"
    fi

    if ! test -d ${HOME}/packages/libfabric ; then
        echo "--> Installing Libfabric"
        cd ${HOME}/packages/src
        curl -OL ${libfabric_url}
        tarball=`find . -maxdepth 1 -name "libfabric*.tar*" -print | head -n 1`
        tar xf ${tarball}
        directory=`echo ${tarball} | sed -e 's/\(.*\)\.tar\..*/\1/'`
        cd ${directory}
        # Explicitly disable the verbs provider: now that rdma-core development
        # packages are installed, libfabric would otherwise auto-enable verbs,
        # which fails to build against the older hwloc shipped on some distros
        # (e.g. Amazon Linux 2).
        ./configure --prefix=${HOME}/packages/libfabric --enable-efa --disable-verbs --with-kdreg2
        ${MAKE_CMD} -j 4 all
        ${MAKE_CMD} install
    else
        echo "--> Libfabric already installed"
    fi
    ompi_configure_args="${ompi_configure_args} --with-libfabric=${HOME}/packages/libfabric"

    if ! test -d ${HOME}/packages/ucx ; then
        echo "--> Installing UCX"
        cd ${HOME}/packages/src
        curl -OL ${ucx_url}
        # Restrict to the top-level tarball: a bare "ucx*" also matches the
        # prov/ucx directory inside the extracted libfabric source tree, and
        # find's traversal order is not stable across filesystems/arches.
        tarball=`find . -maxdepth 1 -name "ucx*.tar*" -print | head -n 1`
        tar xf ${tarball}
        directory=`echo ${tarball} | sed -e 's/\(.*\)\.tar\..*/\1/'`
        cd ${directory}
        ./configure --prefix=${HOME}/packages/ucx
        ${MAKE_CMD} -j 4 all
        ${MAKE_CMD} install
    else
        echo "--> UCX already installed"
    fi
    ompi_configure_args="${ompi_configure_args} --with-ucx=${HOME}/packages/ucx"
fi

if test $run_test != 0; then
    # for these tests, fail the script if a test fails
    echo "==> Running Compile test"
    cd ${HOME}/ompi
    ./autogen.pl
    ./configure --prefix=$HOME/install ${ompi_configure_args}
    ${MAKE_CMD} -j 4 all V=1
    if test "${skip_make_check}" = "0" ; then
        ${MAKE_CMD} check VERBOSE=1
    fi
    ${MAKE_CMD} install
    if test "${skip_make_dist}" = "0" ; then
        ${MAKE_CMD} dist
    fi
    cd $HOME
    rm -rf ${HOME}/ompi ${HOME}/install
    echo "==> SUCCESS!  Open MPI compiled!"
fi


if test "${dist_builder}" = "1" ; then
    # Distribution-tarball builder: strip pandoc, the GNU Autotools, Flex, and
    # M4 back out of system paths now that everything that needed them (e.g.
    # building XPMEM/libfabric/UCX) has run.  The dist tarball jobs build their
    # own version-pinned Autotools and prepend it to PATH, so the released
    # tarball must be produced without any dependence on the distro's copies;
    # leaving them installed would mask such a dependence.  Guarded with
    # "|| true" so a package that is absent (or already removed as a dependency
    # of another) never fails the build under "set -e".
    echo "==> Dist builder: removing pandoc, Autotools, Flex, and M4 from system paths"

    # pandoc: on AL2023 the fallback installer drops a static binary at
    # /usr/local/bin/pandoc; also remove any package-managed copy for good
    # measure.
    sudo rm -f /usr/local/bin/pandoc
    sudo yum -y remove pandoc pandoc-common 2>/dev/null || true

    # Autotools + Flex + M4.  Remove autoconf/automake/libtool/flex first, then
    # m4 last (autoconf/automake/bison depend on m4, so pulling m4 would drag
    # them along anyway; removing the others explicitly keeps the intent clear).
    sudo yum -y remove autoconf automake libtool flex 2>/dev/null || true
    sudo yum -y remove m4 2>/dev/null || true

    echo "--> Verifying the tools are no longer on PATH"
    for tool in pandoc autoconf automake libtool aclocal flex m4 ; do
        if command -v "${tool}" >/dev/null 2>&1 ; then
            echo "ERROR: ${tool} is still present at `command -v ${tool}` on the dist builder"
            exit 1
        fi
    done
    echo "--> Confirmed: pandoc, Autotools, Flex, and M4 are absent from system paths"
fi


echo "==> Deactivating pyenv"
deactivate

echo "==> Cleaning instance"
if test "${PLATFORM_ID}" = "FreeBSD" ; then
    sudo touch /firstboot
fi
rm -rf ${HOME}/.ssh ${HOME}/.history ${HOME}/.bash_history ${HOME}/.sudo_as_admin_successful ${HOME}/.cache ${HOME}/.oracle_jre_usage
sudo rm -rf /var/log/*
sudo rm -f /etc/ssh/ssh_host*
sudo rm -rf /root/* ~root/.ssh ~root/.history ~root/.bash_history


echo "Recommended labels: ${labels}"
echo "==> All done!"
