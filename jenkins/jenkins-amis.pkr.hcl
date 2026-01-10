packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "iam_role" {
  type    = string
  default = "${env("AWS_IAM_ROLE")}"
}

variable "subnet_id" {
  type    = string
  default = "${env("AWS_SUBNET_ID")}"
}

variable "vpc_id" {
  type    = string
  default = "${env("AWS_VPC_ID")}"
}

variable "BuildType" {
  type    = string
  default = "${env("BUILD_TYPE")}"
}

variable "deprecation_date" {
  type    = string
  default = "${env("DEPRECATION_DATE")}"
}


################################################################################
#
# Amazon Linux
#
################################################################################
data "amazon-ami" "AmazonLinux2-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "amzn2-ami-hvm-2.0.*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "us-west-2"
}

source "amazon-ebs" "AmazonLinux2-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Amazon Linux 2 arm64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.AmazonLinux2-arm64.id}"
  ssh_pty      = true
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "AmazonLinux2-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "amzn2-ami-hvm-2.0.*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "us-west-2"
}

source "amazon-ebs" "AmazonLinux2-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Amazon Linux 2 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.AmazonLinux2-x86.id}"
  ssh_pty      = true
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


################################################################################
#
# Red Hat Enterprise Linux
#
################################################################################
data "amazon-ami" "RHEL8-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "RHEL-8.*-0-Hourly2-GP2"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL8-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 8 arm64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL8-arm64.id}"
  ssh_pty      = true
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "RHEL8-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "RHEL-8.*-0-Hourly2-GP2"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL8-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 8 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL8-x86.id}"
  ssh_pty      = true
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


################################################################################
#
# SUSE Linux Enterprise Server
#
################################################################################
data "amazon-ami" "SLES15-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "suse-sles-15-sp??-v????????-hvm-ssd*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "us-west-2"
}

source "amazon-ebs" "SLES15-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins SLES 15 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.SLES15-x86.id}"
  ssh_pty      = true
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


################################################################################
#
# Ubuntu Linux
#
################################################################################
data "amazon-ami" "Ubuntu1804-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "Ubuntu1804-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 18.04 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu1804-x86.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2004-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2004-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 20.04 arm64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2004-arm64.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2004-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2004-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 20.04 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2004-x86.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2204-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2204-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 22.04 arm64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2204-arm64.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2204-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2204-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 22.04 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2204-x86.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2404-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2404-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 24.04 arm64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2404-arm64.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "Ubuntu2404-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "us-west-2"
}

source "amazon-ebs" "Ubuntu2404-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 24.04 x86_64"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2404-x86.id}"
  ssh_pty      = true
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


build {
  sources = [
    "source.amazon-ebs.AmazonLinux2-arm64",
    "source.amazon-ebs.AmazonLinux2-x86",
    "source.amazon-ebs.RHEL8-arm64",
    "source.amazon-ebs.RHEL8-x86",
    "source.amazon-ebs.SLES15-x86",
    "source.amazon-ebs.Ubuntu1804-x86",
    "source.amazon-ebs.Ubuntu2004-arm64",
    "source.amazon-ebs.Ubuntu2004-x86",
    "source.amazon-ebs.Ubuntu2204-arm64",
    "source.amazon-ebs.Ubuntu2204-x86",
    "source.amazon-ebs.Ubuntu2404-arm64",
    "source.amazon-ebs.Ubuntu2404-x86"
  ]

  provisioner "shell" {
    script       = "customize-ami.sh"
  }

}
