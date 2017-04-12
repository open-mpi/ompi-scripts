#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import Builder
import S3BuildFiler
import os
import re
import shutil
import tempfile


class OMPIBuilder(Builder.Builder):
    """Wrapper for some current oddities in OMPI project build files

    Currently, the create_tarball scripts have some, but not all, of
    the functionality needed to avoid too much special casing of the
    build system.  We're going to fix up the create_tarball scripts in
    all the branches so that this code (possibly with the exception of
    the run_with_autotools bits) goes away, so put it here rather in
    the Builder class that will be used long term...

    """

    def update_version_file(self):
        """Update version file in the OMPI/PMIx way

        Rewrite VERSION file, subsituting tarball_version and rep_rev
        based on computed values.
        """
        branch = self._current_build['branch']
        build_time = self._current_build['build_time']
        githash = self._current_build['revision']
        version_file = os.path.join(self._current_build['source_tree'], 'VERSION')

        self._current_build['version_string'] = '%s-%s-%s' % (branch, build_time, githash)
        self._logger.debug('version_string: %s' % (self._current_build['version_string']))

        # sed in the new tarball_version= and repo_rev= lines in the VERSION file
        tarball_version_pattern = re.compile(r'^tarball_version=.*')
        repo_rev_pattern = re.compile(r'^rep_rev=.*')
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp_file:
            with open(version_file) as src_file:
                for line in src_file:
                    line = tarball_version_pattern.sub('tarball_version=%s' %
                                                       (self._current_build['version_string']), line)
                    line = repo_rev_pattern.sub('repo_rev=%s' % (githash), line)
                    tmp_file.write(line)
        shutil.copystat(version_file, tmp_file.name)
        shutil.move(tmp_file.name, version_file)


    def build(self):
        """Run OMPI-custom build step

        Call autogen ; configure ; make distcheck, but with the right
        $USER.  It would be more awesome to use the make_dist_tarball
        script that is part of OMPI / PMIx, but it undoes any VERSION
        file changes we did in the update_version step.  So do
        everything here instead until we can update the
        make_dist_tarball scripts.
        """
        # currently can't use the build script because it always
        # rewrites the VERSION file.  Need to fix that, and then can
        # kill off this function and use the tarball_builder.
        branch_name = self._current_build['branch_name']
        source_tree = self._current_build['source_tree']
        cwd = os.getcwd()
        os.chdir(source_tree)
        try:
            # lie about our username in $USER so that autogen will skip all
            # .ompi_ignore'ed directories (i.e., so that we won't get
            # .ompi_unignore'ed)
            child_env = os.environ.copy()
            child_env['USER'] = self._config['project_very_short_name'] + 'builder'

            self.call([self._config['autogen']], build_call=True, env=child_env)
            self.call(['./configure'], build_call=True, env=child_env)

            # Do make distcheck (which will invoke config/distscript.csh to set
            # the right values in VERSION).  distcheck does many things; we need
            # to ensure it doesn't pick up any other installs via LD_LIBRARY_PATH.
            # It may be a bit Draconian to totally clean LD_LIBRARY_PATH (i.e., we
            # may need something in there), but at least in the current building
            # setup, we don't.  But be advised that this may need to change in the
            # future...
            child_env['LD_LIBRARY_PATH'] = ''
            self.call(['make', 'distcheck'], build_call=True, env=child_env)
        finally:
            os.chdir(cwd)


    def call(self, args, log_name=None, build_call=False, env=None):
        """OMPI wrapper around call

        Add wrapper to properly set up autotools for OMPI/PMIx/hwloc,
        then call the base Builder.call()
        """
        if build_call:
            run_with_autotools = os.path.join(self._config['builder_tools'], 'run-with-autotools.sh')
            full_args = [run_with_autotools, 'autotools/%s-%s' %
                         (self._config['project_very_short_name'], self._current_build['branch_name'])]
            full_args.extend(args)
            if log_name == None:
                log_name = os.path.basename(args[0])
        else:
            full_args = args
        super(OMPIBuilder, self).call(full_args, log_name, env=env)


    def publish_build_artifacts(self):
        """OMPI-specific publish

        Do all the base class publish_build_artifacts() to push into
        S3 and then also do the legacy push into the web server
        filesystem.  This will be removed once the code on the web
        server has been updated to pull from S3 and wrappers are in
        place to make sure scripts looking for latest_snapshot.txt and
        the build artifacts (like MTT) are tested / updated to use the
        new URLs.
        """
        # first, do all the normal bits
        super(OMPIBuilder, self).publish_build_artifacts()
        # second, do all the legacy bits to continue updating the web
        # server directly until we fix the web server...

        child_env = os.environ.copy()
        # child_env['CALL_DEBUG'] = '1'

        # first, expire out builds
        self.call(['ssh', '-p', '2222', self._config['legacy_file_host'],
                   'git/ompi/contrib/build-server/remove-old.pl 7 '
                   + self._config['legacy_target_prefix']
                   + self._current_build['branch_name']],
                  log_name='ssh_remove_old', env=child_env)

        # second, copy build artifacts
        for build in self._current_build['artifacts']:
            local_filename = os.path.join(self._current_build['source_tree'],
                                          build)
            remote_filename = os.path.join(self._config['legacy_target_prefix'],
                                           self._current_build['branch_name'],
                                           build)
            self._logger.debug("Legacy publishing file %s (local: %s, remote: %s)" %
                               (build, local_filename, remote_filename))
            self.call(['scp', '-P', '2222', local_filename,
                       self._config['legacy_file_host'] + ':' + remote_filename],
                      log_name='scp_' + build, env=child_env)

        # create latest_snapshot.txt on remote server
        local_filename = os.path.join(self._current_build['build_root'], 'latest_snapshot.txt')
        remote_filename = os.path.join(self._config['legacy_target_prefix'],
                                       self._current_build['branch_name'],
                                       'latest_snapshot.txt')
        with open(local_filename, "w") as tmp:
            version_string = self._current_build['version_string'] + '\n'
            tmp.write(version_string)
        self.call(['scp', '-P', '2222', local_filename,
                   self._config['legacy_file_host'] + ':' + remote_filename],
                  log_name='scp_snapshot.txt', env=child_env)

        # generate checksums
        self.call(['ssh', '-p', '2222', 'ompiteam@192.185.39.252',
                   'cd ' + os.path.join(self._config['legacy_target_prefix'],
                                        self._current_build['branch_name'])
                   + ' && md5sum ' + self._config['project_short_name'] + '* > md5sums.txt'],
                  log_name='remote_md5sum', env=child_env)
        self.call(['ssh', '-p', '2222', 'ompiteam@192.185.39.252',
                   'cd ' + os.path.join(self._config['legacy_target_prefix'],
                                        self._current_build['branch_name'])
                   + ' && sha1sum ' + self._config['project_short_name'] + '-* > sha1sums.txt'],
                  log_name='remote_sha1sum', env=child_env)
