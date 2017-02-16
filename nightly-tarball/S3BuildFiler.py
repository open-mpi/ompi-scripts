#!/usr/bin/env python
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import BuildFiler
import unittest
import logging
import boto3
import botocore
import time
import os
import errno
import re


logger = logging.getLogger('Builder.S3BuildFiler')


class S3BuildFiler(BuildFiler.BuildFiler):
    """S3 Implementation of the BuildFiler

    S3 implementation of the BuildFiler.  Assumes that the current
    environment is already setup with the required AWS permissions,
    according to Boto3's credentials search path:
    http://boto3.readthedocs.io/en/latest/guide/configuration.html

    """

    def __init__(self, Bucket, Basename):
        logger.debug("-> creating S3BuildFiler with bucket_name=", Bucket,
                     " base_name=", Basename)
        self._bucket = Bucket
        self._basename = Basename
        self._s3 = boto3.client('s3')


    def download_to_stream(self, filename):
        """Download to stream

        Gets the object at basename/filename and returns as a
        StreamObject, suitable for turning into a string via .read()
        or passing to JSON / YAML constructors.

        """
        logger.debug("-> downloading to stream: " + filename)
        key = self._basename + filename
        try:
            response = self._s3.get_object(Bucket=self._bucket, Key=key)
        except botocore.exceptions.ClientError as e:
            code = e.response['Error']['Code']
            if code == "NoSuchKey" or code == "NoSuchBucket":
                raise IOError(errno.ENOENT, os.strerror(errno.ENOENT), filename)
            else:
                raise
        return response['Body']


    def upload_from_stream(self, filename, data):
        """Upload from a stream

        Puts the stream information in data to an object at
        basename/filename.  Data can be the output of json.dumps() or
        similar.

        """
        logger.debug("-> uploading from stream: " + filename)
        key = self._basename + filename
        try:
            self._s3.put_object(Bucket=self._bucket, Key=key, Body=data)
        except botocore.exceptions.ClientError as e:
            code = e.response['Error']['Code']
            if code == "NoSuchBucket":
                raise IOError(errno.ENOENT, os.strerror(errno.ENOENT), filename)
            else:
                raise


    def download_to_file(self, remote_filename, local_filename):
        """Download to a file

        Download the object at basename/remote_filename to
        local_filename.

        """
        logger.debug("-> downloading to file, remote: " + remote_filename
                     + " local: " + local_filename)
        key = self._basename + remote_filename
        try:
            self._s3.download_file(self._bucket, key, local_filename)
        except botocore.exceptions.ClientError as e:
            code = e.response['Error']['Code']
            if code == "NoSuchKey" or code == "NoSuchBucket" or code == "404":
                raise IOError(errno.ENOENT, os.strerror(errno.ENOENT),
                              remote_filename)
            else:
                raise


    def upload_from_file(self, local_filename, remote_filename):
        """Upload a file

        Upload the local_file to S3 as basename/remote_filename.
        """
        logger.debug("-> uploading from file, remote: " + remote_filename
                     + " local: " + local_filename)
        key = self._basename + remote_filename
        try:
            self._s3.upload_file(local_filename, self._bucket, key)
        except botocore.exceptions.ClientError as e:
            code = e.response['Error']['Code']
            if code == "NoSuchBucket":
                raise IOError(errno.ENOENT, os.strerror(errno.ENOENT),
                              remote_filename)
            else:
                raise


    def delete(self, filename):
        """Delete file

        Delete file on remote path.  Note that S3 delete has much
        eventual consistency, so you may still find the file
        immediately after a delete.  But it will be deleted
        eventually.

        """
        logger.debug("-> deleting file: " + filename)
        key = self._basename + filename
        try:
            self._s3.delete_object(Bucket=self._bucket, Key=key)
        except botocore.exceptions.ClientError as e:
            code = e.response['Error']['Code']
            if code == "NoSuchKey" or code == "NoSuchBucket":
                raise IOError(errno.ENOENT, os.strerror(errno.ENOENT), filename)
            else:
                raise


    def file_search(self, dirname, blob):
        """Search for file blob in dirname directory

        Search for all files in dirname matching blob.  Returns a list
        of filenames that match the search.  This is not the most
        efficient implementation, but there's no great way to search
        S3other than searching the directory and then running a regex
        match.  So this will be rather inefficient in very large
        directories.

        """
        full_prefix = self._basename + dirname
        logger.debug('-> search directory %s, blob %s' % (full_prefix, blob))
        regex = re.sub('\.', '\.', blob)
        regex = re.sub('\*', '.*', regex)
        retval = []
        results = self._s3.list_objects(Bucket=self._bucket, Prefix=full_prefix)
        if not 'Contents' in results:
            return []
        blobs = results['Contents']
        for blob in blobs:
            blobname = blob['Key']
            # BWB: fix me!
            if re.search(regex, blobname) != None:
                short_blobname = re.sub(self._basename, '', blobname)
                retval.append(short_blobname)
        return retval


class S3BuildFilerTest(unittest.TestCase):
    _bucket = "ompi-s3buildfiler-test"
    _basename = ""
    _testtime = str(time.time())

    def test_bad_bucket(self):
        filer = S3BuildFiler("this-is-a-random-bucket", self._basename)
        try:
            filer.download_to_stream("read-only/file-that-should-not-exist.txt")
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_stream_bad_get(self):
        filer = S3BuildFiler(self._bucket, self._basename)
        try:
            filer.download_to_stream("read-only/file-that-should-not-exist.txt")
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_stream_good_get(self):
        filer = S3BuildFiler(self._bucket, self._basename)
        body = filer.download_to_stream("read-only/file-that-should-exist.txt")
        text = body.read()
        self.assertEqual(text, "This is a test!\n", "Broken text:" + text)


    def test_stream_read_write(self):
        filename = "cleaned-nightly/" + self._testtime + "/test-abc.txt"

        filer = S3BuildFiler(self._bucket, self._basename)
        input_string = "I love me some unit tests.\n"
        filer.upload_from_stream(filename, input_string)
        body = filer.download_to_stream(filename)
        output_string = body.read()
        filer.delete(filename)
        self.assertEqual(input_string, output_string,
                         input_string + " != " + output_string)


    def test_file_bad_get(self):
        pathname = "/tmp/test-" + self._testtime + ".txt"

        filer = S3BuildFiler(self._bucket, self._basename)
        try:
            filer.download_to_file("read-only/file-that-should-not-exist.txt",
                                   pathname)
        except IOError as e:
            if e.errno != errno.ENOENT:
                raise
        else:
            self.fail()


    def test_file_good_get(self):
        pathname = "/tmp/test-" + self._testtime + ".txt"

        filer = S3BuildFiler(self._bucket, self._basename)
        filer.download_to_file("read-only/file-that-should-exist.txt",
                               pathname)
        with open(pathname, 'r') as data:
            text=data.read()
        self.assertEqual(text, "This is a test!\n", "Broken text:" + text)


    def test_file_read_write(self):
        remote_filename = "cleaned-nightly/" + self._testtime + "/test-abc.txt"
        pathname = "/tmp/test-" + self._testtime + ".txt"
        input_string = "I love me some unit tests.\n"

        filer = S3BuildFiler(self._bucket, self._basename)
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
