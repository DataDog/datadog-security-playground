# AWS CloudTrail -> Datadog, so Cloud SIEM can raise signals from the API calls
# the langflow-rce scenario makes with the stolen node credentials.
# Follows https://docs.datadoghq.com/security/cloud_security_management/setup/cloudtrail_logs/
#
# Pipeline: CloudTrail (multi-region) -> S3 -> Datadog Forwarder Lambda -> Datadog
# Logs (ddsource:cloudtrail). The Forwarder is Datadog's published CloudFormation
# template so its Lambda code stays maintained upstream; everything around it is
# managed here. Enabling Cloud SIEM itself is an org-level setting in Datadog and
# is a prerequisite, not something this module can configure.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  # S3 bucket names must be lowercase; random_string.suffix may contain uppercase.
  cloudtrail_bucket_name    = "security-playground-cloudtrail-${lower(random_string.suffix.result)}"
  cloudtrail_trail_name     = "${local.cluster_name}-trail"
  cloudtrail_forwarder_name = "security-playground-forwarder-${random_string.suffix.result}"

  # Built from known parts so the bucket policy can reference the trail without a
  # dependency cycle (the trail needs the bucket policy to exist before it starts).
  cloudtrail_trail_arn = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_trail_name}"
}

resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = local.cloudtrail_bucket_name

  # Playground bucket: let destroy remove it even with logs still inside.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire logs quickly: this is a short-lived demo, matching the 7-day retention
# used for the cluster's CloudWatch logs.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket[0].json
}

# Multi-region: the scenario's credential pivot calls RunInstances across several
# regions while the cluster runs in var.region, so a single-region trail would
# miss those events.
resource "aws_cloudtrail" "playground" {
  count = var.enable_cloudtrail ? 1 : 0

  name           = local.cloudtrail_trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# Datadog's published Forwarder, pinned. Bump by changing the version in the URL;
# latest.yaml tracks the newest release. The template stores the API key in its
# own Secrets Manager secret rather than in the Lambda environment.
resource "aws_cloudformation_stack" "forwarder" {
  count = var.enable_cloudtrail ? 1 : 0

  name         = local.cloudtrail_forwarder_name
  template_url = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/5.4.16.yaml"

  capabilities = ["CAPABILITY_IAM"]

  parameters = {
    DdApiKey           = var.datadog_api_key
    DdSite             = var.datadog_site
    FunctionName       = local.cloudtrail_forwarder_name
    DdTags             = "env:playground-env"
    LogRetentionInDays = "7"
    # Otherwise the template creates a tag-cache bucket that CloudFormation can't delete once non-empty, breaking destroy.
    DdFetchLambdaTags = "false"
  }
}

# Let the CloudTrail bucket invoke the Forwarder; required before the bucket
# notification can reference it.
resource "aws_lambda_permission" "cloudtrail_forwarder" {
  count = var.enable_cloudtrail ? 1 : 0

  statement_id   = "AllowCloudTrailBucketInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_cloudformation_stack.forwarder[0].outputs["DatadogForwarderArn"]
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.cloudtrail[0].arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  lambda_function {
    lambda_function_arn = aws_cloudformation_stack.forwarder[0].outputs["DatadogForwarderArn"]
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.cloudtrail_forwarder]
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket receiving CloudTrail logs, or null when CloudTrail is disabled"
  value       = try(aws_s3_bucket.cloudtrail[0].bucket, null)
}

output "cloudtrail_trail_arn" {
  description = "ARN of the multi-region CloudTrail trail, or null when CloudTrail is disabled"
  value       = try(aws_cloudtrail.playground[0].arn, null)
}

output "datadog_forwarder_arn" {
  description = "ARN of the Datadog Forwarder Lambda shipping CloudTrail logs to Datadog, or null when CloudTrail is disabled"
  value       = try(aws_cloudformation_stack.forwarder[0].outputs["DatadogForwarderArn"], null)
}
