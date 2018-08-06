#!/usr/bin/python
#
# Copyright (c) 2018      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# This script is used to upload new release artifacts to the Open MPI
# organization's S3 release bucket.  See ./upload-release-to-s3.py
# --help for more information on command line arguments.
#
# In general, the usage flow looks something like:
#   * Log into aws.open-mpi.org
#   * Clone https://github.com/bwbarrett/ompi-www.git somewhere in
#     your ~/www directory
#   * Go to https://aws.open-mpi.org/~[your userid]/<clone location>/ and
#     make sure it is working
#   * Use upload-release-to-s3.py to push release artifacts
#   * Edit software/<project>/<release branch>/version.inc to make
#     the release "live"
#   * Visit the web site and make sure the right things appeared.
#   * Commit web page changes.  The HostGator site syncs from GitHub
#     every 15 minutes.
#

import argparse
import boto3
import botocore
import urlparse
import sys
import re
import os
import dateutil
import time
import uploadutils


default_s3_base = 's3://open-mpi-release/release'
default_region = 'us-west-2'


def arg_check_copy(target, source, name):
    if not name in source:
        print('%s not specified but is required either because --yes was specified' % (name))
        print('or one of --project, --branch, --version, or --date was specified.')
        exit(1)
    target[name] = source[name]


parser = argparse.ArgumentParser(description='Upload project release to S3',
                                 epilog='If any of --project, --base, --version, ' +
                                   'or --date are specified, all 4 options must be ' +
                                   'specified.  If none are specified, the script ' +
                                   'will attempt to guess the options.')
parser.add_argument('--region',
                    help='Default AWS region',
                    type=str, required=False, default=default_region)
parser.add_argument('--s3-base',
                    help='S3 base URL.  Optional, defaults to s3://open-mpi-release/release',
                    type=str, required=False, default=default_s3_base)
parser.add_argument('--project',
                    help='Project (open-mpi, hwloc, etc.) for release being pushed',
                    type=str, required=False)
parser.add_argument('--branch',
                    help='Release branch for release',
                    type=str, required=False)
parser.add_argument('--version',
                    help='Version for release',
                    type=str, required=False)
parser.add_argument('--date',
                    help='Specify release date, in the local timezone',
                    type=str, required=False)
parser.add_argument('--yes',
                    help='Assume yes to go/no go question.  Note that you must ' +
                    'specify --s3-base, --project, --branch, and --date ' +
                    'explicitly when using --yes and --yes will cause the upload ' +
                    'to fail if files would be overwritten.',
                    action='store_true', required=False)
parser.add_argument('--files',
                    help='space separated list of files to upload',
                    type=str, required=True, nargs='*')
args = parser.parse_args()
args_dict = vars(args)

# split the s3 URL into bucket and path, which is what Boto3 expects
parts = urlparse.urlparse(args_dict['s3_base'])
if parts.scheme != 's3':
    print('unexpected URL format for s3-base.  Expected scheme s3, got %s' % parts.scheme)
    exit(1)
bucket_name = parts.netloc
key_prefix = parts.path.lstrip('/')

if len(args_dict['files']) < 1:
    print('No files specified.  Stopping.')
    exit(1)

if (args_dict['project'] == None or args_dict['branch'] == None
    or args_dict['version'] == None) or args_dict['date'] == None:
    if args_dict['yes']:
        print('Can not use --yes option unless --project, --branch, --version, ' +
              'and --date are also set.')
        exit(1)
    releaseinfo = uploadutils.parse_versions(args_dict['files'])
else:
    releaseinfo = {}

    arg_check_copy(releaseinfo, args_dict, 'project')
    arg_check_copy(releaseinfo, args_dict, 'branch')
    arg_check_copy(releaseinfo, args_dict, 'version')
    arg_check_copy(releaseinfo, args_dict, 'date')

    # add the basename based on the project name (because we screwed
    # up the name of the project in S3 for Open MPI)
    if releaseinfo['project'] == 'open-mpi':
        releaseinfo['basename'] = 'openmpi'
    else:
        releaseinfo['basename'] = releaseinfo['project']

    # convert the date into a unix time
    release_timetuple = dateutil.parser.parse(releaseinfo['date']).timetuple()
    releaseinfo['build_unix_time'] = int(time.mktime(release_timetuple))

prompt = 'ALWAYS_PROMPT'
if args_dict['yes']:
    prompt = 'NO_OVERWRITE'

s3_client = boto3.client('s3', args_dict['region'])
uploadutils.upload_files(s3_client, bucket_name, key_prefix,
                         releaseinfo, args_dict['files'], prompt)
