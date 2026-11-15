terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      Module    = "3"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name  = "${var.name}-uploads-${data.aws_caller_identity.current.account_id}"
  secret_param = "/${var.name}/admin-key"
  log_group    = "/${var.name}/app"
}

# ---------------------------------------------------------------- networking

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web" {
  name        = "${var.name}-sg"
  description = "HTTP from anywhere, SSH from my IP only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "HTTP (nginx reverse proxy to the app on 127.0.0.1:3000)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound (package installs, AWS APIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg" }
}

# ---------------------------------------------------------------- object storage (S3)

resource "aws_s3_bucket" "uploads" {
  bucket        = local.bucket_name
  force_destroy = true # lets `terraform destroy` remove the bucket even when it holds uploads
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Quota-style control: uploads expire after 30 days so storage cannot grow forever.
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------- managed database (DynamoDB)

resource "aws_dynamodb_table" "notes" {
  name         = "${var.name}-notes"
  billing_mode = "PAY_PER_REQUEST" # no capacity to provision, you pay per request
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# ---------------------------------------------------------------- secret (SSM Parameter Store)

resource "random_password" "admin_key" {
  length  = 24
  special = false
}

# NOTE: the generated value is also stored in terraform.tfstate, which is git-ignored.
resource "aws_ssm_parameter" "admin_key" {
  name        = local.secret_param
  description = "Admin key that protects DELETE /api/notes/:id"
  type        = "SecureString"
  value       = random_password.admin_key.result
}

# ---------------------------------------------------------------- IAM (role for the server, no access keys on disk)

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

# Least privilege: only this table, this bucket and this one parameter.
data "aws_iam_policy_document" "app" {
  statement {
    sid = "NotesTable"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.notes.arn]
  }

  statement {
    sid       = "UploadsBucket"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }

  statement {
    sid       = "ReadAdminKey"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.admin_key.arn]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.name}-app-access"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# Lets the CloudWatch agent ship logs and memory/disk metrics.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-profile"
  role = aws_iam_role.app.name
}

# ---------------------------------------------------------------- monitoring (CloudWatch)

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group
  retention_in_days = 7
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# The email address receives a confirmation message that must be accepted once.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "Average CPU above 80% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.name}-status-check-failed"
  alarm_description   = "EC2 system or instance status check failing"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Cost quota: email at 80% of the monthly budget.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

# ---------------------------------------------------------------- compute (EC2)

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "app" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.app.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  # IMDSv2 only: blocks the SSRF-style credential theft that IMDSv1 allowed.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region       = var.region
    repo_url     = var.repo_url
    repo_branch  = var.repo_branch
    table_name   = aws_dynamodb_table.notes.name
    bucket_name  = aws_s3_bucket.uploads.bucket
    secret_param = local.secret_param
    log_group    = local.log_group
  })
  user_data_replace_on_change = true

  # The role policies must exist before the app starts and calls AWS.
  depends_on = [
    aws_iam_role_policy.app,
    aws_iam_role_policy_attachment.cloudwatch_agent,
    aws_ssm_parameter.admin_key,
    aws_cloudwatch_log_group.app,
  ]

  tags = { Name = var.name }
}
