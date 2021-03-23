#!/usr/bin/env bash

# Make sure we have clang-format v11.
# This may well be redundant / unnecessary, since the AMI should be
# guaranteed to have it.
check() {
    which $1 2>&1 > /dev/null
    if test $? -eq 0; then
        version=$($1 --version | grep "version 11")
        if test -n "$version"; then
            CF=$1
        fi
    fi
}

# Find if the executable is named "clang-format" or "clang-format-11".
check clang-format
if test -z "$CF"; then
    check clang-format-11
fi
if test -z "$CF"; then
    echo "Cannot find clang-format v11"
    exit 1
fi

#####################################

# This expression to find the files we care about / want to check was
# blatantly stolen from Open MPI contrib/clang-format-ompi.sh.
files=($(git ls-tree -r HEAD --name-only | grep -v -E '3rd-party/|contrib/' | grep -e '.*\.[ch]$' | xargs grep -E -L -- "-*- fortran -*-|-*- f90 -*-"))

st=0
file=tmp.$$.txt
for file in "${files[@]}" ; do
    # Only show the ouptut if there is an error.  Otherwise, we'll
    # show output for every single file in the tree, which will be
    # overwhelming. clang-format writes directly to the tty, so we
    # can't use regular redirection -- must use "script" instead.  :-(
    #
    # NOTE: This is Linux-specific!  The MacOS "script" uses different
    # options.
    script --return --quiet --command "$CF --style=file --Werror --dry-run ${file}" $file > /dev/null
    if test $? -ne 0; then
        st=1
        cat <<EOF

clang-format failed for ${file}"

EOF
        cat $file
    fi
    rm -f $file
done

#####################################

if test "$st" -ne 0; then
    echo "clang-format CI failed"
else
    echo "clang-format CI succeeded -- huzzah!"
fi
exit $st
