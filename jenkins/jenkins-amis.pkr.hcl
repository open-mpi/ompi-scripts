packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}


variable "build_date" {
  type    = string
  default = "${env("BUILD_DATE")}"
}

variable "iam_role" {
  type    = string
  default = "${env("AWS_IAM_ROLE")}"
}

variable "security_group_id" {
  type    = string
  default = "${env("AWS_SECURITY_GROUP_ID")}"
}

variable "ssh_interface" {
  type    = string
  default = "private_ip"
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
  ami_name                    = "Jenkins Amazon Linux 2 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.AmazonLinux2-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Amazon Linux 2 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.AmazonLinux2-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-parameterstore" "AmazonLinux2023-arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  region = "us-west-2"
}

source "amazon-ebs" "AmazonLinux2023-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Amazon Linux 2023 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.AmazonLinux2023-arm64.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-parameterstore" "AmazonLinux2023-x86" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  region = "us-west-2"
}

source "amazon-ebs" "AmazonLinux2023-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Amazon Linux 2023 x86 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.AmazonLinux2023-x86.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


# Distribution-tarball builder variant of the Amazon Linux 2023 x86 AMI.  It is
# intentionally identical to the AmazonLinux2023-x86 builder above except that
# pandoc, the GNU Autotools, Flex, and M4 are NOT left installed in system
# paths (customize-ami.sh removes them when JENKINS_DIST_BUILDER is set).  The
# dist tarball jobs build their own version-pinned Autotools (see
# open-mpi-autotools-build.sh) and must not pick up the distro's copies, so
# this AMI deliberately lacks them.  Tagged JenkinsBuilderAmi=False and
# JenkinsDistBuilderAmi=True so Jenkins can select it separately.
source "amazon-ebs" "AmazonLinux2023Dist-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Amazon Linux 2023 Dist x86 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/xvda"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.AmazonLinux2023-x86.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "False",
    JenkinsDistBuilderAmi = "True"
  }
}


################################################################################
#
# FreeBSD
#
################################################################################
data "amazon-parameterstore" "FreeBSD15-x86" {
  name        = "/aws/service/freebsd/amd64/cloud-init/ufs/15.1/RELEASE"
  region      = "us-west-2"
}

source "amazon-ebs" "FreeBSD15-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins FreeBSD 15 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.FreeBSD15-x86.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_timeout  = "10m"
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
  ami_name                    = "Jenkins RHEL 8 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL8-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins RHEL 8 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL8-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "RHEL9-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "RHEL-9.7.0_HVM-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL9-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 9 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL9-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "RHEL9-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "RHEL-9.7.0_HVM-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL9-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 9 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL9-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "RHEL10-arm64" {
  filters = {
    architecture        = "arm64"
    name                = "RHEL-10.1.0_HVM-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL10-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 10 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL10-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-ami" "RHEL10-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "RHEL-10.1.0_HVM-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["309956199498"]
  region      = "us-west-2"
  include_deprecated = true
}

source "amazon-ebs" "RHEL10-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins RHEL 10 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.RHEL10-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
    name                = "suse-sles-15-sp7-v????????-hvm-ssd*"
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
  ami_name                    = "Jenkins SLES 15 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.SLES15-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ec2-user"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}

data "amazon-ami" "SLES16-x86" {
  filters = {
    architecture        = "x86_64"
    name                = "suse-sles-16-0-v????????-hvm-ssd*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "us-west-2"
}

source "amazon-ebs" "SLES16-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins SLES 16 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.SLES16-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 20.04 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2004-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 20.04 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2004-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 22.04 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2204-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 22.04 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2204-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 24.04 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2404-arm64.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
  ami_name                    = "Jenkins Ubuntu 24.04 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-ami.Ubuntu2404-x86.id}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-parameterstore" "Ubuntu2604-arm64" {
  name = "/aws/service/canonical/ubuntu/server/resolute/stable/current/arm64/hvm/ebs-gp3/ami-id"
  region = "us-west-2"
}

source "amazon-ebs" "Ubuntu2604-arm64" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 26.04 arm64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t4g.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.Ubuntu2604-arm64.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
  ssh_username = "ubuntu"
  tags = {
    BuildType = "${var.BuildType}",
    JenkinsBuilderAmi = "True"
  }
}


data "amazon-parameterstore" "Ubuntu2604-x86" {
  name = "/aws/service/canonical/ubuntu/server/resolute/stable/current/amd64/hvm/ebs-gp3/ami-id"
  region = "us-west-2"
}

source "amazon-ebs" "Ubuntu2604-x86" {
  ami_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  ami_name                    = "Jenkins Ubuntu 26.04 x86_64 ${var.build_date}"
  deprecate_at                = "${var.deprecation_date}"
  associate_public_ip_address = true
  ena_support                 = true
  iam_instance_profile        = "${var.iam_role}"
  security_group_id           = "${var.security_group_id}"
  subnet_id                   = "${var.subnet_id}"
  vpc_id                      = "${var.vpc_id}"
  instance_type               = "t3.large"
  launch_block_device_mappings {
    delete_on_termination = true
    device_name           = "/dev/sda1"
    volume_size           = 16
  }
  metadata_options {
    http_tokens = "required"
  }
  region       = "us-west-2"
  source_ami   = "${data.amazon-parameterstore.Ubuntu2604-x86.value}"
  ssh_pty      = true
  ssh_interface = "${var.ssh_interface}"
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
    "source.amazon-ebs.AmazonLinux2023-arm64",
    "source.amazon-ebs.AmazonLinux2023-x86",
    "source.amazon-ebs.AmazonLinux2023Dist-x86",
    "source.amazon-ebs.FreeBSD15-x86",
    "source.amazon-ebs.RHEL8-arm64",
    "source.amazon-ebs.RHEL8-x86",
    "source.amazon-ebs.RHEL9-arm64",
    "source.amazon-ebs.RHEL9-x86",
    "source.amazon-ebs.RHEL10-arm64",
    "source.amazon-ebs.RHEL10-x86",
    "source.amazon-ebs.SLES15-x86",
    "source.amazon-ebs.Ubuntu2004-arm64",
    "source.amazon-ebs.Ubuntu2004-x86",
    "source.amazon-ebs.Ubuntu2204-arm64",
    "source.amazon-ebs.Ubuntu2204-x86",
    "source.amazon-ebs.Ubuntu2404-arm64",
    "source.amazon-ebs.Ubuntu2404-x86",
    "source.amazon-ebs.Ubuntu2604-arm64",
    "source.amazon-ebs.Ubuntu2604-x86"
  ]

  provisioner "shell" {
    script = "customize-ami.sh"
    # Every source except the dist-tarball builder runs the stock
    # customization.
    except = ["amazon-ebs.AmazonLinux2023Dist-x86"]
  }

  provisioner "shell" {
    # The dist-tarball builder runs the same script, but JENKINS_DIST_BUILDER
    # tells it to remove pandoc / Autotools / Flex / M4 from system paths and
    # skip the in-AMI Open MPI build test (which needs those tools).
    script           = "customize-ami.sh"
    only             = ["amazon-ebs.AmazonLinux2023Dist-x86"]
    environment_vars = ["JENKINS_DIST_BUILDER=1"]
  }

}
