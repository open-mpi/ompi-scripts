#!/usr/bin/python
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# usage: nightly-tarball-sync.py --project <project name> \
#            --input-tree <S3 PATH> --output-tree <PATH> <branches>
#
# Sync nightly tarballs from S3 into the HostGator web site (until
# such time as we convert the website to pull from S3 directly).  If
# there are multiple builds between runs, all but the build that ends
# up in latest_snapshot.txt will be missed.  This script should be run
# significantly more often than once a day as a result.  Since the
# builds are serialized and take > 10 minutes, the plan is to run
# every 10 minutes.  Checking latest_snapshot.txt is pretty low
# overhead, so that shouldn't be a problem.
#

import os
import argparse
import time
import json
import shutil
import urllib
import urllib2
import subprocess

def sync_tree(project, input_path, output_path, branch):
    response = urllib2.urlopen('%s/%s/latest_snapshot.txt' % (input_path, branch))
    s3_latest_snapshot = response.read().strip()

    try:
        local_file = open('%s/%s/latest_snapshot.txt' % (output_path, branch), 'r')
        local_latest_snapshot = local_file.read().strip()
    except:
        local_latest_snapshot = ''

    if s3_latest_snapshot == local_latest_snapshot:
        return

    # get info about new snapshot
    response = urllib2.urlopen('%s/%s/build-%s-%s.json' % (input_path, branch,
                                                           project, s3_latest_snapshot))
    data = json.load(response)

    # delete copies older than 7 days
    for filename in os.listdir('%s/%s' % (output_path, branch)):
        full_filename = '%s/%s/%s' % (output_path, branch, filename)
        if (filename.endswith(".txt") or filename.endswith(".php")):
            continue
        if (time.time() - os.path.getmtime(full_filename) > (7 * 24 * 60 * 60)):
            os.remove(full_filename)

    # copy files from new snapshot
    for file in data['files']:
        fileurl = urllib.URLopener()
        fileurl.retrieve('%s/%s/%s' % (input_path, branch, file),
                         '%s/%s/%s' % (output_path, branch, file))

    # generate md5sums and sha1sums
    os.chdir('%s/%s' % (output_path, branch))
    output = open('md5sums.txt', 'w')
    subprocess.check_call(['md5sum *.tar.gz *.tar.bz2'], stdout=output, shell=True)
    output = open('sha1sums.txt', 'w')
    subprocess.check_call(['sha1sum *.tar.gz *.tar.bz2'], stdout=output, shell=True)

    # update snapshot file
    snapfile = open('latest_snapshot.txt', 'w')
    snapfile.write(s3_latest_snapshot)


parser = argparse.ArgumentParser(description='Web tarball S3 staging')
parser.add_argument('--project', help='project name (tarball prefix)',
                    type=str, required=True)
parser.add_argument('--input-path', help='input path to traverse',
                    type=str, required=True)
parser.add_argument('--output-path', help='scratch directory to stage for later s3 upload',
                    type=str, required=True)
parser.add_argument('branches', nargs='*', default=[], help='List of branches to build')
args = parser.parse_args()

args_dict = vars(args)

for branch in args_dict['branches']:
    sync_tree(args_dict['project'], args_dict['input_path'],
              args_dict['output_path'], branch)

