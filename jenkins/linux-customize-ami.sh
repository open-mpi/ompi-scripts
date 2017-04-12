#!/bin/bash
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Script to take a normal Linux AMI and make it OMPI Jenkins-ified.
# This is still a bit more manual than it could be, but given how
# infrequent AMIs are reved, this is plan B (Plan A was to do all this
# at instance start, which made Jenkins unhappy due to slow startup
# times).  General instructions:
#
# 1) launch normal AMI (t2.micros are great for keeping costs low in
#    building AMIs)
# 2) run the follwowing in the instance:
#    curl https://raw.github.com/open-mpi/ompi-scripts/master/jenkins/linux-customize-ami.sh -i /tmp/linux-customize-ami.sh
#    bash /tmp/linux-customize-ami.sh
#    sudo shutdown -h now
# 3) From EC2 Console / API, run 'Create Image'
#    3.1) AMI Name should be similar to Ubuntu 16.04
#    3.2) Description should include the AMI used in step 1
# 4) Terminate instance
# 5) Create new Jenkins worker configuration with new AMI id.
#

labels="ec2"

eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"

echo "==> PLatform: $PLATFORM_ID"
echo "==> Version:  $VERSION_ID"

OPTIND=1         # Reset in case getopts has been used previously in the shell.
run_test=0       # -t runs an ompi build test; useful for testing new AMIs

while getopts "h?t" opt; do
    case "$opt" in
    h|\?)
        echo "usage: linux-init.sh [-t]"
        exit 1
        ;;
    t)  run_test=1
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
	sudo yum -y install libevent hwloc hwloc-libs java
	labels="${labels} linux rhel ${VERSION_ID} gcc48"
	;;
    amzn)
	sudo yum -y update
	sudo yum -y groupinstall "Development Tools"
	sudo yum -y install libevent-devel
	labels="${labels} linux amazon_linux_${VERSION_ID}"
	case $VERSION_ID in
	    2016.09|2017.03)
		# clang == 3.6.2
		sudo yum -y install gcc44 gcc44-c++ gcc44-gfortran \
		     gcc48 gcc48-c++ gcc48-gfortran clang
		sudo yum -y groupinstall "Java Development"
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
	     default-jre
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
		labels="${labels} gcc47 gcc48 gcc49 clang36 clang37 clang38"
		;;
	    *)
		echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
		exit 1
		;;
	esac
	;;
    sles)
	sudo zypper -n install gcc gcc-c++ gcc-fortran \
	     autoconf automake libtool flex make
	labels="${labels} linux sles_${VERSION_ID}"
	case $VERSION_ID in
	    12.2)
		# gcc5 == 5.3.1
		# gcc6 == 6.2.1
		sudo zypper -n install gcc48 gcc48-c++ gcc48-fortran \
		     gcc5 gcc5-c++ gcc5-fortran \
		     gcc6 gcc6-c++ gcc6-fortran
		labels="${labels} gcc48 gcc53 gcc62"
		;;
	    *)
		echo "ERROR: Unknown version ${PLATFORM_ID} ${VERSION_ID}"
		exit 1
		;;
	esac
	# No java shipped in SLES by default...
	jre_file=jre-8u121-linux-x64.rpm
	aws s3 cp s3://ompi-jenkins-config/${jre_file} /tmp/${jre_file}
	rpm -i /tmp/${jre_file}
	;;
    *)
	echo "ERROR: Unkonwn platform ${PLATFORM_ID}"
	exit 1
esac

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
    echo "==> SUCCESS!  Open MPI compiled!"
fi

echo "==> Cleaning instance"
rm -rf ${HOME}/* ${HOME}/.ssh ${HOME}/.history ${HOME}/.bash_history ${HOME}/.sudo_as_admin_successful ${HOME}/.cache
sudo rm -rf /var/log/*
sudo rm -f /etc/ssh/ssh_host*
sudo rm -rf /root/* ~root/.ssh ~root/.history ~root/.bash_history

echo "==> All done!"
echo "Recommended labels: ${labels}"

# cleanup phase
