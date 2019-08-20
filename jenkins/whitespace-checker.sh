#! /usr/bin/env bash
#
# Copyright (c) 2019      Hewlett Packard Enterprise. All Rights Reserved.
#
# Additional copyrights may follow
#
# Check for white space violation in a given commit range.
# Run on a PR to check whether it is introducing bad white space.
#

context=3
config_file=.whitespace-checker-config.txt
if [[ -r $config_file ]]; then
    exclude_dirs=`cat $config_file`
else
    exclude_dirs='((opal/mca/hwloc/hwloc.*/hwloc)|/(libevent|pmix4x|treematch|romio))/'
fi

foundTab=0
for file in $(git diff -l0 --name-only $1 $2 | grep -vE "($exclude_dirs)" | grep -E "(\.c|\.h)$")
do
    git diff $1 $2 -- $file | grep -C $context -E "^\+.*	+"
    if [[ $? -eq 0 ]]
    then
        foundTab=1
    fi
done

if [[ $foundTab -ne 0 ]]
then
    exit 1
fi
