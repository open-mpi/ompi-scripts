#!/usr/bin/env python3

import re
import logging

from git import Repo

# Helper module for out git commit checkers
import checker

#--------------------------------------

result_messages = {
    'all good'  : { 'message' : 'All commits signed off.  Yay!',
                    'status'  : 0, },
    'some good' : { 'message' : 'Some commits not signed off',
                    'status'  : 1, },
    'none good' : { 'message' : 'No commits are signed off',
                    'status'  : 1, },
}

_prog = re.compile("^Signed-off-by: (.+?) <(.+)>$",
                   flags=re.MULTILINE)

#--------------------------------------

def _signed_off_by_checker(commit, results):
    # Ignore merge commits
    if len(commit.parents) > 1:
        logging.info("Merge commit %s skipped" % (commit.hexsha))
        return

    match = _prog.search(commit.message)
    if not match:
        results['bad'] += 1
        logging.error("Commit %s not signed off" % (commit.hexsha))

    else:
        results['good'] += 1
        name = match.group(1)
        addr = match.group(2)
        logging.info("Commit %s properly signed off: %s <%s>" % (commit.hexsha, name, addr))

#--------------------------------------
# Call the main engine
checker.run('Signed-off-by checker', _signed_off_by_checker,
            result_messages)
