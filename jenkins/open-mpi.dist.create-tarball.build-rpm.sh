#!/bin/bash
#
# usage: build-rpm.sh <build_prefix> <srpm_name>
#
# Script to build a binary RPM from a source RPM
#
# Expected filesystem layout:
#    ${WORKSPACE}/ompi-scripts/         ompi-scripts checkout
#    ${WORKSPACE}/ompi/                 ompi checkout @ target REF
#    ${WORKSPACE}/dist-files/           output of build

set -e

build_prefix="$1"
srpm_name="$2"

aws s3 cp ${build_prefix}/${srpm_name} ${srpm_name}

# Build and install PRRTE and OpenPMIX, if available
if [[ -d ${WORKSPACE}/ompi/3rd-party/openpmix ]]; then
    pushd ${WORKSPACE}/ompi/3rd-party/openpmix
    ./autogen.pl; ./configure; make dist
    cd contrib
    tarball=$(find .. -name "*.bz2" -print)
    rpmtopdir="${WORKSPACE}/rpmbuild" build_srpm=no build_single=yes ./buildrpm.sh $tarball
    rpm_name=$(find ${WORKSPACE}/rpmbuild/RPMS -name "pmix*.rpm" -print)
    sudo rpm -Uvh ${rpm_name}
    popd
fi

if [[ -d ${WORKSPACE}/ompi/3rd-party/prrte ]]; then
    pushd ${WORKSPACE}/ompi/3rd-party/prrte
    ./autogen.pl; ./configure; make dist
    cd contrib/dist/linux
    tarball=$(find ../../.. -name "*.bz2" -print)
    rpmtopdir="${WORKSPACE}/rpmbuild" ./buildrpm.sh -b "${tarball}"
    rpm_name=$(find ${WORKSPACE}/rpmbuild/RPMS -name "prrte*.rpm" -print)
    sudo rpm -Uvh ${rpm_name}
    popd
fi

rpmbuild --rebuild ${srpm_name}
bin_rpm_name=`find ${WORKSPACE}/rpmbuild/RPMS -name "openmpi*.rpm" -print`
sudo rpm -Uvh ${bin_rpm_name}
