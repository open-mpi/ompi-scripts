#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import logging


logger = logging.getLogger('Builder.S3BuildFiler')


class BuildFiler(object):
    """Abstraction for interacting with storage (S3, local, etc.)

    Base class for the BuildFiler.  You probably don't want to use
    this implementation, as it's pretty much an abstract base class.
    Use the S3BuildFiler.

    """

    def download_to_stream(self, filename):
        """Download to stream

        Gets the object at basename/filename and returns as a
        StreamObject, suitable for turning into a string via .read()
        or passing to JSON / YAML constructors.

        """
        raise NotImplementedError


    def upload_from_stream(self, filename, data):
        """Upload from a stream

        Puts the stream information in data to an object at
        basename/filename.  Data can be the output of json.dumps() or
        similar.

        """
        raise NotImplementedError


    def download_to_file(self, remote_filename, local_filename):
        """Download to a file

        Download the object at basename/remote_filename to
        local_filename.

        """
        raise NotImplementedError


    def upload_from_file(self, local_filename, remote_filename):
        """Upload a file

        Upload the local_file to the remote filename.
        """
        raise NotImplementedError


    def delete(self, filename):
        """Delete file"""
        raise NotImplementedError


    def file_search(self, dirname, blob):
        """Search for file blob in dirname directory

        Search for all files in dirname matching blob.  Returns a list
        of filenames that match the search.
        """
        raise NotImplementedError
