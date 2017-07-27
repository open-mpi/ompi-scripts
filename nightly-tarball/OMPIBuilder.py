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
