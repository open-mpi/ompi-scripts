#!/usr/bin/python
#
# Copyright (c) 2018      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import boto3
import botocore
import sys
import re
import os
import json
import tarfile
import hashlib
from io import StringIO
import datetime
import unittest
import mock
import posix

def __unique_assign(releaseinfo, key, value):
    if not key in releaseinfo:
        releaseinfo[key] = value
    elif releaseinfo[key] != value:
        raise Exception('Found files from two %ss: %s %s' %
                        (key, releaseinfo[key], value))


def __compute_hashes(filename):
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


def __query_yes_no(question, default="yes"):
    """Ask a yes/no question via raw_input() and return their answer.

    "question" is a string that is presented to the user.
    "default" is the presumed answer if the user just hits <Enter>.
        It must be "yes" (the default), "no" or None (meaning
        an answer is required of the user).

    The "answer" return value is True for "yes" or False for "no".
    """
    valid = {"yes": True, "y": True, "ye": True,
             "no": False, "n": False}
    if default is None:
        prompt = " [y/n] "
    elif default == "yes":
        prompt = " [Y/n] "
    elif default == "no":
        prompt = " [y/N] "
    else:
        raise ValueError("invalid default answer: '%s'" % default)

    while True:
        sys.stdout.write(question + prompt)
        choice = raw_input().lower()
        if default is not None and choice == '':
            return valid[default]
        elif choice in valid:
            return valid[choice]
        else:
            sys.stdout.write("Please respond with 'yes' or 'no' "
                             "(or 'y' or 'n').\n")


def parse_versions(filelist):
    """Parse the project name, branch, file basename, and version name from a file list

    We're pretty conservative in this function, because it's an
    optimization over specifying a bunch of command linke arguments
    explicitly.  Add projects / regexes as necessary...
    """

    releaseinfo = {}
    build_unix_time = 0

    for filename in filelist:
        if re.search(r'openmpi|OpenMPI', filename):
            m = re.search(r'openmpi\-([0-9a-zA-Z\.]+)(?:\.tar|\-[0-9]+\.src\.rpm|\.dmg.gz)',
                         filename)
            if m == None:
                m = re.search(r'OpenMPI_v([0-9a-zA-Z\.]+)\-[0-9]+_win', filename)
                if m == None:
                    raise Exception('Could not parse Open MPI filename: %s' % (filename))

            # yes, we mean open-mpi for the project.  We perhaps were
            # silly in naming the branch in S3.
            __unique_assign(releaseinfo, 'basename', 'openmpi')
            __unique_assign(releaseinfo, 'project', 'open-mpi')
            __unique_assign(releaseinfo, 'version', m.group(1))

        elif re.search('^hwloc-', filename):
            m = re.search(r'hwloc\-([0-9a-zA-Z\.]+)(?:\.tar|\-[0-9]+\.src\.rpm)',
                         filename)
            if m == None:
                m = re.search(r'hwloc-win[0-9]+-build-([0-9a-zA-Z\.]+)\.zip', filename)
                if m == None:
                    raise Exception('Could not parse hwloc filename: %s' % (filename))

            __unique_assign(releaseinfo, 'basename', 'hwloc')
            __unique_assign(releaseinfo, 'project', 'hwloc')
            __unique_assign(releaseinfo, 'version', m.group(1))

        else:
            raise Exception('Could not parse %s' % (filename))

        m = re.search(r'^[0-9]+\.[0-9]+', releaseinfo['version'])
        if m == None:
            raise Exception('Could not parse version %s' % (releaseinfo['version']))
        __unique_assign(releaseinfo, 'branch', 'v%s' % (m.group(0)))

        if build_unix_time == 0 and re.search('\.tar\.', filename):
            try:
                tar = tarfile.open(filename)
            except:
                raise
            else:
                # rather than look at the ctime and mtime of the
                # tarball (which may change as tarballs are copied
                # around), look at the top level directory (first
                # entry in the tarball) for a mtime.
                build_unix_time = tar.getmembers()[0].mtime

    if build_unix_time != 0:
        releaseinfo['build_unix_time'] = build_unix_time

    return releaseinfo


def upload_files(s3_client, s3_bucket, s3_key_prefix, release_info, files, prompt):
    # first, verify that the key_prefix exists.  We are chicken here
    # and won't create it.
    result = s3_client.list_objects_v2(Bucket = s3_bucket,
                                       Prefix = s3_key_prefix)
    if s3_bucket != 'open-mpi-scratch' and result['KeyCount'] == 0:
        raise Exception('s3://%s/%s does not appear to be a valid prefix.' %
                        (s3_bucket, full_key_prefix))

    # figure out if project and branch exist...
    new = ""
    project_key_path = '%s/%s' % (s3_key_prefix, release_info['project'])
    branch_key_path = '%s/%s' % (project_key_path, release_info['branch'])

    # print some release info
    print('Upload path: s3://%s/%s' % (s3_bucket, branch_key_path))
    print('Project:     %s' % release_info['project'])
    print('Version:     %s' % release_info['version'])
    print('Branch:      %s' % release_info['branch'])
    print('Date:        %s' % datetime.datetime.fromtimestamp(release_info['build_unix_time']))

    branch_result = s3_client.list_objects_v2(Bucket = s3_bucket,
                                              Prefix = branch_key_path)
    if branch_result['KeyCount'] == 0:
        project_result = s3_client.list_objects_v2(Bucket = s3_bucket,
                                                   Prefix = project_key_path)
        if project_result['KeyCount'] == 0:
            print(' * New project %s and branch %s' %
                  (release_info['project'], release_info['branch']))
        else:
            print(' * New branch %s' % (release_info['branch']))

    # and check for existing release
    build_filename = '%s/build-%s-%s.json' % (branch_key_path, release_info['basename'],
                                        release_info['version'])
    try:
        response = s3_client.get_object(Bucket = s3_bucket, Key = build_filename)
        buildinfo = json.load(response['Body'])
        buildinfo_found = True
    except botocore.exceptions.ClientError as e:
        code = e.response['Error']['Code']
        if code == 'NoSuchKey':
            buildinfo_found = False
        else:
            raise
        buildinfo = {}
        buildinfo['files'] = {}

    # check if we would overwrite a file and verify that would be ok...
    will_overwrite = False
    if buildinfo_found:
        print('Existing release found for %s %s' %
              (release_info['basename'], release_info['version']))

        print(' * Existing files that will not change:')
        for filename in buildinfo['files']:
            if not filename in files:
                print('   - %s' % filename)

        print(' * Existing files that will be overwritten:')
        for filename in buildinfo['files']:
            if filename in files:
                will_overwrite = True
                print('   - %s' % filename)

        print(' * New files:')
        for filename in files:
            filename = os.path.basename(filename)
            if not filename in buildinfo['files']:
                print('   - %s' % filename)
    else:
        print('New release for %s %s' %
              (release_info['basename'], release_info['version']))
        print(' * Files to upload:')
        for filename in files:
            filename = os.path.basename(filename)
            print('   - %s' % filename)

    print('')
    if prompt == 'ALWAYS_PROMPT':
        if not __query_yes_no('Continue?', 'no'):
            print('Aborting due to user selection')
            return
    elif prompt == 'NO_OVERWRITE':
        if will_overwrite:
            print('Aborting due to --yes and file overwrite')
            return
    elif prompt == 'NEVER_PROMPT':
        pass
    elif prompt == 'ASSUME_NO':
        print('Aborting due to ASSUME_NO')
        return
    else:
        raise Exception('Unknown Prompt value %d' % prompt)

    # build a build-info structure for the release, possibly building
    # on the old one...
    buildinfo['branch'] = release_info['branch']
    buildinfo['valid'] = True
    buildinfo['revision'] = release_info['version']
    buildinfo['build_unix_time'] = release_info['build_unix_time']
    buildinfo['delete_on'] = 0

    for filename in files:
        info = os.stat(filename)
        hashes = __compute_hashes(filename)
        fileinfo = {}
        fileinfo['sha1'] = hashes['sha1']
        fileinfo['md5'] = hashes['md5']
        fileinfo['size'] = info.st_size
        buildinfo['files'][os.path.basename(filename)] = fileinfo

    for filename in files:
        target_name = '%s/%s' % (branch_key_path, os.path.basename(filename))
        s3_client.upload_file(filename, s3_bucket, target_name)

    buildinfo_str = json.dumps(buildinfo)
    s3_client.put_object(Bucket = s3_bucket, Key = build_filename,
                         Body = buildinfo_str)


######################################################################
#
# Unit Test Code
#
######################################################################
def _test_stat(filename):
    info = posix.stat_result((0, 0, 0, 0, 0, 0, 987654, 0, 0, 0))
    return info

def _test_compute_hashes(filename):
    retval = {}
    retval['md5'] = "ABC"
    retval['sha1'] = "ZYX"
    return retval


class _test_tarfile():
    def __init__(self):
        pass

    def getmembers(self):
        info = tarfile.TarInfo
        info.mtime = 12345
        return [info]

    @classmethod
    def open(cls, filename):
        return _test_tarfile()


class parse_versions_tests(unittest.TestCase):
    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_ompi_release(self):
        filelist = ["openmpi-1.4.0.tar.gz",
                    "openmpi-1.4.0.tar.bz2",
                    "openmpi-1.4.0-1.src.rpm"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "open-mpi",
                         releaseinfo['project'] + " != open-mpi")
        self.assertEqual(releaseinfo['basename'], "openmpi",
                         releaseinfo['basename'] + " != openmpi")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0",
                         releaseinfo['version'] + " != 1.4.0")
        self.assertEqual(releaseinfo['build_unix_time'], 12345,
                         str(releaseinfo['build_unix_time']) + " != 12345")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_ompi_release_second_srpm(self):
        filelist = ["openmpi-1.4.0.tar.gz",
                    "openmpi-1.4.0.tar.bz2",
                    "openmpi-1.4.0-2.src.rpm"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "open-mpi",
                         releaseinfo['project'] + " != open-mpi")
        self.assertEqual(releaseinfo['basename'], "openmpi",
                         releaseinfo['basename'] + " != openmpi")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0",
                         releaseinfo['version'] + " != 1.4.0")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_ompi_binaries(self):
        filelist = ["openmpi-1.4.0.tar.gz",
                    "openmpi-1.4.0.tar.bz2",
                    "openmpi-1.4.0-1.src.rpm",
                    "openmpi-1.4.0.dmg.gz",
                    "OpenMPI_v1.4.0-1_win64.exe"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "open-mpi",
                         releaseinfo['project'] + " != open-mpi")
        self.assertEqual(releaseinfo['basename'], "openmpi",
                         releaseinfo['basename'] + " != openmpi")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0",
                         releaseinfo['version'] + " != 1.4.0")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_ompi_prerelease(self):
        filelist = ["openmpi-1.4.0rc1.tar.gz",
                    "openmpi-1.4.0rc1.tar.bz2",
                    "openmpi-1.4.0rc1-1.src.rpm"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "open-mpi",
                         releaseinfo['project'] + " != open-mpi")
        self.assertEqual(releaseinfo['basename'], "openmpi",
                         releaseinfo['basename'] + " != openmpi")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0rc1",
                         releaseinfo['version'] + " != 1.4.0rc1")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_ompi_mixed_versions(self):
        filelist = ["openmpi-1.4.0.tar.gz",
                    "openmpi-1.4.1.tar.bz2",
                    "openmpi-1.4.0-1.src.rpm"]
        try:
            releaseinfo = parse_versions(filelist)
        except Exception as e:
            pass
        else:
            self.fail()

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_hwloc_release(self):
        filelist = ["hwloc-1.4.0.tar.gz",
                    "hwloc-1.4.0.tar.bz2",
                    "hwloc-win32-build-1.4.0.zip",
                    "hwloc-win64-build-1.4.0.zip"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "hwloc",
                         releaseinfo['project'] + " != hwloc")
        self.assertEqual(releaseinfo['basename'], "hwloc",
                         releaseinfo['basename'] + " != hwloc")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0",
                         releaseinfo['version'] + " != 1.4.0")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_hwloc_prerelease(self):
        filelist = ["hwloc-1.4.0rc1.tar.gz",
                    "hwloc-1.4.0rc1.tar.bz2",
                    "hwloc-win32-build-1.4.0rc1.zip",
                    "hwloc-win64-build-1.4.0rc1.zip"]
        releaseinfo = parse_versions(filelist)
        self.assertEqual(releaseinfo['project'], "hwloc",
                         releaseinfo['project'] + " != hwloc")
        self.assertEqual(releaseinfo['basename'], "hwloc",
                         releaseinfo['basename'] + " != hwloc")
        self.assertEqual(releaseinfo['branch'], "v1.4",
                         releaseinfo['branch'] + " != v1.4")
        self.assertEqual(releaseinfo['version'], "1.4.0rc1",
                         releaseinfo['version'] + " != 1.4.0rc1")

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_hwloc_mixed_versions(self):
        filelist = ["hwloc-1.4.0.tar.gz",
                    "hwloc-1.4.1.tar.bz2",
                    "hwloc-win32-build-1.4.0.zip",
                    "hwloc-win64-build-1.4.0.zip"]
        try:
            releaseinfo = parse_versions(filelist)
        except Exception as e:
            pass
        else:
            self.fail()

    @mock.patch('tarfile.open', _test_tarfile.open)
    def test_hwloc_mixed_versions2(self):
        filelist = ["hwloc-1.4.0.tar.gz",
                    "hwloc-1.4.0.tar.bz2",
                    "hwloc-win32-build-1.4.1.zip",
                    "hwloc-win64-build-1.4.0.zip"]
        try:
            releaseinfo = parse_versions(filelist)
        except Exception as e:
            pass
        else:
            self.fail()

    # we didn't teach the parser about netloc (because it's dead), so
    # this should fail
    def test_netloc(self):
        filelist = ["netloc-1.4.0.tar.gz",
                    "netloc-1.4.0.tar.bz2"]
        try:
            releaseinfo = parse_versions(filelist)
        except Exception as e:
            pass
        else:
            self.fail()


class upload_files_tests(unittest.TestCase):
    class test_s3_client():
        def __init__(self, path, Existing = False):
            self._readcount = 0
            self._file_write_list = []
            self._stream_write = ""
            self._path = path
            self._existing = Existing


        def get_object(self, Bucket, Key):
            self._readcount += 1
            result = {}

            if not self._existing or Key != self._path + 'build-openmpi-100.0.0rho1.json':
                response = {}
                response['Error'] = {}
                response['Error']['Code'] = 'NoSuchKey'
                raise botocore.exceptions.ClientError(response, 'get_object')

            buildinfo = {}
            buildinfo['branch'] = 'v100.0'
            buildinfo['valid'] = True
            buildinfo['revision'] = '100.0.0rho1'
            buildinfo['build_unix_time'] = 314314
            buildinfo['delete_on'] = 0
            buildinfo['files'] = {}
            fileinfo = {}
            fileinfo['sha1'] = 'abc'
            fileinfo['md5'] = 'zyx'
            fileinfo['size'] = 1024
            buildinfo['files']['openmpi-100.0.0rho1.tar.bz2'] = fileinfo
            result['Body'] = StringIO(json.dumps(buildinfo))

            return result


        def list_objects_v2(self, Bucket, Prefix):
            self._readcount += 1
            result = {}

            if self._path.startswith(Prefix):
                result['KeyCount'] = 1
            else:
                result['KeyCount'] = 0
            return result


        def upload_file(self, Filename, Bucket, Key):
            assert(Key.startswith(self._path))
            self._file_write_list.append(Key)


        def put_object(self, Bucket, Key, Body):
            assert(Key.startswith(self._path))
            self._file_write_list.append(Key)
            self._stream_write += Body


        def get_readcount(self):
            return self._readcount


        def get_write_list(self):
            return self._file_write_list


        def get_write_stream(self):
            return self._stream_write


    @mock.patch('os.stat', _test_stat)
    @mock.patch('__main__.__compute_hashes', _test_compute_hashes)
    def test_new_buildinfo(self):
        releaseinfo = {}
        releaseinfo['project'] = 'open-mpi'
        releaseinfo['branch'] = 'v100.0'
        releaseinfo['version'] = '100.0.0rho1'
        releaseinfo['basename'] = 'openmpi'
        releaseinfo['build_unix_time'] = 12345

        files = ['openmpi-100.0.0rho1.tar.gz', 'openmpi-100.0.0rho1.tar.bz2']

        client = self.test_s3_client("scratch/open-mpi/v100.0/", Existing = False)

        upload_files(client, 'open-mpi-scratch', 'scratch',
                     releaseinfo, files, 'NO_OVERWRITE')
        self.assertEqual(client.get_readcount(), 3,
                         "readcount was %d, expected 3" % (client.get_readcount()))
        self.assertEqual(len(client.get_write_list()), 3,
                         "Unexpected write list length: %s" % str(client.get_write_list()))
        buildinfo = json.loads(client.get_write_stream())
        self.assertEqual(len(buildinfo['files']), 2,
                         'Unexpected files length: %s' % str(buildinfo['files']))


    def test_existing_buildinfo_nocontinue(self):
        releaseinfo = {}
        releaseinfo['project'] = 'open-mpi'
        releaseinfo['branch'] = 'v100.0'
        releaseinfo['version'] = '100.0.0rho1'
        releaseinfo['basename'] = 'openmpi'
        releaseinfo['build_unix_time'] = 1

        files = ['openmpi-100.0.0rho1.tar.gz']

        client = self.test_s3_client("scratch/open-mpi/v100.0/", Existing = True)

        upload_files(client, 'open-mpi-scratch', 'scratch',
                     releaseinfo, files, 'ASSUME_NO')
        self.assertEqual(client.get_readcount(), 3,
                         "readcount was %d, expected 3" % (client.get_readcount()))
        self.assertEqual(len(client.get_write_list()), 0,
                         "Unexpected write list length: %s" % str(client.get_write_list()))


    @mock.patch('os.stat', _test_stat)
    @mock.patch('__main__.__compute_hashes', _test_compute_hashes)
    def test_existing_buildinfo_nooverlap(self):
        releaseinfo = {}
        releaseinfo['project'] = 'open-mpi'
        releaseinfo['branch'] = 'v100.0'
        releaseinfo['version'] = '100.0.0rho1'
        releaseinfo['basename'] = 'openmpi'
        releaseinfo['build_unix_time'] = 1

        files = ['openmpi-100.0.0rho1.tar.gz']

        client = self.test_s3_client("scratch/open-mpi/v100.0/", Existing = True)

        upload_files(client, 'open-mpi-scratch', 'scratch',
                     releaseinfo, files, 'NO_OVERWRITE')

        self.assertEqual(client.get_readcount(), 3,
                         "readcount was %d, expected 3" % (client.get_readcount()))
        self.assertEqual(len(client.get_write_list()), 2,
                         "Unexpected write list length: %s" % str(client.get_write_list()))
        buildinfo = json.loads(client.get_write_stream())
        self.assertEqual(len(buildinfo['files']), 2,
                         'Unexpected files length: %s' % str(buildinfo['files']))


    @mock.patch('os.stat', _test_stat)
    @mock.patch('__main__.__compute_hashes', _test_compute_hashes)
    def test_existing_buildinfo_overlap_ok(self):
        releaseinfo = {}
        releaseinfo['project'] = 'open-mpi'
        releaseinfo['branch'] = 'v100.0'
        releaseinfo['version'] = '100.0.0rho1'
        releaseinfo['basename'] = 'openmpi'
        releaseinfo['build_unix_time'] = 1

        files = ['openmpi-100.0.0rho1.tar.gz', 'openmpi-100.0.0rho1.tar.bz2']

        client = self.test_s3_client("scratch/open-mpi/v100.0/", Existing = True)

        upload_files(client, 'open-mpi-scratch', 'scratch',
                     releaseinfo, files, 'NEVER_PROMPT')
        self.assertEqual(client.get_readcount(), 3,
                         "readcount was %d, expected 3" % (client.get_readcount()))
        self.assertEqual(len(client.get_write_list()), 3,
                         "Unexpected write list length: %s" % str(client.get_write_list()))
        buildinfo = json.loads(client.get_write_stream())
        self.assertEqual(len(buildinfo['files']), 2,
                         'Unexpected files length: %s' % str(buildinfo['files']))


    @mock.patch('os.stat', _test_stat)
    @mock.patch('__main__.__compute_hashes', _test_compute_hashes)
    def test_existing_buildinfo_overlap_fail(self):
        releaseinfo = {}
        releaseinfo['project'] = 'open-mpi'
        releaseinfo['branch'] = 'v100.0'
        releaseinfo['version'] = '100.0.0rho1'
        releaseinfo['basename'] = 'openmpi'
        releaseinfo['build_unix_time'] = 1

        files = ['openmpi-100.0.0rho1.tar.gz', 'openmpi-100.0.0rho1.tar.bz2']

        client = self.test_s3_client("scratch/open-mpi/v100.0/", Existing = True)

        upload_files(client, 'open-mpi-scratch', 'scratch',
                     releaseinfo, files, 'NO_OVERWRITE')
        self.assertEqual(client.get_readcount(), 3,
                         "readcount was %d, expected 3" % (client.get_readcount()))
        self.assertEqual(len(client.get_write_list()), 0,
                         "Unexpected write list length: %s" % str(client.get_write_list()))


if __name__ == '__main__':
    unittest.main()
