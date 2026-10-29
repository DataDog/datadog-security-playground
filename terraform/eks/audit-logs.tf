# EKS audit logs -> Datadog: the control-plane (plane A) half of the two-plane
# Kubernetes detections. On managed EKS the api server's audit log exists only
# in CloudWatch (/aws/eks/<cluster>/audit) — there is no audit file on the nodes
# for the Datadog Agent to mount. This file subscribes that log group to the
# Datadog Forwarder (the same Lambda CloudTrail uses, see cloudtrail.tf) so audit
# events reach Datadog Logs with source:kubernetes.audit, where the
# out-of-the-box Kubernetes audit SIEM rules (exec into pod, cluster-admin
# binding, ...) and any pod-UID correlation can see them.
#
# Audit logging itself is enabled in main.tf (cluster_enabled_log_types = ["audit"]).
# Forwarding follows
# https://docs.datadoghq.com/logs/guide/send-aws-services-logs-with-the-datadog-lambda-function/

locals {
  eks_audit_log_group_name = "/aws/eks/${module.eks.cluster_name}/audit"

  # Built from known parts (like the CloudTrail trail ARN in cloudtrail.tf) so
  # the Lambda permission can reference the log group before it exists.
  eks_audit_log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.eks_audit_log_group_name}"
}

# Let CloudWatch Logs invoke the Forwarder for the audit log group; required
# before the subscription filter can reference it. Mirrors the S3 permission
# in cloudtrail.tf.
resource "aws_lambda_permission" "eks_audit_forwarder" {
  count = var.enable_eks_audit_logs_to_datadog ? 1 : 0

  statement_id   = "AllowEksAuditLogGroupInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_cloudformation_stack.forwarder[0].outputs["DatadogForwarderArn"]
  principal      = "logs.amazonaws.com"
  source_arn     = "${local.eks_audit_log_group_arn}:*"
  source_account = data.aws_caller_identity.current.account_id
}

# Every audit event the api server writes flows to the Forwarder and then
# Datadog. No filter pattern: audit volume on a demo cluster is small, and the
# detections want the full stream — denied requests included.
resource "aws_cloudwatch_log_subscription_filter" "eks_audit_to_datadog" {
  count = var.enable_eks_audit_logs_to_datadog ? 1 : 0

  name            = "${local.cluster_name}-audit-to-datadog"
  log_group_name  = local.eks_audit_log_group_name
  filter_pattern  = ""
  destination_arn = aws_cloudformation_stack.forwarder[0].outputs["DatadogForwarderArn"]

  depends_on = [aws_lambda_permission.eks_audit_forwarder]
}

output "eks_audit_log_group_name" {
  description = "CloudWatch log group receiving the EKS control-plane audit log, or null when forwarding to Datadog is disabled"
  value       = var.enable_eks_audit_logs_to_datadog ? local.eks_audit_log_group_name : null
}
