{
  "variables": {
   "subnet_id" : "{{env `AWS_SUBNET_ID`}}",
   "vpc_id" : "{{env `AWS_VPC_ID`}}",
   "build_date" : "{{env `BUILD_DATE`}}",
   "iam_role" : "{{env `AWS_IAM_ROLE`}}"
  },
  "builders": [{
    "type": "amazon-ebs",
    "name" : "AmazonLinux2-x86",
    "ami_name": "Jenkins Amazon Linux 2 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "amzn2-ami-hvm-2.0.*"
        },
        "owners": ["amazon"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/xvda",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/xvda",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "AmazonLinux2-arm64",
    "ami_name": "Jenkins Amazon Linux 2 arm64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "arm64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "amzn2-ami-hvm-2.0.*"
        },
        "owners": ["amazon"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/xvda",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/xvda",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t4g.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu18.04-x86",
    "ami_name": "Jenkins Ubuntu 18.04 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu18.04-arm64",
    "ami_name": "Jenkins Ubuntu 18.04 arm64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "arm64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-arm64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t4g.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu20.04-x86",
    "ami_name": "Jenkins Ubuntu 20.04 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu20.04-arm64",
    "ami_name": "Jenkins Ubuntu 20.04 arm64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "arm64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t4g.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu22.04-x86",
    "ami_name": "Jenkins Ubuntu 22.04 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "Ubuntu22.04-arm64",
    "ami_name": "Jenkins Ubuntu 22.04 arm64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "arm64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
        },
        "owners": ["099720109477"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t4g.micro",
    "ssh_username": "ubuntu",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "RHEL7-x86",
    "ami_name": "Jenkins RHEL 7 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "RHEL-7.*-0-Hourly2-GP2"
        },
        "owners": ["309956199498"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "RHEL8-x86",
    "ami_name": "Jenkins RHEL 8 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "RHEL-8.*-0-Hourly2-GP2"
        },
        "owners": ["309956199498"],
        "most_recent": true
    },
    "instance_type": "t3.micro",
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "RHEL8-arm64",
    "ami_name": "Jenkins RHEL 8 arm64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "arm64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "RHEL-8.*-0-Hourly2-GP2"
        },
        "owners": ["309956199498"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t4g.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "SLES15-x86",
    "ami_name": "Jenkins SLES 15 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "suse-sles-15-sp??-v????????-hvm-ssd*"
        },
        "owners": ["amazon"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  },{
    "type": "amazon-ebs",
    "name" : "FreeBSD11-x86",
    "ami_name": "Jenkins FreeBSD 13 x86_64 {{user `build_date`}}",
    "region": "us-west-2",
    "source_ami_filter": {
        "filters": {
            "architecture": "x86_64",
            "virtualization-type": "hvm",
            "root-device-type": "ebs",
            "name": "FreeBSD 13.*-RELEASE-amd64 UEFI"
        },
        "owners": ["782442783595"],
        "most_recent": true
    },
    "ami_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
        } ],
    "launch_block_device_mappings": [ {
        "device_name": "/dev/sda1",
        "volume_size": 16,
        "delete_on_termination": true
    } ],
    "instance_type": "t3.micro",
    "ssh_username": "ec2-user",
    "ssh_pty" : true,
    "ssh_timeout" : "10m",
    "associate_public_ip_address" : true,
    "ena_support" : true,
    "iam_instance_profile" : "{{user `iam_role`}}"
  }],
  "provisioners": [{
    "type": "shell",
    "script" : "customize-ami.sh"
  }]
}
