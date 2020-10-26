# Helper module used by the signed-off-by checker and email address
# checker.
#
# This module handles all the common code stuff between the various
# checkers.

import os
import sys
import logging
import argparse

from git import Repo

def run(checker_name, per_commit_callback, result_messages):
    logging.basicConfig(level=logging.INFO, stream=sys.stderr)
    logging.info("%s starting" % (checker_name))

    argparser = argparse.ArgumentParser(description='Per-commit PR checker')
    argparser.add_argument('--status-msg-file',
                           help='File in which to print the GitHub status message',
                           type=str, required=True)
    argparser.add_argument('--gitdir', help='Git directory', type=str,
                           required=True)
    argparser.add_argument('--base-branch', help='Merge base branch name',
                           type=str, required=True)
    argparser.add_argument('--pr-branch', help='PR branch name',
                           type=str, required=True)
    args = argparser.parse_args()
    args_dict = vars(args)

    base_branch = args_dict['base_branch']
    pr_branch   = args_dict['pr_branch']
    clone_dir   = args_dict['gitdir']

    logging.info("Git clone:   %s" % (clone_dir))
    logging.info("PR branch:   %s" % (pr_branch))
    logging.info("Base branch: %s" % (base_branch))

    #--------------------------------------
    # Make a python object representing the Git repo
    repo       = Repo(clone_dir)
    merge_base = repo.commit(base_branch)
    logging.info("Merge base:  %s" % (merge_base.hexsha))

    #--------------------------------------
    # Iterate from the HEAD of the PR branch down to the merge base with
    # the base branch.
    results = {
        'good' : 0,
        'bad'  : 0,
    }

    for commit in repo.iter_commits(repo.commit(pr_branch)):
        if commit.binsha == merge_base.binsha:
            logging.info("Found the merge base %s: we're done" % (commit.hexsha))
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
    with open(args_dict['status_msg_file'], 'w') as writer:
        writer.write(msg)

    exit(status)
