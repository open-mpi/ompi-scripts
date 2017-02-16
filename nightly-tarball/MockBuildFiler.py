#!/usr/bin/env python
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow

import BuildFiler
import unittest
import logging
import time
import os
import shutil
import tempfile
import errno
import glob


logger = logging.getLogger('Builder.MockBuildFiler')


class MockBuildFiler(BuildFiler.BuildFiler):
    """Mock BuildFiler

    Used for unit tests.  Use with care.  Files are stored in a temp
    directory unique to the instance of MockBuildFiler and destroyed
    when the instance is destroyed.

    """

    def __init__(self, basename=None, clean_on_delete=True):
        logger.debug("-> creating LocalBuildFiler")
        testtime = str(time.time())
        self._stream_map = { }
        self._file_map = { }
        if basename == None:
            self._basename = tempfile.mkdtemp()
        else:
            self._basename = os.path.expandvars(basename)
        self._clean_on_delete = clean_on_delete


    # Yes, I know, del is evil.  But it's actually what I want here.
    # Don't really care about garbage collection (I think)
    def __del__(self):
        if self._clean_on_delete:
            logger.debug("-> Cleaning tree %s", self._basename)
            shutil.rmtree(self._basename)


    def download_to_stream(self, filename):
        """Download to stream

        Gets the object at basename/filename and returns as a
        StreamObject, suitable for turning into a string via .read()
        or passing to JSON / YAML constructors.

        """
        logger.debug("-> downloading to stream: " + filename)
        pathname = os.path.join(self._basename, filename)
        return open(pathname, "r")


    def upload_from_stream(self, filename, data):
        """Upload from a stream

        Puts the stream information in data to an object at
        basename/filename.  Data can be the output of json.dumps() or
        similar.

        """
        logger.debug("-> uploading from stream: " + filename)
        pathname = os.path.join(self._basename, filename)
        dirname = os.path.dirname(pathname)
        if not os.access(dirname, os.F_OK):
            os.makedirs(dirname)
        with open(pathname, "w") as text_file:
            text_file.write(data)


    def download_to_file(self, remote_filename, local_filename):
        """Download to a file

        Download the object at basename/remote_filename to
        local_filename.  like delete(), this file is provided mainly
        for unit testing.

        """
        logger.debug("-> downloading to file, remote: " + remote_filename
                     + " local: " + local_filename)
        remote_pathname = os.path.join(self._basename, remote_filename)
        shutil.copyfile(remote_pathname, local_filename)


    def upload_from_file(self, local_filename, remote_filename):
        """Upload a file

        Upload the local_file to S3 as basename/remote_filename.
        """
        logger.debug("-> uploading from file, remote: " + remote_filename
                     + " local: " + local_filename)
        remote_pathname = os.path.join(self._basename, remote_filename)
        dirname = os.path.dirname(remote_pathname)
        if not os.access(dirname, os.F_OK):
            os.makedirs(dirname)
        shutil.copyfile(local_filename, remote_pathname)


    def delete(self, filename):
        """Delete file

        This is not necessary before uploading a build history file
        over an existing file, but is provided mainly for unit
        testing.

        """
        logger.debug("-> deleting build history " + filename)
        pathname = os.path.join(self._basename, filename)
        os.remove(pathname)


    def file_search(self, dirname, blob):
        """Search for file blob in dirname directory

        Search for all files in dirname matching blob.  Returns a list
        of filenames that match the search.
        """
        remote_pathname = os.path.join(self._basename, dirname, blob)
        retval = glob.glob(remote_pathname)
        logger.debug("retval: %s" % (str(retval)))
        return retval


class MockBuildFilerTest(unittest.TestCase):
    def setUp(self):
        self._tempdir = tempfile.mkdtemp()


    def tearDown(self):
        shutil.rmtree(self._tempdir)
        pass


    def test_destructor(self):
        filer = MockBuildFiler()


    def test_stream_bad_get(self):
        filer = MockBuildFiler()
        try:
            filer.download_to_stream("file-that-should-not-exist.txt")
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_stream_read_write(self):
        filename = "foo/test-abc.txt"
        input_string = "I love me some unit tests.\n"
        filer = MockBuildFiler()

        filer.upload_from_stream(filename, input_string)

        body = filer.download_to_stream(filename)
        output_string = body.read()

        filer.delete(filename)

        self.assertEqual(input_string, output_string,
                         input_string + " != " + output_string)

        try:
            filer.download_to_stream(filename)
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_file_bad_get(self):
        pathname = os.path.join(self._tempdir, "foobar.txt")

        filer = MockBuildFiler()
        try:
            filer.download_to_file("read-only/file-that-should-not-exist.txt",
                                   pathname)
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_file_read_write(self):
        remote_filename = "foo/test-abc.txt"
        pathname = os.path.join(self._tempdir, "foobar.txt")
        input_string = "I love me some unit tests.\n"
        filer = MockBuildFiler()

        with open(pathname, "w") as text_file:
            text_file.write(input_string)
        filer.upload_from_file(pathname, remote_filename)

        os.remove(pathname)

        try:
            body = filer.download_to_stream(remote_filename)
        except:
            filer.delete(remote_filename)
            raise

        try:
            filer.download_to_file(remote_filename, pathname)
        except:
            filer.delete(remote_filename)
            raise

        filer.delete(remote_filename)

        output_string = body.read()
        self.assertEqual(input_string, output_string,
                         input_string + " != " + output_string)

        with open(pathname, 'r') as data:
            text=data.read()
        self.assertEqual(text, output_string,
                         input_string + " != " + text)


if __name__ == '__main__':
    unittest.main()
