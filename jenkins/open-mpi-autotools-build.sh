#!/bin/bash
#
# Install (building if necessary) the autotools packages necessary for
# building a particular version of Open MPI.  This isn't used as part
# of the Pull Request / commit builders (they use the default
# autotools for that platform), but is used by the nightly / release
# builder pipelines.
#
# usage: ./open-mpi-autotools-build.sh <ompi tree>
#

# be lazy...
set -e

ompi_tree=$1
dist_script=${ompi_tree}/contrib/dist/make_dist_tarball
topdir=`pwd`

if test ! -r ${dist_script} ; then
    echo "Can not read ${dist_script}.  Aborting."
    exit 1
fi

for pkg in AC AM LT M4 ; do
    eval "${pkg}_VERSION=`sed -ne \"s/^${pkg}_TARGET_VERSION=\(.*\)/\1/p\" ${dist_script}`"
done

version_string="${AC_VERSION}-${AM_VERSION}-${LT_VERSION}-${M4_VERSION}"
tarball="autotools-${version_string}.tar.gz"
echo "version string: ${version_string}"

if ! aws s3 cp s3://ompi-jenkins-config/${tarball} . >& /dev/null ; then
    echo "No tarball found; building from scratch"

    mkdir -p ${topdir}/autotools-src
    cd ${topdir}/autotools-src

    export PATH=${topdir}/autotools-install/bin:${PATH}
    export LD_LIBRARY_PATH=${topdir}/autotools-install/lib:${LD_LIBRARY_PATH}

    curl -O http://ftp.gnu.org/gnu/autoconf/autoconf-${AC_VERSION}.tar.gz
    tar xf autoconf-${AC_VERSION}.tar.gz
    (cd autoconf-${AC_VERSION} ; ./configure --prefix=${topdir}/autotools-install ; make install)

    curl -O http://ftp.gnu.org/gnu/automake/automake-${AM_VERSION}.tar.gz
    tar xf automake-${AM_VERSION}.tar.gz
    (cd automake-${AM_VERSION} ; ./configure --prefix=${topdir}/autotools-install ; make install)

    curl -O http://ftp.gnu.org/gnu/libtool/libtool-${LT_VERSION}.tar.gz
    tar xf libtool-${LT_VERSION}.tar.gz
    (cd libtool-${LT_VERSION} ; ./configure --prefix=${topdir}/autotools-install ; make install)

    curl -O http://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.gz
    tar xf m4-${M4_VERSION}.tar.gz
    (cd m4-${M4_VERSION} ; ./configure --prefix=${topdir}/autotools-install ; make install)

    cd  ${topdir}/
    tar czf ${tarball} autotools-install
    aws s3 cp ${tarball} s3://ompi-jenkins-config/${tarball}
else
    tar xf ${tarball}
fi
