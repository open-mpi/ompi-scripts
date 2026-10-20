#!/bin/bash
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Wrapper to start scripts under the right modules environment.  It's
# hard to make modules do something rational from Python, so use this
# wrapper to provide the missing functionality.
#

if test "$#" -lt 2; then
    echo "usage: ./run-with-autotools.sh <module name> <program> [options]"
    exit 1
fi

module_name="$1"
shift
program_name="$1"
shift
arguments=("$@")

if ! type -t module > /dev/null 2>&1 ; then
    if test "$MODULESHOME" = ""; then
	if test -d ${HOME}/local/modules; then
	    export MODULESHOME=${HOME}/local/modules
	else
	    echo "Can't find \$MODULESHOME.  Aborting."
	    exit 1
	fi
    fi
    . ${MODULESHOME}/init/bash
fi

module unload autotools
module load $module_name

#
# in addition to all the autotools modules, recent 
# Open MPI branches need a number of python modules 
# not all of which are available via linux distros,
# so set up a virtual env to run the command in
#
python3 -m venv ompi-docs-venv
. ompi-docs-venv/bin/activate
find . -name "requirements.txt" -exec pip3 install -r {} \;
$program_name "${arguments[*]}"
if [ -n "${VIRTUAL_ENV:-}" ] && command -v deactivate >/dev/null 2>&1; then
    deactivate
fi
