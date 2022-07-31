#!/usr/bin/env python3

'''
Requirements:

$ pip3 install pygithub

Go to https://github.com/settings/tokens and make a personal access
token with full permissions to the repo and org.

'''

import csv

from github import Github
from pprint import pprint

#--------------------------------------------------------------------

# Read the oAuth token file.
# (you will need to supply this file yourself -- see the comment at
# the top of this file)
token_filename = 'oauth-token.txt'
with open(token_filename, 'r') as f:
    token = f.read().strip()
g = Github(token)

#--------------------------------------------------------------------

print("Getting open-mpi organization...")
org = 'open-mpi'
ompi_org = g.get_organization(org)

#--------------------------------------------------------------------

print("Loading organization repos...")
all_members = dict()
repos = dict()
for repo in ompi_org.get_repos():
    print(f"Found Org Repo: {repo.name}")

    if repo.archived:
        print("--> NOTE: This repo is archived")

    # For each repo, get the teams on that repo
    repo_teams = dict()
    for team in repo.get_teams():
        out = f"   Found team on repo {ompi_org.name}/{repo.name}: {team.name} ({team.permission}) "
        # We only care about teams with push permissions
        if team.permission == "pull":
            print(f"{out} -- SKIPPED")
            continue

        print(out)

        # Find all the members of this team
        team_members = dict()
        member_teams = dict()
        for member in team.get_members():
            print(f"      Found member: {member.login}")
            team_members[member.id] = member

            if member.id not in all_members:
                all_members[member.id] = {
                    'member'       : member,
                    'member_teams' : dict(),
                }

            # Find the member in the org and add this team to them
            all_members[member.id]['member_teams'][team.id] = team

        # Same the results
        repo_teams[team.id] = {
            'team'         : team,
            'team_members' : team_members,
        }

    # Save the results
    repos[repo.id] = {
        'repo'        : repo,
        'repo_teams'  : repo_teams,
    }

print("All the repos:")
pprint(repos)
pprint(all_members)

#--------------------------------------------------------------------

# Pre-load the field names with info about the user and repo
fieldnames = ['login', 'name', 'email', 'company']

# Add all the repo names
#
# Skip archived repos -- they're read-only, and thereare are
# effectively just noise in the annual review process.
repo_names = list()
for rentry in repos.values():
    repo = rentry['repo']
    if not repo.archived:
        # Used to include the org name in here, but it was always
        # "open-mpi", and it just made the colun need to be wider.
        repo_names.append(repo.name)

fieldnames.extend(sorted(repo_names))

#--------------------------------------------------------------------

# Now write out the CSV
outfile = 'permissions.csv'
print(f"Writing: {outfile}")
with open(outfile, 'w', newline='') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames,
                            quoting=csv.QUOTE_ALL)
    writer.writeheader()
    for mid, mentry in all_members.items():
        member = mentry['member']
        print(f"  Writing member: {member.login}")

        # Initial entries about the user
        row = {
            'login' : member.login,
            'name'  : member.name,
            'email' : member.email,
            'company' : member.company,
        }

        # Fill in values for each repo
        for _, rentry in repos.items():
            repo = rentry['repo']

            # Per above, skip archived repos
            if repo.archived:
                continue

            found = list()
            for tid, tentry in rentry['repo_teams'].items():
                if tid in mentry['member_teams']:
                    team = tentry['team']
                    found.append(team.name)

            row[repo.name] = ', '.join(found)

        writer.writerow(row)
