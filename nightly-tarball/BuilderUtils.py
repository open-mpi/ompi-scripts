#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#

import subprocess
import logging
import os
import fileinput


def logged_call(args,
                wrapper_args=None,
                log_file=None,
                err_log_len=20,
                env=None):
    """Wrapper around check_call to log output

    Wrap around check_call to capture stdout and stderr and save them
    in log_file (or command-output.txt) with the given environment.
    The amount of data saved from the capture and emitted to the log
    stream is dependent on the status of the logging system.

    """
    logger = logging.getLogger('Builder.BuildUtils')

    base_command = os.path.basename(args[0])

    call_args = []
    if wrapper_args != None:
        call_args.extend(wrapper_args)
    call_args.extend(args)

    logger.debug('Executing: %s' % (str(call_args)))
    logger.debug('cwd: %s' % (str(os.getcwd())))

    if log_file != None:
        stdout_file = log_file
    else:
        stdout_file = '%s-output.txt' % (base_command)
    stdout = open(stdout_file, 'w')

    if env != None and 'CALL_DEBUG' in env:
        return

    try:
        subprocess.check_call(call_args, stdout=stdout, stderr=subprocess.STDOUT, env=env)
    except:
        stdout.close()
        logger.warn("Exceuting %s failed:" % (base_command))
        if logger.getEffectiveLevel() == logging.DEBUG:
            # caller wanted all output anyway (for debug), so give
            # them everything
            for line in fileinput.input(stdout_file):
                logger.warn(line.rstrip('\n'))
        else:
            # caller wasn't going to get success output, so only give
            # the last err_log_len lines to keep emails rationally
            # sized
            output = open(stdout_file, 'r')
            lines = output.readlines()
            for line in lines[-err_log_len:]:
                logger.warn(line.rstrip('\n'))
        raise
    else:
        stdout.close()
        if logger.getEffectiveLevel() == logging.DEBUG:
            for line in fileinput.input(stdout_file):
                logger.debug(line.rstrip('\n'))
