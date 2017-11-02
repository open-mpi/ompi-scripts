#!/bin/sh

# abort on error
set -e

# sigh; this probably isn't the most user friendly thing I've ever done...
for var in "$@"; do
    eval $@
done

#
# Start by figuring out what we are...
#
os=`uname -s`
if test "${os}" = "Linux"; then
    eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
    eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"
else
    PLATFORM_ID=`uname -s`
    VERSION_ID=`uname -r`
fi

echo "--> platform: $PLATFORM_ID"
echo "--> version: $VERSION_ID"

AUTOGEN_ARGS=
CONFIGURE_ARGS=
MAKE_ARGS=
MAKE_J="-j 8"
PREFIX="${WORKSPACE}/install"

#
# If they exist, use installed autotools
#
if test -n "${JENKINS_AGENT_HOME}" ; then
    base_dir=${JENKINS_AGENT_HOME}
else
    base_dir=${HOME}
fi
AUTOTOOLS=${base_dir}/software/autotools-2.69-1.15.0-2.4.6/bin
if test -d ${AUTOTOOLS} ; then
    export PATH=${AUTOTOOLS}:${PATH}
fi

#
# See if builder provided a compiler we should use, and translate it
# to CONFIGURE_ARGS
#
case ${PLATFORM_ID} in
    rhel)
	case "$Compiler" in
	    gcc48|"")
		echo "--> Using default compilers"
		;;
	    *)
		echo "Unsupported compiler ${Compiler}.  Aborting"
		exit 1
		;;
	esac
	;;
    amzn)
	case "$Compiler" in
	    "")
		echo "--> Using default compilers"
		;;
	    gcc44)
		CONFIGURE_ARGS="CC=gcc44 CXX=g++44 FC=gfortran44"
		;;
	    gcc48)
		CONFIGURE_ARGS="CC=gcc48 CXX=g++48 FC=gfortran48"
		;;
	    clang36)
		CONFIGURE_ARGS="CC=clang CXX=clang++ --disable-mpi-fortran"
		;;
	    *)
		echo "Unsupported compiler ${Compiler}.  Aborting"
		exit 1
		;;
	esac
	;;
    ubuntu)
	case "$Compiler" in
	    "")
		echo "--> Using default compilers"
		;;
	    gcc47)
		CONFIGURE_ARGS="CC=gcc-4.7 CXX=g++-4.7 FC=gfortran-4.7"
		;;
	    gcc48)
		CONFIGURE_ARGS="CC=gcc-4.8 CXX=g++-4.8 FC=gfortran-4.8"
		;;
	    gcc49)
		CONFIGURE_ARGS="CC=gcc-4.9 CXX=g++-4.9 FC=gfortran-4.9"
		;;
	    gcc5)
		CONFIGURE_ARGS="CC=gcc-5 CXX=g++-5 FC=gfortran-5"
		;;
	    clang36)
		CONFIGURE_ARGS="CC=clang-3.6 CXX=clang++-3.6 --disable-mpi-fortran"
		;;
	    clang37)
		CONFIGURE_ARGS="CC=clang-3.7 CXX=clang++-3.7 --disable-mpi-fortran"
		;;
	    clang38)
		CONFIGURE_ARGS="CC=clang-3.8 CXX=clang++-3.8 --disable-mpi-fortran"
		;;
	    *)
		echo "Unsupported compiler ${Compiler}.  Aborting"
		exit 1
		;;
	esac
	;;
    sles)
	case "$Compiler" in
	    "")
		echo "--> Using default compilers"
		;;
	    gcc48)
		CONFIGURE_ARGS="CC=gcc-48 CXX=g++-48 FC=gfortran-48"
		;;
	    gcc5)
		CONFIGURE_ARGS="CC=gcc-5 CXX=g++-5 FC=gfortran-5"
		;;
	    gcc6)
		CONFIGURE_ARGS="CC=gcc-6 CXX=g++-6 FC=gfortran-6"
		;;
	    *)
		echo "Unsupported compiler ${Compiler}.  Aborting"
		exit 1
		;;
	esac
	;;
    FreeBSD)
	CONFIGURE_ARGS="LDFLAGS=-Wl,-rpath,/usr/local/lib/gcc5 --with-wrapper-ldflags=-Wl,-rpath,/usr/local/lib/gcc5"
	;;
esac

echo "--> Compiler setup: $CONFIGURE_ARGS"

#
# Add any Autogen or Configure arguments provided by the builder job
#
if test "$AUTOGEN_OPTIONS" != ""; then
    # special case, to work around the fact that Open MPI can't build
    # when there's a space in the build path name (sigh)
    if test "$AUTOGEN_OPTIONS" = "--no-orte"; then
	AUTOGEN_OPTIONS="--no-orte --no-ompi"
    fi
    echo "--> Adding autogen arguments: $AUTOGEN_OPTIONS"
    AUTOGEN_ARGS="${AUTOGEN_ARGS} ${AUTOGEN_OPTIONS}"
fi

if test "$CONFIGURE_OPTIONS" != ""; then
    echo "--> Adding configure arguments: $CONFIGURE_OPTIONS"
    CONFIGURE_ARGS="${CONFIGURE_ARGS} ${CONFIGURE_OPTIONS}"
fi

#
# Build.
#
cd "${WORKSPACE}/src"

sha1=`git rev-parse HEAD`
echo "--> Building commit ${sha1}"

if test -f autogen.pl; then
    echo "--> running ./autogen.pl ${AUTOGEN_ARGS}"
    ./autogen.pl ${AUTOGEN_ARGS}
else
    if test "${AUTOGEN_ARGS}" != ""; then
	echo "--> Being a coward and not running with special autogen arguments and autogen.sh"
	exit 1
    else
	echo "--> running ./atogen.sh"
	./autogen.sh
    fi
fi

echo "--> running ./configure --prefix=\"${PREFIX}\" ${CONFIGURE_ARGS}"
./configure --prefix="${PREFIX}" ${CONFIGURE_ARGS}

# shortcut for the distcheck case, as it won't run any tests beyond
# the build-in make check tests.
if test "${MAKE_DISTCHECK}" != ""; then
    echo "--> running make ${MAKE_ARGS} distcheck"
    make ${MAKE_ARGS} distcheck
    exit 0
fi

echo "--> running make ${MAKE_J} ${MAKE_ARGS} all"
make ${MAKE_J} ${MAKE_ARGS} all
echo "--> running make check"
make ${MAKE_ARGS} check
echo "--> running make install"
make ${MAKE_ARGS} install

export PATH="${PREFIX}/bin":${PATH}

case "$AUTOGEN_OPTIONS" in
    *--no-ompi*)
	echo "--> Skipping MPI tests due to --no-ompi"
	exit 0
	;;
esac

echo "--> running ompi_info"
ompi_info

echo "--> running make all in examples"
cd "${WORKSPACE}/src/examples"
make ${MAKE_ARGS} all
cd ..

# it's hard to determine what the failure was and there's no printing
# of error code with set -e, so for the tests, we do per-command
# checking...
set +e

run_example() {
    example=`basename ${2}`
    echo "--> Running example: $example"
    ${1} ${2}
    ret=$?
    if test ${ret} -ne 0 ; then
	echo "Example failed: ${ret}"
	echo "Command was: ${1} ${2}"
	exit ${ret}
    fi
}

if test "${MPIRUN_MODE}" != "none"; then
    echo "--> running examples"
    echo "localhost cpu=2" > "${WORKSPACE}/hostfile"
    # Note: using perl here because figuring out a portable sed regexp
    # proved to be a little challenging.
    mpirun_version=`"${WORKSPACE}/install/bin/mpirun" --version | perl -wnE 'say $1 if /mpirun [^\d]*(\d+.\d+)/'`
    echo "--> mpirun version: ${mpirun_version}"
    case ${mpirun_version} in
	1.*|2.0*)
	    exec="timeout -s SIGSEGV 3m mpirun -hostfile ${WORKSPACE}/hostfile -np 2 "
	    ;;
	*)
	    exec="timeout -s SIGSEGV 4m mpirun --get-stack-traces --timeout 180 -hostfile ${WORKSPACE}/hostfile -np 2 "
	    ;;
    esac
    run_example "${exec}" ./examples/hello_c
    run_example "${exec}" ./examples/ring_c
    run_example "${exec}" ./examples/connectivity_c
    if ompi_info --parsable | grep -q bindings:cxx:yes >/dev/null; then
        echo "--> running C++ examples"
        run_example "${exec}" ./examples/hello_cxx
        run_example "${exec}" ./examples/ring_cxx
    else
        echo "--> skipping C++ examples"
    fi
    if ompi_info --parsable | grep -q bindings:mpif.h:yes >/dev/null; then
        echo "--> running mpif examples"
        run_example "${exec}" ./examples/hello_mpifh
        run_example "${exec}" ./examples/ring_mpifh
    else
        echo "--> skipping mpif examples"
    fi
    if ompi_info --parsable | egrep -q bindings:use_mpi:\"\?yes >/dev/null; then
        echo "--> running usempi examples"
        run_example "${exec}" ./examples/hello_usempi
        run_example "${exec}" ./examples/ring_usempi
    else
        echo "--> skipping usempi examples"
    fi
    if ompi_info --parsable | grep -q bindings:use_mpi_f08:yes >/dev/null; then
        echo "--> running usempif08 examples"
        run_example "${exec}" ./examples/hello_usempif08
        run_example "${exec}" ./examples/ring_usempif08
    else
        echo "--> skipping usempif08 examples"
    fi
else
    echo "--> Skipping examples (MPIRUN_MODE = none)"
fi

echo "--> All done!"
