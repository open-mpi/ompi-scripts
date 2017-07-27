#!/bin/bash
#
# usage: build-tarball.sh <build_type> <REF> <s3_prefix> <build_date>
#
# First step in building a release tarball; takes a git checkout
# and makes the tarballs, uploading the results to S3.  Before
# uploading, some basic sanity checks are performed to make sure
# that the requested release in some way matches the actual
# release.
#
# Expected filesystem layout:
#    ${WORKSPACE}/ompi-scripts/         ompi-scripts checkout
#    ${WORKSPACE}/ompi/                 ompi checkout @ target REF
#    ${WORKSPACE}/dist-files/           output of build

set -e

build_type=$1
ref=$2
s3_prefix=$3
build_date="$4"

echo "build_type: ${build_type}"
echo "ref: ${ref}"
echo "s3_prefix: ${s3_prefix}"
echo "build_date: ${build_date}"

# If doing a release or pre-release, the given ref must be a tag.
# search for the tag and chicken out if we can't ifnd it.
if test "$build_type" = "release" -o "${build_type}" = "pre-release"; then
  (cd ompi;
   git tag -l ${ref};
   if test "`git tag -l ${ref}`" = ""; then
     echo "Build target ${ref} does not appear to be a tag."
     exit 1
   fi)
fi

# This won't do anything rational on a ref that isn't a tag in
# our usual format, but the check is only used for the release
# and pre-release options, which should only build on tags, so
# shrug.
greek=`echo "$ref" | sed -e 's/v\?[0-9]\+\.[0-9]\+\.[0-9]\+//'`

case "$build_type" in
    "release")
	greek_option="--no-greek"
     if test "$greek" != "" ; then
       echo "Found what appears to be a greek version in tag $ref of $greek."
       echo "Aborting because this doesn't look right."
       exit 1
     fi
	;;
    "pre-release")
	greek_option="--greekonly"
     if test "$greek" = "" ; then
       echo "Did not find a greek version in tag $ref."
       echo "Aborting because this doesn't look right."
       exit 1
     fi
	;;
    "scratch")
     greek_option="--greekonly"
     ;;
    *)
	echo "Unknown build type ${build_type}"
	exit 1
	;;
esac

rm -rf dist-files
mkdir dist-files
(cd ompi ; contrib/dist/make_dist_tarball --no-git-update ${greek_option} --distdir ${WORKSPACE}/dist-files)

# release version is the tarball version name, which is roughly what
# is in the tarball's VERSION file.
tarball=`ls -1 dist-files/openmpi-*.tar.gz`
tarball=`basename ${tarball}`
release_version=`echo ${tarball} | sed -e 's/.*openmpi-\(.*\)\.tar\.\(gz\|bz2\)/\1/'`
if test "${release_version}" = "" ; then
    echo "Could not determine release version for ${tarball}"
    exit 1
fi

# branch_directory is the directory in S3/web pages for this release.
# While the branch that releases come from might not follow a strict
# format (I'm looking at you, v2.x), the web page names are always
# v<MAJOR>.<MINOR>
branch_directory=`echo "v${release_version}" | sed -e 's/\([0-9]\+\.[0-9]\+\).*/\1/'`

# ref_version is the ref with any leading v stripped out, because
# people aren't always great about tagging versions as v1.2.3 instead
# of 1.2.3.
ref_version=`echo ${REF} | sed -e 's/v\(.*\)/\1/'`

# if we're not doing a scratch build, make sure that the tag version
# matches the version produced
if test "${build_type}" != "scratch" -a "${ref_version}" != "$release_version"; then
  echo "Build target version ${ref_version} does not match release tarball version ${release_version}."
  exit 1
fi

# release the files into s3
dist_files=`ls dist-files/openmpi-*`
${WORKSPACE}/ompi-scripts/dist/upload-release-to-s3.py \
    --s3-base "${s3_prefix}" --project "open-mpi" --branch "${branch_directory}" \
    --version "${release_version}" --date "${build_date}" --yes \
    --files $dist_files

# need to save the tarball name and branch_directory for consumption
# by the calling script
echo "${tarball}" > build-tarball-filename.txt
echo "${branch_directory}" > build-tarball-branch_directory.txt
