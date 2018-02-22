#!/usr/bin/python
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# usage: build-staged-tarball-migration.py --input-path IN --output-path OUT
#
# Builds a staged tree of tarballs/srpms from the historical Open MPI
# layout into the directory structure used for S3 hosting (which is
# *always* release/<project>/<branch>/<filename> or
# nightly/<project>/<branch>/<filename>).  It doesn't re-arrange the
# directories, but instead verifies the various hashes, computes an
# accurate timestamp from the build artifacts themselves (because the
# curren tree has tarballs copied without timestamp preservation) and
# builds the build-*.json files for the S3 scheme the projects are
# using.
#
# This script doesn't push anything into S3 (giving you a chance to
# undo any directory structure before the push).  The AWS CLI has a
# nice S3 copy interface for pushing a directory tree.  After
# organizing into two directory structures (nightly and release), the
# initial push was run with:
#
# % aws --region us-east-1 s3 cp <release tree rout> \
#   s3://open-mpi-release/release/ --recursive
# % aws --region us-east-1 s3 cp <nightly tree root> \
#   s3://open-mpi-nightly/nightly/  --recursive
#

import os
import re
import tarfile
import argparse
import time
import json
import hashlib
import shutil

def compute_hashes(filename):
    """Helper function to compute MD5 and SHA1 hashes"""
    retval = {}
    md5 = hashlib.md5()
    sha1 = hashlib.sha1()
    with open(filename, 'rb') as f:
        while True:
            data = f.read(64 * 1024)
            if not data:
                break
            md5.update(data)
            sha1.update(data)
    retval['md5'] = md5.hexdigest()
    retval['sha1'] = sha1.hexdigest()
    return retval


def do_migrate(input_path, output_path):
    for root, dirs, files in os.walk(input_path, topdown=False):
        for name in files:
            output_root = root
            if os.path.basename(root) == 'downloads':
                output_root = os.path.dirname(output_root)
            output_dir = os.path.join(output_path, output_root)

            if name == 'latest_snapshot.txt':
                continue

            pattern = '\.dmg\.gz|\.exe|\.tar\.gz|\.tar\.bz2|-[0-9]+\.src\.rpm|\.zip'
            if re.search(pattern, name):
                base_filename = re.sub(pattern, '', name)
                full_filename = os.path.join(root, name)

                print("==> %s" % (full_filename))

                # clean up Open MPI windows names
                if re.search('\.exe', name) :
                    version_search = re.search('OpenMPI_v(.*)-.*', base_filename)
                    if version_search:
                        base_filename = 'openmpi-' + version_search.group(1)
                    else:
                        print("--> no joy %s" % base_filename)
                        continue

                # clean up hwloc windows names
                if re.search('\.zip', name):
                    version_search = re.search('(hwloc|libtopology)-win.*-build-(.*)', base_filename)
                    if version_search:
                        base_filename = '%s-%s' % (version_search.group(1),  version_search.group(2))
                    else:
                        print("--> no joy %s" % base_filename)
                        continue

                # skip the bad tarballs entirely...
                if re.search('\.tar\.', name):
                    try:
                        tar = tarfile.open(full_filename)
                    except:
                        continue

                # build info json files are named
                # build-<base_filename>.json, which hopefully is
                # unique enough (given that it should be unique enough
                # for the actual tarball).
                buildfile = 'build-%s.json' % (base_filename)

                build_pathname = os.path.join(output_path, output_root, buildfile)
                try:
                    with open(build_pathname, 'r') as fh:
                        builddata = json.load(fh)
                except:
                    builddata = {}
                    branch = os.path.basename(output_root)
                    version_search = re.search('.*-.*-[0-9]+-(.*)', base_filename)
                    if version_search:
                        revision = version_search.group(1)
                    else:
                        revision = ''
                    builddata['branch'] = branch
                    builddata['valid'] = True
                    # revision is only used for comparing nightly
                    # build versions.  If the tarball name doesn't
                    # match the git-based nightly tarball version, set
                    # revision to empty, as that will cause a rebuild
                    # (since, by definition, we're not at the latest.
                    builddata['revision'] = revision
                    builddata['build_unix_time'] = 0
                    builddata['delete_on'] = 0
                    builddata['files'] = {}

                if builddata['build_unix_time'] == 0 and re.search('\.tar\.', name):
                    try:
                        tar = tarfile.open(full_filename)
                    except:
                        print("tar file %s looks invalid" % (full_filename))
                    else:
                        # many tarballs had their ctime and mtime
                        # changed in the migration from IU to
                        # hostgator.  So look at the top level
                        # directory in the tarball instead.
                        builddata['build_unix_time'] = tar.getmembers()[0].mtime

                hashes = compute_hashes(full_filename)
                info = os.stat(full_filename)
                builddata['files'][name] = {}
                builddata['files'][name]['sha1'] = hashes['sha1']
                builddata['files'][name]['md5'] = hashes['md5']
                builddata['files'][name]['size'] = info.st_size

                # verify the md5sums / sha1sums are sane..
                verify = 0
                with open(os.path.join(root, 'md5sums.txt')) as f:
                    content = f.readlines()
                    for line in content:
                        entry = line.split()
                        if len(entry) != 2:
                            continue
                        if name == entry[1]:
                            if hashes['md5'] == entry[0]:
                                verify = verify + 1
                                break
                            else:
                                raise Exception("hash mismatch %s %s" % (entry[0], hashesh['md5']))
                with open(os.path.join(root, 'sha1sums.txt')) as f:
                    content = f.readlines()
                    for line in content:
                        entry = line.split()
                        if len(entry) != 2:
                            continue
                        if name == entry[1]:
                            if hashes['sha1'] == entry[0]:
                                verify = verify + 1
                                break
                            else:
                                raise Exception("hash mismatch %s %s" % (entry[0], hashesh['sha1']))
                if verify != 2:
                    raise Exception("Hash verification failure on %s" % (name))

                # make sure the directory exists...
                if not os.access(output_dir, os.F_OK):
                    os.makedirs(output_dir)

                with open(build_pathname, 'w') as fh:
                    json.dump(builddata, fh)

                shutil.copyfile(full_filename,
                                os.path.join(output_dir, name))

parser = argparse.ArgumentParser(description='Web tarball S3 staging')
parser.add_argument('--input-path', help='input path to traverse',
                    type=str, required=True)
parser.add_argument('--output-path', help='scratch directory to stage for later s3 upload',
                    type=str, required=True)
args = parser.parse_args()

args_dict = vars(args)

do_migrate(args_dict['input_path'], args_dict['output_path'])
