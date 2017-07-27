#!/bin/bash
#
# usage: build-srpm.sh <s3_prefix> <tarball_name> <branch_name> \
#                      <build_version> <build_time>
#
# Script to build a source RPM from an existing tarball and upload
# the output to the correct S3 bucket.
#
# Expected filesystem layout:
#    ${WORKSPACE}/ompi-scripts/         ompi-scripts checkout
#    ${WORKSPACE}/ompi/                 ompi checkout @ target REF
#    ${WORKSPACE}/dist-files/           output of build

set -e

s3_prefix="$1"
tarball="$2"
branch_name="$3"
build_date="$4"

# guess release version from tarball, same way build_tarball does 
release_version=`echo ${tarball} | sed -e 's/.*openmpi-\(.*\)\.tar\.\(gz\|bz2\)/\1/'`

# copy tarball back locally
aws s3 cp "${s3_prefix}/open-mpi/${branch_name}/${tarball}" "${WORKSPACE}/dist-files/${tarball}"

cp ompi/contrib/dist/linux/openmpi.spec .
ompi/contrib/dist/linux/buildrpm.sh dist-files/${tarball}
rpms=`find rpmbuild/SRPMS -name "*.rpm" -print`
${WORKSPACE}/ompi-scripts/dist/upload-release-to-s3.py \
    --s3-base "${s3_prefix}" --project "open-mpi" --branch "${branch_name}" \
    --version "${release_version}" --date "${build_date}" --yes \
    --files $rpms
srpm_name=`find rpmbuild/SRPMS -name "*.rpm" -print | head -n 1`
# only want the filename, not the path to the file, since upload_release_to_s3.py will remove
# the directory prefixes as well.
basename "$srpm_name" > ${WORKSPACE}/srpm-name.txt
