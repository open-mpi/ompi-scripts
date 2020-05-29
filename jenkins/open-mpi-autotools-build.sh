#!/bin/bash
#
# Install (building if necessary) the autotools packages necessary for
# building a particular version of Open MPI.
#
# We build and save artifacts outside of the Jenkins workspace, which
# is a little odd, but allows us to persist builds across jobs (and
# avoid any job-specific naming problems in paths).  We will write the
# autotools installations into $HOME/autotools-setup/ unless otherwise
# instructed.  If JENKINS_AGENT_HOME is set, we will use that instead
# of $HOME.
#
# In addition to building and saving artifacts (including to S3 for
# EC2 instances), this script can be called for every job to create a
# simlink from the built autotools into $WORKSPACE/autotools-install.
#
# usage: ./open-mpi-autotools-build.sh <ompi tree>
#

# be lazy...
set -e

ompi_tree=$1
dist_script=${ompi_tree}/contrib/dist/make_dist_tarball
s3_path="s3://ompi-jenkins-config/autotools-builds"

if test ! -n "${JENKINS_AGENT_HOME}" ; then
    JENKINS_AGENT_HOME=${HOME}
fi
autotools_root=${JENKINS_AGENT_HOME}/autotools-builds
mkdir -p "${autotools_root}"

if test ! -r ${dist_script} ; then
    echo "Can not read ${dist_script}.  Aborting."
    exit 1
fi

os=`uname -s`
if test "${os}" = "Linux"; then
    eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
    eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"
else
    PLATFORM_ID=`uname -s`
    VERSION_ID=`uname -r`
fi

if `echo ${NODE_NAME} | grep -q '^EC2'` ; then
    IS_EC2="yes"
else
    IS_EC2="no"
fi

echo "==> Platform: $PLATFORM_ID"
echo "==> Version:  $VERSION_ID"
echo "==> EC2: $IS_EC2"

for pkg in AC AM LT M4 FLEX; do
    eval "${pkg}_VERSION=`sed -ne \"s/^${pkg}_TARGET_VERSION=\(.*\)/\1/p\" ${dist_script}`"
done

version_string="${AC_VERSION}-${AM_VERSION}-${LT_VERSION}-${M4_VERSION}-${FLEX_VERSION}"
tarball_name="autotools-${PLATFORM_ID}_${VERSION_ID}-${version_string}.tar.gz"
autotools_install_short="autotools-install-${version_string}"
autotools_install="${autotools_root}/${autotools_install_short}"
echo "==> Version string: ${version_string}"

cd ${autotools_root}

if test ${IS_EC2} = "yes" && test ! -d ${autotools_install} ; then
    if aws s3 cp ${s3_path}/${tarball_name} . >& /dev/null ; then
        echo "==> Downloaded build from S3"
        tar xf ${tarball_name}
        rm ${tarball_name}
    fi
fi

if test ! -d ${autotools_install} ; then
    echo "==> No build found ; building from scratch"

    autotools_srcdir="${autotools_root}/autotools-src.$$"

    mkdir -p ${autotools_srcdir}
    cd ${autotools_srcdir}

    export PATH=${autotools_install/bin}:${PATH}
    export LD_LIBRARY_PATH=${autotools_install}/lib:${LD_LIBRARY_PATH}

    curl -fO http://ftp.gnu.org/gnu/autoconf/autoconf-${AC_VERSION}.tar.gz
    tar xf autoconf-${AC_VERSION}.tar.gz
    (cd autoconf-${AC_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fO http://ftp.gnu.org/gnu/automake/automake-${AM_VERSION}.tar.gz
    tar xf automake-${AM_VERSION}.tar.gz
    (cd automake-${AM_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fO http://ftp.gnu.org/gnu/libtool/libtool-${LT_VERSION}.tar.gz
    tar xf libtool-${LT_VERSION}.tar.gz
    (cd libtool-${LT_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fO http://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.gz
    tar xf m4-${M4_VERSION}.tar.gz
    (cd m4-${M4_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    # When flex moved from ftp.gnu.org to sourceforge to GitHub for
    # downloads, they dropped all the archive versions.  Including the
    # one we say we require (sigh).  So we archive that tarball
    # (stolen from a distro archive repository) for use.  Hopefully,
    # one day, we will be able to update :).
    flex_tarball="flex-${FLEX_VERSION}.tar.gz"
    if ! curl -fO https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/${flex_tarball}  ; then
        curl -fO https://download.open-mpi.org/archive/flex/${flex_tarball}
    fi
    tar xf ${flex_tarball}
    (cd flex-${FLEX_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    cd  ${autotools_root}

    # autotools_srcdir was unique to this process, so this is safe
    # even in a concurrent Jenkins jobs situation.
    rm -rf ${autotools_srcdir}

    if test "$IS_EC2" = "yes" ; then
        echo "==> Archiving build to S3"
        tar czf ${tarball_name} ${autotools_install_short}
        aws s3 cp ${tarball_name} ${s3_path}/${tarball_name}
        rm ${tarball_name}
    fi
fi

echo "==> Symlinking ${autotools_install} to ${WORKSPACE}/autotools-install"
ln -s ${autotools_install} ${WORKSPACE}/autotools-install
