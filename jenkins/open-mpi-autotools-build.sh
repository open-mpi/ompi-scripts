#!/bin/bash
#
# Install (building if necessary) the autotools packages necessary for
# building a particular package.
#
# We build and save artifacts outside of the Jenkins workspace, which
# is a little odd, but allows us to persist builds across jobs (and
# avoid any job-specific naming problems in paths).
#
# In addition to building and saving artifacts (including to S3 for
# EC2 instances), this script can be called for every job to create a
# simlink from the built autotools into <target>
#
# usage: ./open-mpi-autotools-build.sh
#            [-z <dist_script_for_versions]
#            [-r <autotools_root>
#            [-c <autoconf_version] [-m <automake version]
#            [-l <libtool_version] [-n <m4 version>]
#            [-f <flex_version>]

dist_script=
debug=0
autotools_root=
target_link=
dist_script_path="/dev/null"
patch_file_directory=
s3_build_path="s3://ompi-jenkins-config/autotools-builds"
autotools_scratch_dir=

usage() {
     echo "Usage: $0 -r <DIR> -t <LINK> [OPTION]..."
     echo "Build autotools necessary for OMPI-related project builds"
     echo ""
     echo "Mandatory Arguments:"
     echo "  -r DIR      Leave build artifacts in DIR and use DIR for building"
     echo "              temporary artifacts.  On non-ephemeral instances, DIR"
     echo "              should be outside of a Jenkins workspace to avoid"
     echo "              unnecessary rebuilding of autotools."
     echo "  -t LINK     Create symlnk LINK to the autotools build requested."
     echo "              Unlike -r, this option frequently is in a Jenkins"
     echo "              workspace, as it is ephemeral to a build."
     echo ""
     echo "Optional Arguments"
     echo "  -d          If specified, enable debug output."
     echo "  -p DIR      Directory to search for patch files.  If a patch file"
     echo "              named <package_name>-<version>.patch is found in DIR"
     echo "              it will be applied to <package_name> before building."
     echo "  -z FILE     Pull required Autotools versions from an Open MPI like"
     echo "              dist script.  This option assumes certain variables are"
     echo "              set in FILE.  This option is exclusive with -c, -m, -l,"
     echo "              -n, and -f options."
     echo "  -{c,m,l,n,f} VERSION  Use VERSION as the required version string for"
     echo "              Autoconf, Automake, Libtool, M4, and Flex (respectively)."
     echo "              If one of these arguments is set, all must be set.  Either"
     echo "              these arguments or -z must be specified."
     echo "  -h          Print this usage message and exit."
}

debug_print() {
    if [[ $debug -ne 0 ]] ; then
        echo $1
    fi
}

clean_scratch_dir() {
    if [[ -n "$autotools_scratch_dir" ]] ; then
        echo "cleaning $autotools_scratch_dir"
        rm -rf "$autotools_scratch_dir"
    fi
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi
while getopts ":dz:r:t:c:m:l:n:f:p:h" arg; do
    case $arg in
        d)
            debug=1
            ;;
        p)
            patch_file_directory=${OPTARG}
            patch_file_directory=`realpath ${patch_file_directory}`
            ;;
        r)
            autotools_root=${OPTARG}
            ;;
        t)
            target_link=${OPTARG}
            ;;
        z)
            dist_script=${OPTARG}
            ;;
        c)
            AC_VERSION=${OPTARG}
            ;;
        m)
            AM_VERSION=${OPTARG}
            ;;
        l)
            LT_VERSION=${OPTARG}
            ;;
        n)
            M4_VERSION=${OPTARG}
            ;;
        f)
            FLEX_VERSION=${OPTARG}
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# command line checking
if [[ -z "${target_link}" ]] ; then
    echo "-t <target_link> is a required option, but is not set."
    exit 1
fi
if [[ -z "${autotools_root}" ]] ; then
    echo "-r <build root> is a required option, but is not set."
    exit 1
fi

trap clean_scratch_dir EXIT

mkdir -p "${autotools_root}"
if [[ $? -ne 0 ]] ; then
     echo "Could not create directory ${autotools_root}.  Cannot continue."
     exit 2
fi

# If a dist script was specified, grab the version files from there.
# Otherwise, expect all the versions to be explicitly specified.
if [[ -n "${dist_script}" ]] ; then
    debug_print "Finding versions from dist script ${dist_script}"
    if [[ ! -r ${dist_script} ]] ; then
        echo "Cannot read ${dist_script}.  Aborting."
        exit 1
    fi

    for pkg in AC AM LT M4 FLEX ; do
        eval "${pkg}_VERSION=`sed -ne \"s/^${pkg}_TARGET_VERSION=\(.*\)/\1/p\" ${dist_script}`"
	eval "var=${pkg}_VERSION"
	if test -z "${var}" ; then
            echo "${pkg_VERSION} not set in ${dist_script}"
            exit 2
        fi
    done
else
    for pkg in AC AM LT M4 FLEX ; do
        eval "var=\"\$${pkg}_VERSION\""
        if test -z "${var}" ; then
            echo "${pkg}_VERSION not set on command line"
            exit 1
        fi
    done
fi
for pkg in AC AM LT M4 FLEX ; do
    eval "var=\"\$${pkg}_VERSION\""
    debug_print "${pkg}_VERSION: $var"
done

os=`uname -s`
if test "${os}" = "Linux"; then
    eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
    eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"
else
    PLATFORM_ID=`uname -s`
    VERSION_ID=`uname -r`
fi

if `echo ${NODE_NAME} | grep -q '^EC2'` ; then
    IS_EC2_JENKINS="yes"
else
    IS_EC2_JENKINS="no"
fi

debug_print "Platform: $PLATFORM_ID"
debug_print "Version:  $VERSION_ID"
debug_print "EC2 Jenkins Worker: $IS_EC2_JENKINS"

version_string="${AC_VERSION}-${AM_VERSION}-${LT_VERSION}-${M4_VERSION}-${FLEX_VERSION}"
tarball_name="autotools-${PLATFORM_ID}_${VERSION_ID}-${version_string}.tar.gz"
autotools_install_short="autotools-install-${version_string}"
autotools_install="${autotools_root}/${autotools_install_short}"
debug_print "Version string: ${version_string}"

cd ${autotools_root}

if [[ ${IS_EC2_JENKINS} = "yes" && ! -d ${autotools_install} ]] ; then
    debug_print "Attempting to download cached build ${s3_build_path}/${tarball_name}"
    if aws s3 cp ${s3_build_path}/${tarball_name} . >& /dev/null ; then
        debug_print "Downloaded build from S3"
        tar xf ${tarball_name}
        rm ${tarball_name}
    fi
fi

if [[ ! -d ${autotools_install} ]] ; then
    debug_print "==> No build found ; building from scratch"

    autotools_scratch_dir=$(mktemp -d ${autotools_root}/autotools-src.XXXXXXXX)
    cd ${autotools_scratch_dir}
    debug_print "build dir: $autotools_scratch_dir"

    export PATH=${autotools_install/bin}:${PATH}
    export LD_LIBRARY_PATH=${autotools_install}/lib:${LD_LIBRARY_PATH}

    build_cleanup() {
        echo "Building autotools failed.  Cleaning ${autotools_install}."
        if [[ -d "${autotools_install}" ]] ; then
            rm -rf "${autotools_install}"
        fi
        exit 5
    }
    trap build_cleanup ERR

    # TODO: Error checking!
    curl -fLO http://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.gz
    tar xf m4-${M4_VERSION}.tar.gz
    patch_file="${patch_file_directory}/m4-${M4_VERSION}.patch"
    if [[ -r ${patch_file} ]] ; then
        debug_print "Appying patch m4-${M4_VERSION}.patch"
        (cd m4-${M4_VERSION} ; patch -p 1 < ${patch_file})
    else
        debug_print "patch m4-${M4_VERSION}.patch not found."
    fi
    (cd m4-${M4_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fLO http://ftp.gnu.org/gnu/autoconf/autoconf-${AC_VERSION}.tar.gz
    tar xf autoconf-${AC_VERSION}.tar.gz
    patch_file="${patch_file_directory}/autoconf-${AC_VERSION}.patch"
    if [[ -r ${patch_file} ]] ; then
        debug_print "Appying patch autoconf-${AC_VERSION}.patch"
        (cd autoconf-${AC_VERSION} ; patch -p 1 < ${patch_file})
    else
        debug_print "patch autoconf-${AC_VERSION}.patch not found."
    fi
    (cd autoconf-${AC_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fLO http://ftp.gnu.org/gnu/automake/automake-${AM_VERSION}.tar.gz
    tar xf automake-${AM_VERSION}.tar.gz
    patch_file="${patch_file_directory}/automake-${AM_VERSION}.patch"
    if [[ -r ${patch_file} ]] ; then
        debug_print "Appying patch automake-${AM_VERSION}.patch"
        (cd automake-${AM_VERSION} ; patch -p 1 < ${patch_file})
    else
        debug_print "patch automake-${AM_VERSION}.patch not found."
    fi
    (cd automake-${AM_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    curl -fLO http://ftp.gnu.org/gnu/libtool/libtool-${LT_VERSION}.tar.gz
    tar xf libtool-${LT_VERSION}.tar.gz
    patch_file="${patch_file_directory}/libtool-${LT_VERSION}.patch"
    if [[ -r ${patch_file} ]] ; then
        debug_print "Appying patch libtool-${LT_VERSION}.patch"
        (cd libtool-${LT_VERSION} ; patch -p 1 < ${patch_file})
    else
        debug_print "patch libtool-${LT_VERSION}.patch not found."
    fi
    (cd libtool-${LT_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    # When flex moved from ftp.gnu.org to sourceforge to GitHub for
    # downloads, they dropped all the archive versions.  Including the
    # one we say we require (sigh).  So we archive that tarball
    # (stolen from a distro archive repository) for use.  Hopefully,
    # one day, we will be able to update :).
    flex_tarball="flex-${FLEX_VERSION}.tar.gz"
    if ! curl -fLO https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/${flex_tarball}  ; then
        curl -fLO https://download.open-mpi.org/archive/flex/${flex_tarball}
    fi
    tar xf ${flex_tarball}
    patch_file="${patch_file_directory}/flex-${FLEX_VERSION}.patch"
    if [[ -r ${patch_file} ]] ; then
        debug_print "Appying patch flex-${FLEX_VERSION}.patch"
        (cd flex-${FLEX_VERSION} ; patch -p 1 < ${patch_file})
    else
        debug_print "patch flex-${FLEX_VERSION}.patch not found."
    fi
    (cd flex-${FLEX_VERSION} ; ./configure --prefix=${autotools_install} ; make install)

    trap - ERR

    cd  ${autotools_root}

    if test "$IS_EC2_JENKINS" = "yes" ; then
        echo "==> Archiving build to S3"
        tar czf "${tarball_name}" "${autotools_install_short}"
        aws s3 cp "${tarball_name}" "${s3_build_path}/${tarball_name}"
        rm "${tarball_name}"
    fi
fi

if [[ -e "${target_link}" && ! -L "${target_link}" ]] ; then
    echo "${target_link} exists but is not a symlink.  Cowardly not creating link."
    exit 99
else
    echo "==> Symlinking ${autotools_install} to ${target_link}"
    rm -f "${target_link}"
    ln -s "${autotools_install}" "${target_link}"
fi
