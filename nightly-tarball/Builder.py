#
# Copyright (c) 2017-2019 Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
# Copyright (c) 2081 Cisco Systems, Inc.  All rights reserved.
#
# Additional copyrights may follow
#

import argparse
import logging
import os
import json
import hashlib
import time
import datetime
import shutil
import subprocess
import fileinput
import Coverity
import BuilderUtils
import smtplib
from email.mime.text import MIMEText
from git import Repo, exc
from enum import Enum


def compute_hashes(filename):
    """Helper function to compute MD5 and SHA1 hashes"""
    retval = {}
    md5 = hashlib.md5()
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    with open(filename, 'rb') as f:
        while True:
            data = f.read(64 * 1024)
            if not data:
                break
            md5.update(data)
            sha1.update(data)
            sha256.update(data)
    retval['md5'] = md5.hexdigest()
    retval['sha1'] = sha1.hexdigest()
    retval['sha256'] = sha256.hexdigest()
    return retval


# a note on paths used in the Builder...
#
# config['scratch_path']	: <scratch_path>
# config['project_path']	: <scratch_path>/<project_short_name>
# current_build['build_root']	: <scratch_path>/<project_short_name>/<branch>-<build_time>/
# current_build['source_tree']	: <scratch_path>/<project_short_name>/<branch>-<build_time>/[repo]
class Builder(object):
    """Build one or more branches of a git repo

    Core class of a nightly build system (possibly to be extended into
    a release build system as well).  User callable functions are the
    object constructor as well as run()

    """

    _base_options = { 'email_log_level' : 'INFO',
                      'console_log_level' : 'CRITICAL',
                      'scratch_path' : '${TMPDIR}' }

    class BuildResult(Enum) :
        SUCCESS = 1
        FAILED = 2
        SKIPPED = 3


    def __init__(self, config, filer):
        """Create a Builder object

        Create a builder object, which will build most simple
        projects.  Projects with more complicated needs will likely
        want to override the add_arguments(), call(), and
        find_build_artifacts() functions.  In the case of
        add_arguments() and call(), it is highly recommended
        that functions provided by a subclass of Builder call into the
        Builder functions to do the actual work.

        """
        self._logger = None
        self._current_build = {}
        self._config = self._base_options.copy()
        self._config.update(config)
        self._filer = filer
        self._parser = argparse.ArgumentParser(description='Nightly build script for Open MPI related projects')
        self.add_arguments(self._parser)
        # copy arguments into options, assuming they were specified
        for key, value in vars(self._parser.parse_args()).items():
            if not value == None:
                self._config[key] = value
        # special case hack...  expand out scratch_path
        self._config['scratch_path'] = os.path.expandvars(self._config['scratch_path'])
        self._config['project_path'] = os.path.join(self._config['scratch_path'],
                                                    self._config['project_short_name'])
        self._config['builder_tools'] = os.path.dirname(os.path.realpath(__file__))

        # special hack for OMPI being inconsistent in short names....
        if not 'project_very_short_name' in self._config:
            self._config['project_very_short_name'] = self._config['project_short_name']

        if not os.path.exists(self._config['scratch_path']):
            os.makedirs(self._config['scratch_path'])

        # logging initialization.  Logging will work after this point.
        self._logger = logging.getLogger("Builder")
        # while we use the handler levels to limit output, the
        # effective level is the lowest of the handlers and the base
        # logger output.  There's a switch in the output function of
        # the call() utility to dump all output on debug, so be a
        # little careful about setting debug level output on the
        # logger to avoid that path being activated all the time.
        if self._config['console_log_level'] == 'DEBUG' or self._config['email_log_level'] == 'DEBUG':
            self._logger.setLevel(logging.DEBUG)
        else:
            self._logger.setLevel(logging.INFO)

        ch = logging.StreamHandler()
        ch.setLevel(self._config['console_log_level'])
        ch.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))
        self._logger.addHandler(ch)

        self._config['log_file'] = os.path.join(self._config['scratch_path'],
                                                'builder-output-%d.log' % (int(time.time())))

        self._fh = logging.FileHandler(self._config['log_file'], 'w')
        self._fh.setLevel(self._config['email_log_level'])
        self._fh.setFormatter(logging.Formatter('%(message)s'))
        self._logger.addHandler(self._fh)


    def __del__(self):
        # delete the log file, since it doesn't auto-clean (we're only
        # using it for email, so no one will miss it)
        if self._logger != None:
            self._logger.removeHandler(self._fh)
            self._fh.close()
            os.remove(self._config['log_file'])


    def add_arguments(self, parser):
        """Add options for command line arguments

        Called during initialization of the class in order to add any
        required arguments to the options parser.  Builder classes can
        provide their own add_arguments call, but should call the base
        add_arguments() in order to get the base set of options added
        to the parser.

        """
        self._parser.add_argument('--console-log-level',
                                  help='Console Log level (default: CRITICAL).', type=str,
                                  choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'])
        self._parser.add_argument('--email-log-level',
                                  help='Email Log level (default: INFO).', type=str,
                                  choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'])
        self._parser.add_argument('--scratch-path',
                                  help='Directory to use as base of build tree.',
                                  type=str)


    def run(self):
        """Do all the real work of the Builder

        Other than __init__(), this is the real API for the Builder
        class.  This function will execute every build described by
        the configuration passed to __init__().  Internally, it uses a
        helper function run_single_build() to execute each build.  The
        only real logic in this function (other than iterating over
        keys and calling single_build) is to write the summary output
        / send emails).

        """
        self._logger.info("Branches: %s", str(self._config['branches'].keys()))
        good_builds = []
        failed_builds = []
        skipped_builds = []

        for branch_name in self._config['branches']:
            try:
                result = self.run_single_build(branch_name)
                if result == Builder.BuildResult.SUCCESS:
                    good_builds.append(branch_name)
                elif result == Builder.BuildResult.FAILED:
                    failed_builds.append(branch_name)
                elif result == Builder.BuildResult.SKIPPED:
                    skipped_builds.append(branch_name)
            except Exception as e:
                self._logger.error("run_single_build(%s) threw exception %s: %s" %
                                   (branch_name, str(type(e)), str(e)))
                failed_builds.append(branch_name)
                # if run_single_build throws an exception, we should
                # not continue trying to run, but should just do the
                # cleanup work
                break

        # Generate results output for email
        body = "Successful builds: %s\n" % (str(good_builds))
        body += "Skipped builds: %s\n" % (str(skipped_builds))
        body += "Failed builds: %s\n" % (str(failed_builds))
        if len(failed_builds) > 0:
            subject = "%s nightly build: FAILURE" % (self._config['project_name'])
        else:
            subject = "%s nightly build: SUCCESS" % (self._config['project_name'])
        body += "\n=== Build output ===\n\n"
        body += open(self._config['log_file'], 'r').read()
        body += "\nYour friendly daemon,\nCyrador\n"

        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = self._config['email_from']
        msg['To'] = self._config['email_dest']

        s = smtplib.SMTP('localhost')
        s.sendmail(self._config['email_from'], [self._config['email_dest']], msg.as_string())
        s.quit()


    def run_single_build(self, branch_name):
        """Run a single branch build

        All the logic required to run a single build.  This function
        should not raise an exception unless all follow-on builds
        should be skipped.

        """
        self._logger.info("\nStarting build for " + branch_name)
        self._current_build = { "status" : 0,
                                "branch_name" : branch_name }
        retval = Builder.BuildResult.SUCCESS

        remote_repository = self._config['repository']

        now = time.time()
        self._current_build['build_unix_time'] = int(now)
        self._current_build['build_time'] = self.generate_build_time(now)
        build_root = os.path.join(self._config['project_path'],
                                  branch_name + "-" + self._current_build['build_time'])
        source_tree = os.path.join(build_root,
                                   os.path.basename(remote_repository))

        self._current_build['remote_repository'] = remote_repository
        self._current_build['build_root'] = build_root
        self._current_build['source_tree'] = source_tree
        self._current_build['branch'] = branch_name

        build_history = self.get_build_history()
        if len(build_history) > 0:
            # this is really kind of awful, but build_history keys are
            # unix timestamps of the build.  Find the last timestamp,
            # and that's the last build.  Then look at the revision to
            # get the revision id of that build.
            last_version = build_history[sorted(build_history.keys())[-1:][0]]['revision']
        else:
            last_version = ''

        self.prepare_source_tree()
        try:
            if last_version == self._current_build['revision']:
                self._logger.info("Build for revision %s already exists, skipping.",
                                  self._current_build['revision'])
                retval = Builder.BuildResult.SKIPPED
            else:
                self._logger.info("Found new revision %s",
                                  self._current_build['revision'])

                self.update_version_file()
                self.build()
                self.find_build_artifacts()
                if ('coverity' in self._config['branches'][branch_name]
                    and self._config['branches'][branch_name]['coverity']
                    and len(self._current_build['artifacts']) > 0):
                    try:
                        Coverity.run_coverity(self._logger,
                                              self._current_build['build_root'],
                                              os.path.join(self._current_build['source_tree'],
                                                           next(iter(self._current_build['artifacts'].keys()))),
                                              self._config['coverity'])
                    except Exception as e:
                        self._logger.error("ERROR: Coverity submission failed: %s"
                                           % (str(e)))
                    else:
                        self._logger.info("Successfully submitted Coverity build")
                self.publish_build_artifacts()
                self._logger.info("%s build of revision %s completed successfully" %
                                  (branch_name, self._current_build['revision']))
        except Exception as e:
            self._logger.error("FAILURE: %s: %s"
                               % (str(type(e)), str(e)))
            self.publish_failed_build()
            retval = Builder.BuildResult.FAILED
        finally:
            self.cleanup()
            self.remote_cleanup(build_history)
        return retval


    def generate_build_time(self, build_unix_time):
        """Helper function to format time strings from unix time"""
        return datetime.datetime.utcfromtimestamp(build_unix_time).strftime("%Y%m%d%H%M")


    def generate_build_history_filename(self, branch_name, build_unix_time, revision):
        """Helper function to build filename

        The build history file represents a single build, and has to
        have an agreed-upon naming convention between both the builder
        script and the web pages that will consume the output.
        Override if build-<branch name>-<unix timestamp of build>.json
        is not sufficient for your project.

        """
        build_time = self.generate_build_time(build_unix_time)
        return os.path.join(self._config['branches'][branch_name]['output_location'],
                            "build-%s-%s-%s-%s.json" % (self._config['project_short_name'],
                                                        branch_name,
                                                        build_time,
                                                        revision))


    def get_build_history(self):
        """Helper function to list all known builds for the current branch

        Pull all known builds from the remote storage and return an
        array of the build history objects for the current branch.
        Returns an empty list if there are no known builds for the
        current branch.

        """
        branch_name = self._current_build['branch_name']
        dirname = self._config['branches'][branch_name]['output_location']
        builds = self._filer.file_search(dirname, "build-*.json")
        build_history = {}
        for build in builds:
            self._logger.debug("looking at data file %s" % build)
            stream = self._filer.download_to_stream(build)
            data = json.load(stream)
            if not 'build_unix_time' in data:
                continue
            if not 'branch' in data:
                continue
            data_build_unix_time = data['build_unix_time']
            data_branch_name = data['branch']
            if data_branch_name == branch_name:
                build_history[data_build_unix_time] = data
        return build_history


    def prepare_source_tree(self):
        """Build a local source tree for the current branch

        Builds the current tree, including building all parent
        directories, checks out the source for the current branch, and
        sets _current_build['revision'] to the revision of the HEAD
        for the current branch.

        """
        branch_name = self._current_build['branch_name']
        remote_repository = self._current_build['remote_repository']
        source_tree = self._current_build['source_tree']
        branch = self._current_build['branch']

        # assume that the build tree doesn't exist.  Makedirs will
        # throw an exception if it does.
        self._logger.debug("Making build tree: " + os.path.dirname(source_tree))
        os.makedirs(os.path.dirname(source_tree))

        # get an up-to-date git repository
        self._logger.debug("Cloning from " + remote_repository)
        repo = Repo.clone_from(remote_repository, source_tree)

        # switch to the right branch and reset the HEAD to be
        # origin/<branch>/HEAD
        self._logger.debug("Switching to branch: " + branch)
        if not branch in repo.heads:
            # TODO: Can we avoid calling into repo.git here?
            repo.git.checkout('origin/' + branch, b=branch)
        repo.head.reference = repo.refs['origin/' + branch]

        # And pull in all the right submodules
        repo.submodule_update(recursive = True)

        # wish I could figure out how to do this without resorting to
        # shelling out to git :/
        self._current_build['revision'] = repo.git.rev_parse(repo.head.object.hexsha, short=7)


    def update_version_file(self):
        """Hook to update version file if needed before the actual build step.

        Most projects have custom methods of updating the version used
        by the build process before making a nightly tarball (so that
        different revisions are evident by the tarball name / build
        version).  Projects should provide a customized version of
        this function if necessary.  Default action is to do
        nothing.

        """
        pass


    def build(self):
        """Execute building the tarball.

        Most projects have a helper script for building tarballs.  If
        the key 'tarball_builder' is present in the config, this
        function will execute the tarball_builder.  Otherwise, it will
        run autoreconf -if; ./configure ; make distcheck.

        """
        branch_name = self._current_build['branch_name']
        source_tree = self._current_build['source_tree']
        cwd = os.getcwd()
        os.chdir(source_tree)
        try:
            if 'tarball_builder' in self._config:
                self.call(self._config['tarball_builder'], build_call=True)
            else:
                self.call(["autoreconf", "-if"], build_call=True)
                self.call(["./configure"], build_call=True)
                self.call(["make", "distcheck"], build_call=True)
        finally:
            os.chdir(cwd)


    def call(self, args, log_name=None, build_call=False, env=None):
        """Modify shell executable string before calling

        Some projects (like Open MPI) use shell modules to configure
        the environment properly for a build.  The easiest way to
        support that use case is a shell wrapper function that
        properly configures the environment.  This function provides a
        hook which can be used to add the shell wrapper function into
        the call arguments, resulting in the build system having the
        right environment at execution time.  The default is to call
        args directly.

        """
        if log_name == None:
            log_file = args[0]
        else:
            log_file = log_name
        log_file=os.path.join(self._current_build['build_root'], log_file + "-output.txt")
        BuilderUtils.logged_call(args, log_file=log_file, env=env)


    def find_build_artifacts(self):
        """Pick up any build artifacts from the build step

        Returns a list of file names relative to source_tree of the
        build artifacts from the build step.  The
        Builder.find_build_artifacts() implementation will search for
        any .tar.gz and .tar.bz2 files in the top level of the build
        tree.  Overload if the project builder can be more
        specific.

        """
        self._current_build['artifacts'] = {}
        source_tree = self._current_build['source_tree']
        for file in os.listdir(source_tree):
            if file.endswith(".tar.gz") or file.endswith(".tar.bz2"):
                filename = os.path.join(source_tree, file)
                info = os.stat(filename)
                hashes = compute_hashes(filename)
                self._current_build['artifacts'][file] = {}
                self._current_build['artifacts'][file]['sha1'] = hashes['sha1']
                self._current_build['artifacts'][file]['sha256'] = hashes['sha256']
                self._current_build['artifacts'][file]['md5'] = hashes['md5']
                self._current_build['artifacts'][file]['size'] = info.st_size
                self._logger.debug("Found artifact %s, size: %d, md5: %s, sha1: %s sha256: %s"
                                   % (file, info.st_size, hashes['md5'], hashes['sha1'], hashes['sha256']))


    def publish_build_artifacts(self):
        """Publish any successful build artifacts

        Publish any build artifacts found by find_build_artifacts and
        create / publish the build history blob for the artifacts.
        This function also creates the "latest_snapshot.txt" file,
        on the assumption that the current build is, in fact, the latest.

        """
        branch_name = self._current_build['branch_name']

        build_data = {}
        build_data['branch'] = self._current_build['branch']
        build_data['valid'] = True
        build_data['revision'] = self._current_build['revision']
        build_data['build_unix_time'] = self._current_build['build_unix_time']
        build_data['delete_on'] = 0
        build_data['files'] = {}

        for build in self._current_build['artifacts']:
            local_filename = os.path.join(self._current_build['source_tree'],
                                          build)
            remote_filename = os.path.join(self._config['branches'][branch_name]['output_location'],
                                           build)
            self._logger.debug("Publishing file %s (local: %s, remote: %s)" %
                               (build, local_filename, remote_filename))
            self._filer.upload_from_file(local_filename, remote_filename)
            build_data['files'][build] = self._current_build['artifacts'][build]

        datafile = self.generate_build_history_filename(self._current_build['branch_name'],
                                                        self._current_build['build_unix_time'],
                                                        self._current_build['revision'])
        self._filer.upload_from_stream(datafile, json.dumps(build_data), {'Cache-Control' : 'max-age=600'})

        latest_filename = os.path.join(self._config['branches'][branch_name]['output_location'],
                                       'latest_snapshot.txt')
        version_string = self._current_build['version_string'] + '\n'
        self._filer.upload_from_stream(latest_filename, version_string, {'Cache-Control' : 'max-age=600'} )


    def update_build_history(self, build_history):
        """Update any build histories that need expiring

        Deletion of build histories / artifacts is a two step process.
        First, when there are more config['than max_count'] builds
        found, the oldest N are expired to get under max_count.
        Expired builds are not immediately deleted.  Instead, they
        have their valid field set to false and a delete_on time set
        to 24 hours from now.  This is to give the web front end time
        to see the update and stop publishing the now-expired builds.
        Second, builds with a delete_on time in the past are deleted
        from the remote archive.  This function handles moving builds
        from "valid" to "expired", and remote_cleanup() handles the
        deletion case.

        """
        branch_name = self._current_build['branch_name']

        # set builds past max_count to invalid and set an expiration
        # if one isn't already set.  Note that this isn't quite right,
        # as we'll count already invalid builds against max_count, but
        # unless builds are added to the build_history out of order
        # (which would be an entertaining causality problem), the
        # effect is the same, and this is way less code.
        if 'max_count' in self._config['branches'][branch_name]:
            max_count = self._config['branches'][branch_name]['max_count']
        else:
            max_count = 10
        builds = sorted(build_history[branch_name]['builds'].keys())
        if len(builds) > max_count:
            expire_builds = builds[max_count:]
            for key in expire_builds:
                if not build_history[branch_name]['builds'][key]['valid']:
                    continue
                build_history[branch_name]['builds'][key]['valid'] = False
                build_history[branch_name]['builds'][key]['delete_on'] = 12
                self._logger.debug("Expiring build %s" % (key))


    def publish_failed_build(self):
        """Deal with a failed build

        Builds fail.  It happens to the best of us.  This function is
        called when something in the build failed (any step, from code
        checkout to finding build artifacts).  This function will
        create a tarball of the build directory and publish it so that
        future generations may see what went wrong and learn from our
        mistakes.  After making a tarball of the directory, it uploads
        the tarball to the remote storage and sets
        ._current_build['failed tarball'] to the name (relative to
        ._config['failed_build_prefix'] where the tarball was
        uploaded.

        """
        if not 'failed_build_prefix' in self._config:
            self._logger.warn("failed_build_prefix not set in config; not saving failed build info")
            return

        branch_name = self._current_build['branch_name']
        self._logger.debug("publishing failed build for %s" % (branch_name))
        failed_tarball_name = "%s-%s-%s-failed.tar.gz" % (self._config['project_short_name'],
                                                          branch_name,
                                                          self._current_build['build_time'])
        failed_tarball_path = os.path.join(self._config['project_path'],
                                           failed_tarball_name)
        cwd = os.getcwd()
        os.chdir(self._current_build['build_root'])
        try:
            self.call(["tar", "czf", failed_tarball_path, "."],
                      log_name="failed-tarball-tar")
        finally:
            os.chdir(cwd)
        remote_filename = os.path.join(self._config['failed_build_prefix'],
                                       failed_tarball_name)

        self._filer.upload_from_file(failed_tarball_path, remote_filename)
        os.remove(failed_tarball_path)

        self._logger.warn('Build artifacts available at: %s' %
                          (self._config['failed_build_url'] + remote_filename))


    def cleanup(self):
        """Clean up after ourselves

        If your builder subclass does anything crazy in the previous
        steps, override here.  Otherwise, deleting everything in the
        build directory should be sufficient.

        """
        dirpath = self._config['project_path']
        self._logger.debug("Deleting directory: %s" % (dirpath))
        # deal with "make distcheck"'s stupid permissions.  Exception
        # handling is inside the loop so that we do not skip some
        # files on an error.  os.chmod will throw an error if it
        # tries to follow a dangling symlink.
        for root, dirs, files in os.walk(dirpath):
            for momo in dirs:
                try:
                    os.chmod(os.path.join(root, momo), 0o700)
                except:
                    pass
            for momo in files:
                try:
                    os.chmod(os.path.join(root, momo), 0o700)
                except:
                    pass
        shutil.rmtree(dirpath)


    def remote_cleanup(self, build_history):
        """Clean up old builds on remote storage"""
        now = int(time.time())
        branch_name = self._current_build['branch_name']

        # set builds past max_count to invalid and set an expiration
        # if one isn't already set.  Note that this isn't quite right,
        # as we'll count already invalid builds against max_count, but
        # unless builds are added to the build_history out of order
        # (which would be an entertaining causality problem), the
        # effect is the same, and this is way less code.  Also, this
        # is a little racy as hell, given there's no locking on
        # simultaneous builds, but the worst case should be that the
        # server ends up with a few too many valid builds.
        if 'max_count' in self._config['branches'][branch_name]:
            max_count = self._config['branches'][branch_name]['max_count']
        else:
            max_count = 10
        builds = sorted(build_history.keys())
        if len(builds) > max_count:
            builds = builds[0:len(builds) - max_count]
            for key in builds:
                if not build_history[key]['valid']:
                    continue
                build_history[key]['valid'] = False
                # expire in one day
                build_history[key]['delete_on'] = now + (24 * 60 * 60)
                self._logger.debug("Expiring build %s" % (key))
                filename = self.generate_build_history_filename(build_history[key]['branch'],
                                                                build_history[key]['build_unix_time'],
                                                                build_history[key]['revision'])
                self._filer.upload_from_stream(filename,
                                               json.dumps(build_history[key]), {'Cache-Control' : 'max-age=600'})

        for build in build_history.keys():
            delete_on = build_history[build]['delete_on']
            if delete_on != 0 and delete_on < int(time.time()):
                self._logger.debug("Removing build %s" % (build))
                for name in build_history[build]['files'].keys():
                    dirname = self._config['branches'][branch_name]['output_location']
                    pathname = os.path.join(dirname, name)
                    self._logger.debug("Removing file %s" % (pathname))
                    self._filer.delete(pathname)
                datafile = self.generate_build_history_filename(build_history[build]['branch'],
                                                                build_history[build]['build_unix_time'],
                                                                build_history[build]['revision'])
                self._logger.debug("Removing data file %s" % (datafile))
                self._filer.delete(datafile)

        # as a (maybe temporary?) hack, generate md5sum.txt and
        # sha1sum.txt files for all valid builds.  Do this in
        # remote_cleanup rather than update_build_history so that it
        # gets regenerated whenever files go invalid/removed, rather
        # than just when new builds are created.
        md5sum_string = ''
        sha1sum_string = ''
        for build in build_history.keys():
            if not build_history[build]['valid']:
                continue
            for filename in build_history[build]['files'].keys():
                filedata = build_history[build]['files'][filename]
                md5sum_string += '%s %s\n' % (filedata['md5'], filename)
                sha1sum_string += '%s %s\n' % (filedata['sha1'], filename)
        output_base = self._config['branches'][branch_name]['output_location']
        self._filer.upload_from_stream(os.path.join(output_base, 'md5sums.txt'),
                                       md5sum_string)
        self._filer.upload_from_stream(os.path.join(output_base, 'sha1sums.txt'),
                                       sha1sum_string)
