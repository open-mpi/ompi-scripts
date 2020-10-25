# Helper module used by the signed-off-by checker and email address
# checker.
#
# This module handles all the common code stuff between the various
# checkers.

import os
import sys
import logging

from git import Repo

def run(checker_name, per_commit_callback, result_messages):
    logging.basicConfig(level=logging.INFO, stream=sys.stderr)
    logging.info(f"{checker_name} starting")

    #--------------------------------------
    # These env variables come in from Jenkins
    # See https://jenkins.open-mpi.org/jenkins/env-vars.html/
    try:
        base_branch = os.environ['CHANGE_BRANCH']
        pr_branch   = os.environ['BRANCH_NAME']
        clone_dir   = os.environ['GIT_CHECKOUT_DIR']
    except Exception as e:
        logging.error(f"Cannot find the expected Jenkins environment variable: {e}")
        logging.error("Aborting in despair")
        exit(1)

    logging.info(f"Git clone:   {clone_dir}")
    logging.info(f"PR branch:   {pr_branch}")
    logging.info(f"Base branch: {base_branch}")

    #--------------------------------------
    # Make a python object representing the Git repo
    repo       = Repo(clone_dir)
    merge_base = repo.commit(base_branch)
    logging.info(f"Merge base:  {merge_base.hexsha}")

    #--------------------------------------
    # Iterate from the HEAD of the PR branch down to the merge base with
    # the base branch.
    results = {
        'good' : 0,
        'bad'  : 0,
    }

    for commit in repo.iter_commits(repo.head.ref):
        if commit.binsha == merge_base.binsha:
            logging.info(f"Found the merge base {commit.hexsha}: we're done")
            break

        per_commit_callback(commit, results)

    #--------------------------------------
    # Analyze what happened
    if results['good'] == 0 and results['bad'] == 0:
        msg    = 'No commits -- nothing to do'
        status = 0
    elif results['good'] > 0 and results['bad'] == 0:
        msg    = result_messages['all good']['message']
        status = result_messages['all good']['status']
    elif results['good'] > 0 and results['bad'] > 0:
        msg    = result_messages['some good']['message']
        status = result_messages['some good']['status']
    else:
        msg    = result_messages['none good']['message']
        status = result_messages['none good']['status']

    print(msg)
    exit(status)
