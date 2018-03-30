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

labels="ec2"

os=`uname -s`
if test "${os}" = "Linux"; then
    eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
    eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"
else
    PLATFORM_ID=`uname -s`
    VERSION_ID=`uname -r`
fi

echo "==> Platform: $PLATFORM_ID"
echo "==> Version:  $VERSION_ID"

OPTIND=1         # Reset in case getopts has been used previously in the shell.
run_test=0       # -b runs an ompi build test; useful for testing new AMIs
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

echo "==> Installing packages"

case $PLATFORM_ID in
    rhel)
	# RHEL's default repos only include the "base" compiler
	# version, so don't worry about script version
	# differentiation.
	# gcc = 4.8.5
	sudo yum -y update
	sudo yum -y group install "Development Tools"
	sudo yum -y install libevent hwloc hwloc-libs java gdb
	(cd /tmp && \
	 curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip" && \
         unzip awscli-bundle.zip && \
         sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && \
         rm -rf awscli-bundle*)
	labels="${labels} linux rhel ${VERSION_ID} gcc48"
	;;
    amzn)
	sudo yum -y update
	sudo yum -y groupinstall "Development Tools"
	sudo yum -y groupinstall "Java Development"
	sudo yum -y install libevent-devel java-1.8.0-openjdk-devel \
	    java-1.8.0-openjdk gdb python27-mock python27-boto \
	    python27-boto3
	labels="${labels} linux amazon_linux_${VERSION_ID}"
	case $VERSION_ID in
	    2016.09|2017.03)
		# clang == 3.6.2
		sudo yum -y install gcc44 gcc44-c++ gcc44-gfortran \
		     gcc48 gcc48-c++ gcc48-gfortran clang
		sudo alternatives --set java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java
		labels="${labels} gcc44 gcc48 clang36"
		;;
	    *)
		echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
		exit 1
		;;
	esac
	;;
    ubuntu)
	sudo apt-get update
	sudo apt-get -y upgrade
	sudo apt-get -y install build-essential gfortran \
	     autoconf automake libtool flex hwloc libhwloc-dev git \
	     default-jre awscli python-mock python-boto3 rman
	labels="${labels} linux ubuntu_${VERSION_ID}"
	case $VERSION_ID in
	    14.04)
		sudo apt-get -y install gcc-4.4 g++-4.4 gfortran-4.4 \
		     gcc-4.6 g++-4.6 gfortran-4.6 \
		     gcc-4.7 g++-4.7 gfortran-4.7 \
		     gcc-4.8 g++-4.8 gfortran-4.8 \
		     clang-3.6 clang-3.7 clang-3.8
		labels="${labels} gcc44 gcc46 gcc47 gcc48 clang36 clang37 clang38"
		;;
	    16.04)
		sudo apt-get -y install gcc-4.7 g++-4.7 gfortran-4.7 \
		     gcc-4.8 g++-4.8 gfortran-4.8 \
		     gcc-4.9 g++-4.9 gfortran-4.9 \
		     clang-3.6 clang-3.7 clang-3.8
		labels="${labels} gcc47 gcc48 gcc49 gcc5 clang36 clang37 clang38"
		;;
	    *)
		echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
		exit 1
		;;
	esac
	;;
    sles)
	sudo zypper -n update
	sudo zypper -n install gcc gcc-c++ gcc-fortran \
	     autoconf automake libtool flex make gdb \
	     python-boto python-boto3 python-mock
	labels="${labels} linux sles_${VERSION_ID}"
	case $VERSION_ID in
	    12.2)
		# gcc5 == 5.3.1
		# gcc6 == 6.2.1
		sudo zypper -n install gcc48 gcc48-c++ gcc48-fortran \
		     gcc5 gcc5-c++ gcc5-fortran \
		     gcc6 gcc6-c++ gcc6-fortran
		labels="${labels} gcc48 gcc5 gcc6"
		;;
	    *)
		echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
		exit 1
		;;
	esac
	# No java shipped in SLES by default...
	jre_file=jre-8u121-linux-x64.rpm
	aws s3 cp s3://ompi-jenkins-config/${jre_file} /tmp/${jre_file}
	sudo rpm -i /tmp/${jre_file}
	;;
    FreeBSD)
	su -m root -c 'pkg install -y sudo'
	if ! grep -q '^%wheel ALL=(ALL) NOPASSWD: ALL' /usr/local/etc/sudoers ; then
	    echo "--> Updating sudoers"
	    su -m root -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /usr/local/etc/sudoers'
	else
	    echo "--> Skipping sudoers update"
	fi
	sudo pkg install -y openjdk8 autoconf automake libtool gcc wget curl git
	if ! grep -q '/dev/fd' /etc/fstab ; then
	    echo "Adding /dev/fd entry to /etc/fstab"
	    sudo sh -c 'echo "fdesc /dev/fd fdescfs rw 0 0" >> /etc/fstab'
	fi
	if ! grep -q '/proc' /etc/fstab ; then
	    echo "Adding /proc entry to /etc/fstab"
	    sudo sh -c 'echo "proc /proc procfs rw 0 0 " >> /etc/fstab'
	fi
	;;
    *)
	echo "ERROR: Unkonwn platform ${PLATFORM_ID}"
	exit 1
esac

#
# Run the most recent version of the agent script to pre-fetch the
# required software packages.
#
curl https://raw.githubusercontent.com/open-mpi/ompi-scripts/master/jenkins/agent-setup-script.sh -o agent-setup-script.sh
/bin/sh ./agent-setup-script.sh
rm ./agent-setup-script.sh

if test $run_test != 0; then
    # for these tests, fail the script if a test fails
    set -e
    echo "==> Running Compile test"
    cd
    git clone https://github.com/open-mpi/ompi.git
    cd ompi
    ./autogen.pl
    ./configure --prefix=$HOME/install
    make -j 4 all
    make check
    make install
    cd $HOME
    rm -rf ${HOME}/ompi ${HOME}/install
    echo "==> SUCCESS!  Open MPI compiled!"
fi

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
