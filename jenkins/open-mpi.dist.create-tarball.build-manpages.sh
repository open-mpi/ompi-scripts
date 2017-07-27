#!/bin/bash
#
# Build man pages for Open MPI.
#
# usage build-manpages.sh <build_prefix> <tarball> <branch>
#
# Expected filesystem layout:
#    ${WORKSPACE}/ompi-scripts/         ompi-scripts checkout
#    ${WORKSPACE}/ompi/                 ompi checkout @ target REF
#    ${WORKSPACE}/dist-files/           output of build

set -e

build_prefix=$1
tarball=$2
branch=$3

echo "build_prefix: ${build_prefix}"
echo "tarball: ${tarball}"
echo "branch: ${branch}"

aws s3 cp "${build_prefix}/${tarball}" "${WORKSPACE}/dist-files/${tarball}"
tar xf ${WORKSPACE}/dist-files/${tarball}
directory=`echo ${tarball} | sed -e 's/\(.*\)\.tar\..*/\1/'`
cd ${directory}
../ompi/contrib/dist/make-html-man-pages.pl
mkdir ${WORKSPACE}/dist-files/doc
cp -rp man-page-generator/php ${WORKSPACE}/dist-files/doc/${branch}

cd ${WORKSPACE}/dist-files
docname="${directory}-doc.tar.gz"
tar czf ${docname} doc/
aws s3 cp ${docname} s3://open-mpi-scratch/scratch/open-mpi-doc/${docname}

echo "https://download.open-mpi.org/scratch/open-mpi-doc/${docname}" > ${WORKSPACE}/manpage-build-artifacts.txt
