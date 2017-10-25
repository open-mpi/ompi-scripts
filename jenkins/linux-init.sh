#!/bin/bash
#
# Copyright (c) 2017      Amazon.com, Inc. or its affiliates.  All Rights
#                         Reserved.
#
# Additional copyrights may follow
#
# Script to take an AMI already customized for OMPI Jenkins (by the
# linux-customize-ami.sh script) and verify that it's up to date on
# boot.  Yes, we could probably just hard-code the update commands
# into the user-data, but this gives us a bit of a future-proofing
# hook, should we change our minds later.
#
# Recommended usage is to set the following in user-data on the launch
# command (the 'User Data' advanced option in the Jenkins
# configuration):
#
#  #!/bin/bash
#  curl https://raw.github.com/open-mpi/ompi-scripts/master/jenkins/linux-init.sh -i /tmp/linux-init.sh
#  /bin/bash /tmp/linux-init.sh
#

eval "PLATFORM_ID=`sed -n 's/^ID=//p' /etc/os-release`"
eval "VERSION_ID=`sed -n 's/^VERSION_ID=//p' /etc/os-release`"

echo $PLATFORM_ID
echo $VERSION_ID

case $PLATFORM_ID in
    rhel|amzn)
	sudo yum -y update
	;;
    ubuntu)
	sudo apt-get update
	sudo apt-get -y upgrade
	;;
    sles)
	;;
    *)
	echo "ERROR: Unkonwn platform ${PLATFORM_ID}"
	exit 1
esac
