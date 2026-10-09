# AGENTS.md: terraform/eks

This folder is run directly (two-stage apply, see README.md) and is also called as a Terraform module pinned with
`?ref=<release>` (README.md, "Use as a Module").

## Module callers

- Callers depend on the variable and output names, on module.vpc and module.eks as first-stage targets, and on
  deploy/*.yaml being read through ../../deploy. Module downloads fetch the whole repository; keep deploy/ at the root.
- To rename or remove one of these, add the new name, release, give callers time to switch, then remove the old one.

## Rules

- New variables default to the current behavior.
- Provider blocks live in this folder, so callers can't pass providers or use count, for_each, or depends_on on the
  module block. Keep it working as a single plain module call.
- The Kubernetes and Helm providers authenticate with `aws eks get-token --output json`: a static token expires
  before long applies finish.
- DD_ENV in deploy/datadog-agent.yaml and the env:playground-env scope of the `[CADR] IMDSv2 tracking` policy change
  together.
- The CADR backend rule groups by @process.variables.correlation_key, which needs agent 7.68 or later.
- The cloud-access and langflow-rce scenarios rely on pods reaching IMDSv2: keep the node groups' default hop limit
  of 2.
- langflow-vulnerable is vulnerable by design. Keep the langflow_service validations that limit a load balancer to
  narrow IPv4 source ranges.
- Publishing a GitHub release also publishes the ghcr.io images and moves :latest
  (.github/workflows/publish-image.yaml).

## Verify

Run the commands in the README's Checks section. CI (.github/workflows/terraform.yaml) runs them with a pinned
Terraform version.
