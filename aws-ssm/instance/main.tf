data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^amzn2-ami-hvm.*-ebs"

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  bastion_launch_template_name = "ssm-bastion-lt"
  name_prefix                  = local.bastion_launch_template_name
}

resource "aws_iam_role" "bastion_host_role" {
  name               = "ssm-bastion-host"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_policy_document.json
}

data "aws_iam_policy_document" "assume_policy_document" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


data "aws_iam_policy_document" "bastion_host_ssm_policy_document" {

  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetEncryptionConfiguration",
    ]
    resources = [
      var.log_bucket_arn,
      "${var.log_bucket_arn}/*"
    ]
  }

  statement {
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      var.session_kms_arn,
    ]
  }

}

resource "aws_iam_policy" "bastion_host_ssm_policy" {
  name   = "${local.name_prefix}-host-ssm-policy"
  policy = data.aws_iam_policy_document.bastion_host_ssm_policy_document.json
}

resource "aws_iam_role_policy_attachment" "bastion_host_ssm" {
  policy_arn = aws_iam_policy.bastion_host_ssm_policy.arn
  role       = aws_iam_role.bastion_host_role.name
}

resource "aws_iam_instance_profile" "bastion_host_profile" {
  role = aws_iam_role.bastion_host_role.name
  path = "/"
}

resource "aws_launch_template" "bastion_launch_template" {
  name_prefix            = local.name_prefix
  image_id               = data.aws_ami.amazon-linux-2.id
  instance_type          = "t3.nano"
  update_default_version = true
  monitoring {
    enabled = true
  }
  network_interfaces {
    associate_public_ip_address = false
    security_groups = [
      aws_security_group.bastion_host_security_group.id,
    ]
    delete_on_termination = true
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.bastion_host_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(tomap({ "Name" = local.bastion_launch_template_name }), merge(var.tags))
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(tomap({ "Name" = local.bastion_launch_template_name }), merge(var.tags))
  }

  lifecycle {
    create_before_destroy = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

resource "aws_autoscaling_group" "bastion_auto_scaling_group" {
  name_prefix = "ASG-${local.name_prefix}"
  launch_template {
    id      = aws_launch_template.bastion_launch_template.id
    version = aws_launch_template.bastion_launch_template.latest_version
  }
  max_size         = 1
  min_size         = 1
  desired_capacity = 1

  vpc_zone_identifier = var.auto_scaling_group_subnets

  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  termination_policies = [
    "OldestLaunchConfiguration",
  ]

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-${var.env}"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
  }

  lifecycle {
    create_before_destroy = true
  }
}

### security groups
resource "aws_security_group" "bastion_host_security_group" {
  description = "basic security group for bastion host"
  name        = "${local.name_prefix}-host"
  vpc_id      = var.vpc_id

  tags = merge(var.tags)
}

resource "aws_security_group_rule" "egress_postgres" {
  description = "Allow connections to Postgres"
  type        = "egress"
  from_port   = "5432"
  to_port     = "5432"
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}

resource "aws_security_group_rule" "egress_https" {
  description = "Allow connections to HTTP for outbound SSM connections"
  type        = "egress"
  from_port   = "443"
  to_port     = "443"
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group.id
}
