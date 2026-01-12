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

pandoc_x86_url="s3://ompi-jenkins-config/pandoc-2.14.2-linux-amd64.tar.gz"
pandoc_arm_url="s3://ompi-jenkins-config/pandoc-2.14.2-linux-arm64.tar.gz"
awscli_x86_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
awscli_arm_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"

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

echo "==> Platform: $PLATFORM_ID"
echo "==> Version:  $VERSION_ID"
echo "==> Architecture: $arch"

OPTIND=1         # Reset in case getopts has been used previously in the shell.
run_test=1       # -b runs an ompi build test; useful for testing new AMIs
clean_ami=1      # -t enables testing mode, where the AMI isn't cleaned up
                 # after the test (so remote logins still work)

while getopts "h?tb" opt; do
    case "$opt" in
    h|\?)
        echo "usage: customize-ami.sh [-t]"
        exit 1
        ;;
    b)
        run_test=1
        ;;
    t)
        clean_ami=0
        ;;
    esac
done

pandoc_installed=0

skip_make_check=0
skip_make_dist=0
venv_preflight_modules=

PIP_CMD="pip3"
MAKE_CMD="make"

case $PLATFORM_ID in
    rhel|centos)
        echo "==> Installing packages"
        # RHEL's default repos only include the "base" compiler
        # version, so don't worry about script version
        # differentiation.
        sudo yum -y update
        sudo yum -y group install "Development Tools"
        sudo yum -y install libevent hwloc hwloc-libs gdb
        labels="${labels} linux rhel ${VERSION_ID}"
        case $VERSION_ID in
            8.*)
                sudo yum -y install python3.8 \
                  gcc gcc-c++ gcc-gfortran \
                  java-17-openjdk-headless
                sudo yum -y remove java-1.8.0-openjdk-headless
                sudo alternatives --set python /usr/bin/python3
                PIP_CMD=pip3.8
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme sphobjinv
                labels="${labels} gcc8"
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
        labels="${labels} linux"
        case $VERSION_ID in
            2)
                sudo yum -y install clang hwloc-devel \
                  python2-pip python2 python2-boto3 python3-pip python3 \
                  java-17-amazon-corretto-headless libevent-devel hwloc-devel \
                  hwloc gdb python3-pip python3-devel
                  sudo pip install mock
                # system python3 is linked against openssl 1.0, which doesn't work with
                # urllib3 2.0 or later.  So pin to an older version of urllib :(.
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme 'urllib3<2' sphobjinv
		venv_preflight_modules='urllib3<2'
                labels="${labels} amazon_linux_2-${arch} gcc7 clang7"
                ;;
            2023)
                sudo yum -y install clang gdb \
                  java-17-amazon-corretto-headless \
                  python3 python3-devel python3-pip \
	          hwloc hwloc-devel libevent libevent-devel \
		  python3-mock
                labels="${labels} amazon_linux_2023-${arch} gcc11 clang15"
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
        # Ubuntu needs a little time on first boot to get APT configured.
        echo "Waiting 15 seconds so initial Apt configuration finishes"
        sleep 15
        echo "==> Installing packages"
        sudo DEBIAN_FRONTEND=noninteractive apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
        sudo DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential gfortran \
             autoconf automake libtool flex hwloc libhwloc-dev git libevent-dev \
             rman pandoc
        pandoc_installed=1
        labels="${labels} linux ubuntu_${VERSION_ID}-${arch}"
        case $VERSION_ID in
            18.04)
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     awscli python3-boto3 python-pip python3-venv \
                     python-mock \
                     openjdk-17-jre-headless \
                     gcc-4.8 g++-4.8 gfortran-4.8 \
                     gcc-5 g++-5 gfortran-5 \
                     gcc-6 g++-6 gfortran-6 \
                     gcc-7 g++-7 gfortran-7 \
                     gcc-8 g++-8 gfortran-8 \
                     clang-3.9 clang-4.0 clang-5.0 clang-6.0 \
                     clang-7 clang-8 clang-9 
                PIP_CMD=pip
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme sphobjinv
                labels="${labels} gcc48 gcc5 gcc6 gcc7 gcc8 clang39 clang40 clang50 clang60 clang7 clang8 clang9"
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
                ;;
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
                labels="${labels} gcc7 gcc8 gcc9 gcc10 clang60 clang7 clang8 clang9 clang10"
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
                ;;
            22.04)
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
                     awscli python-is-python3 python3-boto3 python3-mock \
                     python3-pip python3-venv\
                     openjdk-21-jre-headless \
                     gcc-9 g++-9 gfortran-9 \
                     gcc-10 g++-10 gfortran-10 \
                     gcc-11 g++-11 gfortran-11 \
                     gcc-12 g++-12 gfortran-12 \
                     clang-11 clang-12 clang-13 clang-14 \
                     clang-format-14 bsdutils
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme sphobjinv
                labels="${labels} gcc9 gcc10 gcc11 gcc12 clang11 clang12 clang13 clang14"
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
                     openjdk-21-jdk-headless \
                     gcc-9 g++-9 gfortran-9 \
                     gcc-10 g++-10 gfortran-10 \
                     gcc-11 g++-11 gfortran-11 \
                     gcc-12 g++-12 gfortran-12 \
                     gcc-13 g++-13 gfortran-13 \
                     gcc-14 g++-14 gfortran-14 \
                     clang-14 clang-15 flang-15 clang-16 flang-16 \
                     clang-17 flang-17 clang-18 flang-18 \
                     clang-format bsdutils unzip
                sudo ${PIP_CMD} install --break-system-packages sphobjinv
                ( cd $HOME
                  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                  unzip awscliv2.zip
                  sudo ./aws/install
                  rm -rf awscliv2.zip aws
                )
                labels="${labels} gcc9 gcc10 gcc11 gcc12 gcc13 gcc14 clang11 clang12 clang13 clang14"
                if test "$arch" = "x86_64" ; then
                    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install gcc-multilib g++-multilib gfortran-multilib
                    labels="${labels} 32bit_builds"
                fi
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
        # wait for zypper auto-updates to finish
        echo "Waiting 180 seconds so initial Zypper configuration finishes"
        sleep 180
        while pgrep -x 'zypper' > /dev/null ; do
            echo "Waiting 10 seconds for zypper to exit...."
            sleep 10
        done
        sudo zypper -n update
        sudo zypper -n install gcc gcc-c++ gcc-fortran \
             autoconf automake libtool flex make gdb git bzip2
        labels="${labels} linux sles_${VERSION_ID}-${arch}"
        case $VERSION_ID in
            15.*)
                sudo zypper -n install \
                     java-17-openjdk-headless \
                     python3-pip
                PIP_CMD=pip
                sudo ${PIP_CMD} install sphinx recommonmark docutils sphinx-rtd-theme \
		     importlib_resources dataclasses sphobjinv
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
        ;;
    FreeBSD)
        labels="${labels} freebsd freebsd-${VERSION_ID}-${arch}"
        su -m root -c 'pkg install -y sudo'
        if ! grep -q '^%wheel ALL=(ALL) NOPASSWD: ALL' /usr/local/etc/sudoers ; then
            echo "--> Updating sudoers"
            su -m root -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /usr/local/etc/sudoers'
        else
            echo "--> Skipping sudoers update"
        fi

        if ! grep -q '/dev/fd' /etc/fstab ; then
            echo "Adding /dev/fd entry to /etc/fstab"
            sudo sh -c 'echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab'
        fi
        if ! grep -q '/proc' /etc/fstab ; then
            echo "Adding /proc entry to /etc/fstab"
            sudo sh -c 'echo "proc /proc procfs rw 0 0 " >> /etc/fstab'
        fi

        case $VERSION_ID in
            15.*)
                sudo pkg install -y openjdk17 autoconf automake libtool gcc wget \
                     curl git hs-pandoc libevent-devel hwloc2 \
                     lang/python3 py311-pip gmake

                MAKE_CMD=gmake
                PIP_CMD=pip

                skip_make_check=1
                pandoc_installed=1
                ;;
            *)
                echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
                exit 1
                ;;
        esac
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

    aws s3 cp "${pandoc_url}" "${pandoc_tarname}"
    tar xf "${pandoc_tarname}"
    # Pandoc does not name its directories exactly the same name
    # as the tarball.  Sigh.
    pandoc_dir=`find . -maxdepth 1 -name "pandoc*" -type d -print`
    sudo cp "${pandoc_dir}/bin/pandoc" "/usr/local/bin/pandoc"
    rm -rf "${pandoc_tarname}" "${pandoc_dir}"
fi


echo "==> Building pyenv"
cd ${HOME}
cat <<EOF > ${HOME}/ompi-setup-python.sh
PIP_CMD=${PIP_CMD}
. ${HOME}/ompi-venv/bin/activate
EOF
python3 -m venv ompi-venv
. ${HOME}/ompi-setup-python.sh
git clone --recurse-submodules https://github.com/open-mpi/ompi.git
if test "${venv_preflight_modules}" != "" ; then
    ${PIP_CMD} install ${venv_preflight_modules}
fi
find ompi -name "requirements.txt" -exec ${PIP_CMD} install -r {} \;


if test $run_test != 0; then
    # for these tests, fail the script if a test fails
    echo "==> Running Compile test"
    cd ${HOME}/ompi
    ./autogen.pl
    ./configure --prefix=$HOME/install
    ${MAKE_CMD} -j 4 all
    if test "${skip_make_check}" = "0" ; then
        ${MAKE_CMD} check
    fi
    ${MAKE_CMD} install
    if test "${skip_make_dist}" = "0" ; then
        ${MAKE_CMD} dist
    fi
    cd $HOME
    rm -rf ${HOME}/ompi ${HOME}/install
    echo "==> SUCCESS!  Open MPI compiled!"
fi


echo "==> Deactivating pyenv"
deactivate


if test "${clean_ami}" != "0" ; then
    echo "==> Cleaning instance"

    if test "${PLATFORM_ID}" = "FreeBSD" ; then
        sudo touch /firstboot
    fi

    rm -rf ${HOME}/.ssh ${HOME}/.history ${HOME}/.bash_history ${HOME}/.sudo_as_admin_successful ${HOME}/.cache ${HOME}/.oracle_jre_usage
    sudo rm -rf /var/log/*
    sudo rm -f /etc/ssh/ssh_host*
    sudo rm -rf /root/* ~root/.ssh ~root/.history ~root/.bash_history
    echo "Recommended labels: ${labels}"
else
    echo "Skipped cleaning instance.  Do not use to build AMI!"
fi

echo "==> All done!"


# cleanup phase
