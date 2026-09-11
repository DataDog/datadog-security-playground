# Terraform for EKS

The Terraform code inside this repository provides a simple way to create an EKS cluster with Datadog monitoring and a security playground application.

## Prerequisites

- AWS credentials configured or passed as environment variables
- Terraform installed (>= 1.0)
- Datadog API key
- Datadog application key with the `security_monitoring_cws_agent_rules_write` permission (agent rules, `datadog.tf`) and the `security_monitoring_rules_write` permission (backend rules, `datadog-backend.tf`) — [Organization Settings → Application Keys](https://app.datadoghq.com/organization-settings/application-keys)
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
    -var="datadog_app_key=YOUR_APP_KEY_HERE" \
    -var="datadog_site=datadoghq.com"
```

This deploys:
- Kubernetes namespaces (`playground` and `datadog`)
- Service accounts and secrets
- Datadog Agent via Helm
- Playground application
- Datadog CSM Threats agent rule `imds_host_aws_access_key_ids` (see [Datadog resources](#datadog-resources))

## Access the Cluster

Update your kubeconfig to access the cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

## Datadog Resources

`datadog.tf` manages Datadog resources through the Datadog provider, independently of the cluster:

- `imds_host_aws_access_key_ids` agent rule ([csm_threats_agent_rule](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/csm_threats_agent_rule)): tracks the AWS access key IDs a host resolved from IMDS to correlate its activity with Cloud SIEM and CloudTrail. Mirrors the upstream default rule from `security-monitoring/workload-security/agent-rules/linux/network/imds_host_aws_access_key_ids.yaml`.
- The rule is attached to and enabled in the org's default CSM Threats policy (`Default Policy`), which is the policy the helm-deployed agent uses.
- A second agent rule, `imds_v2_tracking`, lives in its own `[CADR] IMDSv2 tracking` policy. It tracks IMDSv2 responses carrying AWS HMAC security credentials; its events are consumed by backend correlation rules via `@agent.rule_id:imds_v2_tracking` (see the `[CADR] Cryptomining attack chain detected` backend rule). The `@process.variables.correlation_key` it relies on is populated by the default execution-context agent rules, so it needs no set action. Without `host_tags_lists`, the policy applies to all hosts — set them to scope it to a subset of hosts.

To test the Datadog resources alone, without touching the cluster:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_app_key=YOUR_APP_KEY_HERE" \
    -var="datadog_site=datadoghq.com" \
    -target=datadog_csm_threats_agent_rule.imds_host_aws_access_key_ids
```

Notes:
- The rule is set to `silent = true`: it only enriches events with the `host_aws_access_key_ids` set action and does not generate signals on its own.
- `priority`, `osFilter`, `agentConstraint` and `category` from the upstream YAML are not part of the agent-rule create/update API and are not carried over — the rule behavior lives in `expression` + `actions`.
- The action TTL (`12h` in the YAML) is expressed in nanoseconds in the provider (`43200000000000`).

### Backend Rules

`datadog-backend.tf` manages backend detection rules (`datadog_security_monitoring_rule`), which run in the Datadog backend instead of in the agent:

- **`[CADR] Cryptomining attack chain detected`** (type `workload_security`): correlates cryptomining indicators (miner execution, pool connection, persistence setup, system optimization) plus IMDSv2 cloud credential resolution (`@agent.rule_id:imds_v2_tracking`, provided by the agent rule in the `[CADR] IMDSv2 tracking` policy) within the same execution context (`@process.variables.correlation_key`), and raises signals at critical/high/medium severity depending on the combination.
- Backend rules use the security monitoring rules API, which requires the `security_monitoring_rules_write` permission on the application key.

## What Gets Deployed

### Namespaces
- **`playground`**: Contains the vulnerable security playground application
- **`datadog`**: Contains the Datadog Agent for monitoring and security

### Resources
- EKS cluster (v1.29) with 2 managed node groups
- Datadog Agent deployed via Helm chart
- Ubuntu test pod for experimentation
- Pod Identity associations for AWS IAM integration

## File Structure

- `main.tf`: EKS cluster, VPC, and provider configurations
- `k8s.tf`: Kubernetes resources (namespaces, deployments, etc.)
- `datadog.tf`: Datadog provider and CSM Threats agent rules
- `datadog-backend.tf`: Datadog backend security monitoring rules
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `terraform.tf`: Terraform and provider version constraints

## Troubleshooting

**AWS token expires**: Get fresh credentials.

**Provider initialization errors**: Make sure to follow the two-stage deployment process. The Kubernetes provider needs the cluster to exist before it can initialize.