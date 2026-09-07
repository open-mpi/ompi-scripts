#!/bin/bash
#
# Run test build on release tarball
#
# usage tarball-distcheck.sh <build_prefix> <tarball>
#
# Expected filesystem layout:
#    ${WORKSPACE}/ompi-scripts/         ompi-scripts checkout
#    ${WORKSPACE}/ompi/                 ompi checkout @ target REF
#    ${WORKSPACE}/dist-files/           output of build

set -euo pipefail

build_prefix="$1"
tarball="$2"

echo "build_prefix: ${build_prefix}"
echo "tarball: ${tarball}"

if test -r "${HOME}/ompi-setup-python.sh" ; then
    echo "--> Initializing Python environment"
    . ${HOME}/ompi-setup-python.sh
    find . -name "requirements.txt" -exec ${PIP_CMD} install -r {} \;
else
    echo "--> No Python environment found, hoping for the best."
fi

aws s3 cp "${build_prefix}/${tarball}" "${WORKSPACE}/dist-files/${tarball}"
directory=`echo ${tarball} | sed -e 's/\(.*\)\.tar\..*/\1/'`
rm -rf "${directory}"
tar xf ${WORKSPACE}/dist-files/${tarball}

cd "${directory}"
./configure

set +e
make distcheck VERBOSE=1
if test $? -ne 0 ; then
    # Jenkins doesn't clean up properly if there's a bunch of unwriteable
    # directories, so help it out with cleanup.
    chmod -R u+w *
    cd "${WORKSPACE}"
    rm -rf "${directory}"
fi
set -e
