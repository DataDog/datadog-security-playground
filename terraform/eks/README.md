# Terraform for EKS

The Terraform code inside this repository provides a simple way to create an EKS cluster with Datadog monitoring and a security playground application.

## Prerequisites

- AWS credentials configured or passed as environment variables, also allowed to create the CloudTrail resources unless `enable_cloudtrail=false` (see [CloudTrail Logs](#cloudtrail-logs))
- AWS CLI: the Kubernetes and Helm providers get cluster tokens with `aws eks get-token`
- Terraform installed (>= 1.3)
- Datadog API key
- Datadog application key only with `enable_cadr_rules=true` — [Organization Settings → Application Keys](https://app.datadoghq.com/organization-settings/application-keys). It needs the `security_monitoring_cws_agent_rules_write` (agent rules) and `security_monitoring_rules_write` (backend rules) permissions. With rules disabled (the default), the Agent and Forwarder need only the API key
- (Optional) Datadog site if yours differs from `datadoghq.com`.

## Deployment

Due to Terraform provider initialization requirements, deployment must be done in **two stages**:

### Stage 1: Create the EKS Cluster and VPC

```bash
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_site=datadoghq.com" \
    -target=module.vpc \
    -target=module.eks
```

**Note**: The `datadog_site` variable is optional and defaults to `datadoghq.com`. Common values include:
- `datadoghq.com`
- `datadoghq.eu`
- `us3.datadoghq.com`
- `us5.datadoghq.com`
- `ap1.datadoghq.com`
- `ddog-gov.com`

This creates:
- VPC with public and private subnets
- EKS cluster with managed node groups
- Required IAM roles and policies

### Stage 2: Deploy Kubernetes Resources

Once the cluster is created, deploy the Kubernetes resources:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_site=datadoghq.com"
```

This deploys:
- Kubernetes namespaces (`playground` and `datadog`)
- Service accounts and secrets
- Datadog Agent via Helm
- Playground application
- Datadog CSM Threats agent rule `imds_v2_tracking` and the `[CADR] Cryptomining attack chain detected` backend rule, if enabled (see [Datadog Resources](#datadog-resources))
- AWS CloudTrail collection into Datadog, unless disabled (see [CloudTrail Logs](#cloudtrail-logs))

## Optional Variables

Each optional variable defaults to the behavior described above.

| Variable | Default | Use |
|---|---|---|
| `region` | `eu-west-3` | AWS region |
| `tags` | `{}` | Tags added to every AWS resource Terraform creates |
| `enable_cloudtrail` | `true` | Collect CloudTrail logs into Datadog for Cloud SIEM (see [CloudTrail Logs](#cloudtrail-logs)); set `false` to skip |
| `enable_eks_audit_logs_to_datadog` | `true` | Subscribe the EKS control-plane audit log group to the Datadog Forwarder so audit events reach Datadog (see [EKS Audit Logs](#eks-audit-logs)); set `false` to leave them in CloudWatch only |
| `enable_cadr_rules` | `false` | Create the `[CADR]` agent and backend rules (see [Datadog Resources](#datadog-resources)), for agents older than 7.84 whose default rules don't cover these detections |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | CIDR blocks allowed to reach the public EKS API endpoint |
| `access_entries` | `{}` | Extra EKS access entries, for example to give another IAM principal access to the cluster |
| `exclude_zone_ids` | `[]` | Availability zone IDs never used for the cluster, for example `use1-az3`, which EKS doesn't support |
| `datadog_helm_chart_version` | latest | Version of the `datadog` Helm chart |
| `extra_agent_values` | `[]` | Helm values applied after `deploy/datadog-agent.yaml`, for example to pin the agent image |
| `playground_image` | image in `deploy/app.yaml` | Image of the `playground-app` container |
| `langflow_image` | image in `deploy/langflow-vulnerable.yaml` | Image of the `langflow-vulnerable` container |
| `langflow_service` | none | Service exposing `langflow-vulnerable` on port 7860 |

A `LoadBalancer` `langflow_service` needs `source_ranges`, each an IPv4 CIDR block no broader than `/16`: `langflow-vulnerable` is exploitable (CVE-2025-3248). For example, to reach it from a single IP through a Network Load Balancer:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var='langflow_service={type="LoadBalancer", source_ranges=["203.0.113.10/32"], annotations={"service.beta.kubernetes.io/aws-load-balancer-type"="nlb"}}'
terraform output -raw langflow_lb_hostname
```

## Use as a Module

Other configurations can call this folder as a module, pinned to a release:

```hcl
module "playground" {
  source = "git::https://github.com/DataDog/datadog-security-playground.git//terraform/eks?ref=<release>"

  region          = "us-east-1"
  datadog_api_key = var.datadog_api_key
  # datadog_app_key is only needed with enable_cadr_rules=true.
}
```

- Terraform downloads the whole repository, so the module still finds `deploy/`.
- The two stages still apply, with the module prefix: first `terraform apply -target=module.playground.module.vpc -target=module.playground.module.eks`, then `terraform apply`.
- The module configures its own providers, so its `module` block can't use `count`, `for_each`, or `depends_on`.

Callers depend on the variable and output names: see `AGENTS.md` before renaming or removing one.

## Checks

CI checks formatting and validates the module when `terraform/eks` or `deploy` changes. To run the same checks locally from the repository root:

```bash
terraform fmt -check -recursive terraform/eks
terraform -chdir=terraform/eks init -backend=false
terraform -chdir=terraform/eks validate
```

## Access the Cluster

Update your kubeconfig to access the cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

## Datadog Resources

`datadog.tf` manages Datadog resources through the Datadog provider, independently of the cluster. They, and the backend rule below, are only created with `enable_cadr_rules=true`: it's off by default because the default rules of agents 7.84 and later already cover these detections.

- The `[CADR] IMDSv2 tracking` policy and its `imds_v2_tracking` agent rule: tracks IMDSv2 responses carrying AWS HMAC credentials; the rule's events are consumed by backend rules via `@agent.rule_id:imds_v2_tracking`. The policy is scoped to hosts tagged `env:playground-env` (from `DD_ENV` in `deploy/datadog-agent.yaml`), so it doesn't apply to hosts outside this playground.

To apply only the Datadog resources, without touching the cluster:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_app_key=YOUR_APP_KEY_HERE" \
    -var="datadog_site=datadoghq.com" \
    -var="enable_cadr_rules=true" \
    -target=datadog_csm_threats_agent_rule.imds_v2_tracking \
    -target=datadog_security_monitoring_rule.cryptomining_attack_chain_detected
```

### Backend Rules

`datadog-backend.tf` manages backend detection rules (`datadog_security_monitoring_rule`), which run in the Datadog backend:

- **`[CADR] Cryptomining attack chain detected`**: correlates cryptomining indicators (miner execution, pool connection, persistence, system optimization) and IMDSv2 credential resolution within the same execution context (`@process.variables.correlation_key`); critical/high/medium depending on the combination.

## CloudTrail Logs

`cloudtrail.tf` ships AWS CloudTrail logs to Datadog so Cloud SIEM can raise signals from the API calls the [langflow-rce](../../scenarios/langflow-rce) scenario makes with stolen node credentials, such as the cross-region `RunInstances` pivot. It follows the [CloudTrail logs setup](https://docs.datadoghq.com/security/cloud_security_management/setup/cloudtrail_logs/), reuses `datadog_api_key`, and is **on by default**; set `enable_cloudtrail=false` to skip it.

It creates:

- a **multi-region** CloudTrail trail (management events) writing to a dedicated S3 bucket. Multi-region matters: the scenario's credential pivot calls `RunInstances` in regions other than the cluster's, which a single-region trail would miss.
- the **Datadog Forwarder** Lambda, from Datadog's pinned CloudFormation template, with an S3 trigger on that bucket. Forwarded logs arrive tagged `source:cloudtrail` and `env:playground-env`.

Notes:

- **Cloud SIEM must be enabled** for your Datadog org — it is an account-level product, not something Terraform configures here. Once on, the out-of-the-box AWS CloudTrail detection rules generate signals from these logs.
- The applying AWS principal needs permission to create CloudTrail, S3, Lambda, IAM, CloudFormation, Secrets Manager, and CloudWatch Logs resources: the Forwarder stack runs with the principal's credentials and creates the Lambda's execution role, an API key secret, and a log group.
- Confirm logs are arriving in [Log Explorer](https://app.datadoghq.com/logs) with `source:cloudtrail`.
- AWS cost stays low for a short-lived demo: the bucket expires objects after 7 days, and a trail's first copy of management events is free. If the account already has a management-events trail, this second copy is billed per event.
- The trail records every management event in the account, not only the playground's, and all of them are billed as Datadog logs and Cloud SIEM analyzed logs. In a busy shared account, or one whose CloudTrail already reaches Datadog (which duplicates logs and signals), set `enable_cloudtrail=false`.
- AWS allows 5 trails per region per account, and a multi-region trail counts in every region: several playgrounds in one account can hit `MaximumNumberOfTrailsExceededException`.

## EKS Audit Logs

`audit-logs.tf` forwards the EKS control-plane audit log to Datadog, so Kubernetes audit detections work: without it, the audit log exists only in CloudWatch (managed EKS writes no audit file on the nodes the Agent could mount), and every control-plane-side detection — `User Exec into a Pod`, cluster-admin bindings, impersonation, the audit side of two-plane pod-UID correlation — sees nothing.

It reuses the Datadog Forwarder Lambda from [CloudTrail Logs](#cloudtrail-logs) (creating it if `enable_cloudtrail=false`), and subscribes the log group `/aws/eks/<cluster>/cluster` to it. EKS writes raw Kubernetes audit events to the `kube-apiserver-audit-*` streams in this group. Since this module enables only audit logging, the subscription forwards the full audit stream without filtering events or projecting fields. It is **on by default**; set `enable_eks_audit_logs_to_datadog=false` to skip.

Verify after the first apply:

1. Wait a few minutes — audit events transit CloudWatch before the Forwarder sees them.
2. In [Log Explorer](https://app.datadoghq.com/logs), filter `source:kubernetes.audit`: events from `audit.k8s.io` should appear. If they arrive under a different `source`, add a pipeline remapping it to `kubernetes.audit` (match on the `@aws.awslogs.logGroup` attribute), since the out-of-the-box Kubernetes audit rules query `source:kubernetes.audit`.
3. End-to-end check: `kubectl exec` into the `playground-app` pod, then find the matching `create pods/exec` audit event with `source:kubernetes.audit @objectRef.subresource:exec`.

Notes:

- EKS manages the audit policy: exec requests should arrive with their request object. Verify with the end-to-end check above before writing rules that depend on request bodies.
- Denied requests are forwarded too (no filter pattern) — several detections key on them.
- Audit volume on a short-lived demo cluster is small; every event is billed as a Datadog log.

## What Gets Deployed

### Namespaces
- **`playground`**: Contains the vulnerable security playground application
- **`datadog`**: Contains the Datadog Agent for monitoring and security

### Resources
- EKS cluster (v1.29) with 2 managed node groups
- Datadog Agent deployed via Helm chart
- Ubuntu test pod for experimentation
- Pod Identity associations for AWS IAM integration
- Multi-region CloudTrail trail, S3 bucket, and Datadog Forwarder Lambda (unless `enable_cloudtrail=false`)
- CloudWatch subscription sending the EKS control-plane audit log to the Forwarder (unless `enable_eks_audit_logs_to_datadog=false`)
- `[CADR]` agent and backend detection rules (only with `enable_cadr_rules=true`)

## File Structure

- `main.tf`: EKS cluster, VPC, and provider configurations
- `k8s.tf`: Kubernetes resources (namespaces, deployments, etc.)
- `datadog.tf`: Datadog provider and CSM Threats agent rules
- `datadog-backend.tf`: Datadog backend detection rules
- `cloudtrail.tf`: CloudTrail trail, S3 bucket, and Datadog Forwarder for Cloud SIEM
- `audit-logs.tf`: CloudWatch subscription forwarding the EKS audit log group to the Forwarder
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `terraform.tf`: Terraform and provider version constraints
- `AGENTS.md`: Constraints to keep in mind when changing this folder

## Troubleshooting

**AWS token expires**: Get fresh credentials.

**`executable aws not found`**: Install the AWS CLI; the Kubernetes and Helm providers run `aws eks get-token`.

**Provider initialization errors**: Make sure to follow the two-stage deployment process. The Kubernetes provider needs the cluster to exist before it can initialize.

**`AccessDenied` on CloudTrail, CloudFormation, or Lambda, or `MaximumNumberOfTrailsExceededException`**: CloudTrail collection is on by default; set `enable_cloudtrail=false` if the account doesn't allow it (see [CloudTrail Logs](#cloudtrail-logs)).