#!/usr/bin/env python
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import os
import sys
import re
import argparse
import logging
import time
import shlex
import shutil
import urllib
import requests
import BuilderUtils


def run_coverity_internal(logger, build_root, source_tarball, config):
    # read the token file
    file = open(config['token_file'], 'r')
    token = file.readline().rstrip('\n')

    # get the tool
    if not os.path.isdir(config['tool_dir']):
        os.makedirs(config['tool_dir'])
    os.chdir(config['tool_dir'])
    timestamp = 0
    if os.path.exists('coverity_tool.tgz'):
        timestamp  = os.stat('coverity_tool.tgz').st_mtime
    if (timestamp + (24 * 3600)) > int(time.time()):
        logger.debug('Reusing existing tarball')
    else:
        logger.debug('Downloading %s' % (config['tool_url']))
        data = {
            'token' : token,
            'project' : config['project_name'],
        }
        r = requests.get(config['tool_url'], params=data)
        with open('coverity_tool.tgz', 'wb') as fp:
            fp.write(r.content)

    # make sure we have a build root
    if not os.path.isdir(build_root):
        os.makedirs(build_root)
    os.chdir(build_root)

    # The name of the top-level directory in the tarball changes every
    # time Coverity releases a new version of the tool.  So search
    # around and hope we find something.
    logger.debug('Expanding coverity_tool.tgz')
    BuilderUtils.logged_call(['tar', 'xf', os.path.join(config['tool_dir'], 'coverity_tool.tgz')],
                             log_file=os.path.join(build_root, 'coverity-tools-untar-output.txt'))
    cov_path=''
    for file in os.listdir(build_root):
        if file.startswith('cov-'):
            cov_path = os.path.join(build_root, file, 'bin')
            break
    logger.debug('Found Coverity path %s' % (cov_path))

    child_env = os.environ.copy()
    child_env['PATH'] = cov_path + ':' + child_env['PATH']

    logger.debug('Extracting build tarball: %s' % (source_tarball))
    BuilderUtils.logged_call(['tar', 'xf', source_tarball],
                             log_file=os.path.join(build_root, 'coverity-source-untar-output.txt'))

    # guess the directory based on the tarball name.  Don't worry
    # about the exception, because we want out in that case anyway...
    build_version = re.search('^' + config['project_prefix'] + '-(.*)\.tar\..*$',
                              os.path.basename(source_tarball)).group(1)
    srcdir = config['project_prefix'] + '-' + build_version
    os.chdir(srcdir)

    logger.debug('coverity configure')
    args = ['./configure']
    if 'configure_args' in config:
        args.extend(shlex.split(config['configure_args']))
    BuilderUtils.logged_call(args, env=child_env,
                             log_file=os.path.join(build_root, 'coverity-configure-output.txt'))

    logger.debug('coverity build')
    args = ['cov-build', '--dir', 'cov-int', 'make']
    if 'make_args' in config:
        args.extend(shlex.split(config['make_args']))
    BuilderUtils.logged_call(args, env=child_env,
                             log_file=os.path.join(build_root, 'coverity-make-output.txt'))

    logger.debug('bundling results')
    results_tarball = os.path.join(build_root, 'analyzed.tar.bz2')
    BuilderUtils.logged_call(['tar', 'jcf', results_tarball, 'cov-int'],
                             log_file=os.path.join(build_root, 'coverity-results-tar-output.txt'))

    logger.debug('submitting results')
    url = 'https://scan.coverity.com/builds?project=' + config['project_name']
    files = { 'file': open(results_tarball, 'rb') }
    values = { 'email' : config['email'],
               'version' : build_version,
               'description' : 'nightly-master',
               'token' : token }
    r = requests.post(url, files=files, data=values)
    r.raise_for_status()


def run_coverity(logger, build_root, source_tarball, config):
    """Run coverity test and submit results

    Run Coverity test and submit results to their server.  Can be run
    either standalone (with a tarball as a target) or integrated into
    the Builder class.

    """
    cwd = os.getcwd()
    try:
        run_coverity_internal(logger, build_root, source_tarball, config)
    finally:
        os.chdir(cwd)


if __name__ == '__main__':
    config = { 'tool_url' : 'https://scan.coverity.com/download/cxx/linux64',
               'log_level' : 'INFO' }

    parser = argparse.ArgumentParser(description='Coverity submission script for Open MPI related projects')
    parser.add_argument('--log-level', help='Log level.', type=str,
                              choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'])
    parser.add_argument('--build-root',
                        help='Directory to use as base of build tree.',
                        type=str)
    parser.add_argument('--source-tarball',
                        help='Tarball to submit for analysis',
                        type=str)
    parser.add_argument('--tool-dir',
                        help='Directory in which to store downloaded tool (for reuse)',
                        type=str)
    parser.add_argument('--tool-url',
                        help='URL for downloading Coverity tool',
                        type=str)
    parser.add_argument('--project-name',
                        help='Coverity project name',
                        type=str)
    parser.add_argument('--project-prefix',
                        help='prefix of the tarball directory',
                        type=str)
    parser.add_argument('--token-file',
                        help='File containing the Coverity token for project',
                        type=str)
    parser.add_argument('--configure-args',
                        help='Configuration arguments for source tarball',
                        type=str)
    parser.add_argument('--make-args',
                        help='Build arguments for source tarball',
                        type=str)
    parser.add_argument('--email',
                        help='Coverity submission email address',
                        type=str)

    for key, value in vars(parser.parse_args()).iteritems():
        if not value == None:
            config[key] = value

    logging.basicConfig()
    logger = logging.getLogger()
    logger.setLevel(config['log_level'])

    run_coverity(logger, config['build_root'], config['source_tarball'], config)
