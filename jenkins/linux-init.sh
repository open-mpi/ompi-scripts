#!/bin/bash
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Script to install all the bits to run Open MPI build tests on
# various Linux AMIs in EC2.  The idea is that this script is pulled
# down and run at instance launch for Linux jenkins workers using a
# script like the following as the user-data:
#
#  #!/bin/bash
#  curl https://raw.github.com/open-mpi/ompi-scripts/master/jenkins/linux-init.sh -i /tmp/linux-init.sh
#  /bin/bash /tmp/linux-init.sh
#

eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"

echo $PLATFORM_ID
echo $VERSION_ID

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

case $PLATFORM_ID in
    rhel)
	# RHEL's default repos only include the "base" compiler
	# version, so don't worry about script version
	# differentiation.
	# gcc = 4.8.5
	sudo service sshd stop
	sudo yum -y update
	sudo yum -y group install "Development Tools"
	sudo yum -y install libevent hwloc hwloc-libs
	sudo yum -y install java
	sudo service sshd start
	;;
    amzn)
	sudo service sshd stop
	sudo yum -y update
	sudo yum -y groupinstall "Development Tools"
	sudo yum -y install libevent-devel
	case $VERSION_ID in
	    2016.09|2017.03)
		# clang == 3.6.2
		sudo yum -y install gcc44 gcc44-c++ gcc44-gfortran \
		     gcc48 gcc48-c++ gcc48-gfortran clang
		sudo yum -y groupinstall "Java Development"
		;;
	esac
	sudo service sshd start
	;;
    ubuntu)
	sudo service ssh stop
	sudo apt-get update
	sudo apt-get -y upgrade
	sudo apt-get -y install build-essential gfortran \
	     autoconf automake libtool flex hwloc libhwloc-dev git
	case $VERSION_ID in
	    14.04)
		sudo apt-get -y install gcc-4.4 g++-4.4 gfortran-4.4 \
		     gcc-4.6 g++-4.6 gfortran-4.6 \
		     gcc-4.7 g++-4.7 gfortran-4.7 \
		     gcc-4.8 g++-4.8 gfortran-4.8 \
		     clang-3.6 clang-3.7 clang-3.8
		;;
	    16.04)
		sudo apt-get -y install gcc-4.7 g++-4.7 gfortran-4.7 \
		     gcc-4.8 g++-4.8 gfortran-4.8 \
		     gcc-4.9 g++-4.9 gfortran-4.9 \
		     clang-3.6 clang-3.7 clang-3.8
		;;
	esac
	sudo apt-get -y install default-jre
	sudo service ssh start
	;;
    sles)
	sudo service sshd stop
	sudo zypper -n install gcc gcc-c++ gcc-fortran \
	     autoconf automake libtool flex make
	case $VERSION_ID in
	    12.2)
		# gcc5 == 5.3.1
		# gcc6 == 6.2.1
		sudo zypper -n install gcc48 gcc48-c++ gcc48-fortran \
		     gcc5 gcc5-c++ gcc5-fortran \
		     gcc6 gcc6-c++ gcc6-fortran

		;;
	esac
	# No java shipped in SLES by default...
	jre_file=jre-8u121-linux-x64.rpm
	aws s3 cp s3://ompi-jenkins-config/${jre_file} /tmp/${jre_file}
	rpm -i /tmp/${jre_file}
	sudo service sshd start
	;;
    *)
	echo "ERROR: Unkonwn platform ${PLATFORM_ID}"
	exit 1
esac

if test $run_test != 0; then
    # for these tests, fail the script if a test fails
    set -e
    echo "Running Compile test"
    cd
    git clone https://github.com/open-mpi/ompi.git
    cd ompi
    ./autogen.pl
    ./configure --prefix=$HOME/install
    make -j 4 all
    make check
    make install
    echo "SUCCESS!  Open MPI compiled!"
fi
