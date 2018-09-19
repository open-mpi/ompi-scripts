#!/usr/bin/env python3
#
# Copyright (c) 2018 Jeff Squyres.  All rights reserved.
#
# Additional copyrights may follow
#
# $HEADER$
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# - Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#
# - Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer listed
#   in this license in the documentation and/or other materials
#   provided with the distribution.
#
# - Neither the name of the copyright holders nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# The copyright holders provide no reassurances that the source code
# provided does not infringe any patent, copyright, or any other
# intellectual property rights of third parties.  The copyright holders
# disclaim any liability to any recipient for claims brought against
# recipient by any third party for infringement of that parties
# intellectual property rights.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

'''This script waits for all the CI on a given PR to complete.

You typically want to run some kind of notifier after this script
completes to let you know that all the CI has completed.  For example:

    $ ./wait-for-pr-ci-completion.py \
        --pr https://github.com/open-mpi/ompi/pull/5731; \
        pushover CI for PR5731 is done

where "pushover" is a notifier script that I use to send a push
notification to my phone.  I.e., the 'pushover' script will execute
when the CI for PR 5731 completes.

-----

# Requirements:

1. You need the PyGithub python module
2. You need a GitHub personal access token to use the GitHub API
   (through the PyGithub python module)

-----

## Installing PyGithub:

$ pip3 install pygithub

Docs:

https://github.com/PyGithub/PyGithub
http://pygithub.readthedocs.io/

## Getting a Github personal access token

Go to https://github.com/settings/tokens and make a personal access
token with full permissions to the repo and org.

You can pass the oauth token to this script in one of 3 ways:

1. Name the file 'oauth-token.txt' and have it in the PWD when you run
   this script.
2. Pass the filename of the token via --oauth-file CLI options.
3. Set the env variable GITHUB_OAUTH_TOKEN with the filename of your
   oauth token (pro tip: if you set it to the absolute filename, it
   will be found no matter what directory you run this script from).

'''

import os
import time
import http
import logging
import argparse
import requests

from github import Github
from urllib.parse import urlparse
from datetime import datetime

#--------------------------------------------------------------------

default_delay = 60
real_default_oauth_file = 'oauth-token.txt'

if 'GITHUB_OAUTH_TOKEN' in os.environ:
    default_oauth_file = os.environ['GITHUB_OAUTH_TOKEN']
else:
    default_oauth_file = real_default_oauth_file

#--------------------------------------------------------------------

# Parse the CLI options

parser = argparse.ArgumentParser(description='Github actions.')

parser.add_argument('--pr', help='URL of PR')
parser.add_argument('--debug', action='store_true', help='Be really verbose')
parser.add_argument('--delay', default=default_delay,
                    help='Delay this many seconds between checking')
parser.add_argument('--oauth-file', default=default_oauth_file,
                    help='Filename containinig OAuth token to access Github (default is "{file}")'
                    .format(file=default_oauth_file))

args = parser.parse_args()

# Sanity check the CLI args

if not args.pr:
    print("Must specify a PR URL via --pr")
    exit(1)

if not os.path.exists(args.oauth_file):
    print("Cannot find oauth token file: {filename}"
          .format(filename=args.oauth_file))
    exit(1)

#--------------------------------------------------------------------

delay = args.delay

# Read the oAuth token file.
# (you will need to supply this file yourself -- see the comment at
# the top of this file)
with open(args.oauth_file, 'r') as f:
    token = f.read().strip()
g = Github(token)

#--------------------------------------------------------------------

log = logging.getLogger('GithubPRwaiter')
level = logging.INFO
if args.debug:
    level = logging.DEBUG
log.setLevel(level)

ch = logging.StreamHandler()
ch.setLevel(level)

format = '%(asctime)s %(levelname)s: %(message)s'
formatter = logging.Formatter(format)

ch.setFormatter(formatter)

log.addHandler(ch)

#--------------------------------------------------------------------

# Pick apart the URL
parts = urlparse(args.pr)
path = parts.path
vals = path.split('/')
org  = vals[1]
repo = vals[2]
pull = vals[3]
num  = vals[4]

full_name = os.path.join(org, repo)
log.debug("Getting repo {r}...".format(r=full_name))
repo = g.get_repo(full_name)

log.debug("Getting PR {pr}...".format(pr=num))
pr = repo.get_pull(int(num))

log.info("PR {num}: {title}".format(num=num, title=pr.title))
log.info("PR {num} is {state}".format(num=num, state=pr.state))
if pr.state != "open":
    log.info("Nothing to do!".format(num=num))
    exit(0)

log.debug("PR head is {sha}".format(sha=pr.head.sha))

log.debug("Getting commits...")
commits = pr.get_commits()

# Find the HEAD commit -- that's where the most recent statuses will be
head_commit = None
for c in commits:
    if c.sha == pr.head.sha:
        log.debug("Found HEAD commit: {sha}".format(sha=c.sha))
        head_commit = c
        break

if not head_commit:
    log.error("Did not find HEAD commit (!)")
    log.error("That's unexpected -- I'm going to abort...")
    exit(1)

#--------------------------------------------------------------------

# Main loop

done      = False
succeeded = None
failed    = None
statuses  = dict()
while not done:
    # There can be a bunch of statuses from the same context.  Take
    # only the *chronologically-last* status from each context.

    # Note: put both the "head_commit.get_statuses()" *and* the "for s
    # in github_statuses" in the try block because some empirical
    # testing shows that pygithub may be obtaining statuses lazily
    # during the for loop (i.e., not during .get_statuses()).
    try:
        github_statuses = head_commit.get_statuses()
        for s in github_statuses:
            save = False
            if s.context not in statuses:
                save = True
                log.info("Found new {state} CI: {context} ({desc})"
                         .format(context=s.context, state=s.state,
                                 desc=s.description))
            else:
                # s.updated_at is a python datetime.  Huzzah!
                if s.updated_at > statuses[s.context].updated_at:
                    log.info("Found update {state} CI: {context} ({desc})"
                             .format(context=s.context, state=s.state,
                                     desc=s.description))
                    save = True

            if save:
                statuses[s.context] = s

    except ConnectionResetError:
        log.error("Got Connection Reset.  Sleeping and trying again...")
        time.sleep(5)
        continue
    except requests.exceptions.ConnectionError:
        log.error("Got Connection error.  Sleeping and trying again...")
        time.sleep(5)
        continue
    except http.client.RemoteDisconnected:
        log.error("Got http Remote Disconnected.  Sleeping and trying again...")
        time.sleep(5)
        continue
    except requests.exceptions.RemotedDisconnected:
        log.error("Got requests Remote Disconnected.  Sleeping and trying again...")
        time.sleep(5)
        continue

    done      = True
    succeeded = list()
    failed    = list()
    for context,status in statuses.items():
        if status.state == 'success':
            succeeded.append(status)
        elif status.state == 'failure':
            failed.append(status)
        elif status.state == 'pending':
            log.debug("Still waiting for {context}: {desc}"
                      .format(context=context,
                              desc=status.description))
            done = False
        else:
            log.warning("Got unknown status state: {state}"
                        .format(state=status.state))
            exit(1)

    if not done:
        log.debug("Waiting {delay} seconds...".format(delay=delay))
        time.sleep(delay)

log.info("All CI statuses are complete:")
for s in succeeded:
    log.info("PASSED {context}: {desc}"
             .format(context=s.context,
                     desc=s.description.strip()))
for s in failed:
    log.info("FAILED {context}: {desc}"
             .format(context=s.context,
                     desc=s.description.strip()))
exit(0)
