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

while getopts "h?a:l" opt; do
    case "$opt" in
    h|\?)
        echo "usage: build-ami.sh [-a <ami list>]"
        echo "  -a <ami list>     Only build amis in ami list (comma separated)"
        echo "  -l                List ami names available for building"
        exit 1
        ;;
    a)
        packer_opts="--only ${OPTARG}"
        ;;
    l)
        ami_list=`packer inspect -machine-readable ${packer_file} | grep template-builder | cut -f4 -d, | xargs`
        echo "Available amis: ${ami_list}"
        exit 0
        ;;
    esac
done

export BUILD_DATE=`date +%Y%m%d%H%M`
export AWS_IAM_ROLE="jenkins-worker"

packer build ${packer_opts} ${packer_file} | tee ${packer_file}.${BUILD_DATE}.txt
grep 'Recommended labels' ${packer_file}.${BUILD_DATE}.txt
