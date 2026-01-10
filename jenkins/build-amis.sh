#!/bin/sh
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Build a new set of AMIs for Jenkins using Packer.  This script
# requires packer be installed, along with the packer.json and
# customize-ami.sh scripts in this directory.
#
# Run this script from your laptop using an IAM role for the
# ompi-aws-prod account with EC2 priviledges or from aws.open-mpi.org
# using the instance's role.
#

OPTIND=1
packer_opts=""
packer_file="jenkins-amis.pkr.hcl"
build_type="testing"
deprecation_date=`date -d "+3 weeks" +"%Y-%m-%dT%H:%M:00Z"`

while getopts "h?a:lpd" opt; do
    case "$opt" in
    h|\?)
        echo "usage: build-ami.sh [-a <ami list>]"
        echo "  -a <ami list>     Only build amis in ami list (comma separated)"
        echo "  -l                List ami names available for building"
        echo "  -p                Label as production amis"
        echo "  -d                Enable debugging for packer"
        exit 1
        ;;
    a)
        packer_opts="${packer_opts} --only ${OPTARG}"
        ;;
    l)
        ami_list=`packer inspect ${packer_file} | grep amazon-ebs`
        echo "Available amis:\n${ami_list}"
        exit 0
        ;;
    p)
        if test "$JENKINS_URL" = "" ; then
            echo "Can't build production amis ourside of Jenkins and don't see a \$JENKINS_URL."
            exit 1
        fi
        build_type="production"
        ;;
    d)
        packer_opts="${packer_opts} --debug"
        ;;
    esac
done

BUILD_DATE=`date +%Y%m%d%H%M`

export AWS_IAM_ROLE="jenkins-worker"
export BUILD_TYPE="${build_type}"
export DEPRECATION_DATE="${deprecation_date}"

packer build ${packer_opts} ${packer_file} | tee ${packer_file}.${BUILD_DATE}.txt
grep 'Recommended labels' ${packer_file}.${BUILD_DATE}.txt
