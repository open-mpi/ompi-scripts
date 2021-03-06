#!/usr/bin/env python3

import logging

from git import Repo

# Helper module for out git commit checkers
import checker

#--------------------------------------

result_messages = {
    'all good'  : { 'message' : 'All commits have good email addresses.  Yay!',
                    'status'  : 0, },
    'some good' : { 'message' : 'Some commits have bad email addresses',
                    'status'  : 1, },
    'none good' : { 'message' : 'No commits have good email addresses',
                    'status'  : 1, },
}

#--------------------------------------

def _email_address_checker(commit, results):
    for type, email in (('author', commit.author.email),
                        ('committer', commit.committer.email)):
        # Check for typical bad email addresses
        if ('root@' in email or
            'localhost' in email or
            'localdomain' in email):
            logging.error("Commit %s has an unspecific %s email address: %s" % (commit.hexsha, type, email))
            results['bad'] += 1

        else:
            logging.info("Commit %s has a good %s email address: %s" % (commit.hexsha, type, email))
            results['good'] += 1

#--------------------------------------
# Call the main engine
checker.run('Commit email address checker', _email_address_checker,
            result_messages)
