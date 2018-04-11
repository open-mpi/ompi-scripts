#!/bin/bash
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Build autotools dependencies needed for various software builds.
# Run after an agent starts, but before the host is marked as
# available.
#

SCRIPT_ROOT=`pwd`
SOFTWARE_ROOT="${SCRIPT_ROOT}/software"
SOURCE_ROOT="${SOFTWARE_ROOT}/source"

set -e

install_autotools ()
{
    local autoconf=$1
    local automake=$2
    local libtool=$3

    local old_PATH="$PATH}"
    export PATH="${4}/bin:${PATH}"

    if test -f ${4}/bin/autoconf -a -f ${4}/bin/automake -a -f ${4}/bin/libtool ; then
	local found=1
	# see if we can skip building
	if ! autoconf --version | grep ${autoconf}; then
	    found=0
	fi
	if ! automake --version | grep ${automake}; then
	    found=0
	fi
	if ! libtool --version | grep ${libtool}; then
	    found=0
	fi
	if test ${found} -eq 1 ; then
	    echo "Autotools already available"
	    return 0
	fi
    fi

    # ok, so we actually need to build
    mkdir -p ${SOURCE_ROOT}
    cd ${SOURCE_ROOT}

    curl http://ftp.gnu.org/gnu/autoconf/autoconf-${autoconf}.tar.gz -o autoconf-${autoconf}.tar.gz
    curl http://ftp.gnu.org/gnu/automake/automake-${automake}.tar.gz -o automake-${automake}.tar.gz
    curl http://ftp.gnu.org/gnu/libtool/libtool-${libtool}.tar.gz -o libtool-${libtool}.tar.gz

    tar xf autoconf-${autoconf}.tar.gz
    tar xf automake-${automake}.tar.gz
    tar xf libtool-${libtool}.tar.gz

    cd autoconf-${autoconf}
    ./configure --prefix=$4 && make install
    cd ${SOURCE_ROOT}

    cd automake-${automake}
    ./configure --prefix=$4 && make install
    cd ${SOURCE_ROOT}

    cd libtool-${libtool}
    ./configure --prefix=$4 && make install
    cd ${SOURCE_ROOT}

    export PATH="${old_PATH}"
}

install_autotools 2.69 1.16.1 2.4.6 ${SOFTWARE_ROOT}/autotools-2.69-1.16.1-2.4.6
