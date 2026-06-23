# Cloud Access - AWS Credential Theft and Resource Abuse

- **Location**: `scenarios/cloud-access/`
- **Description**: Simulates cloud credential theft and resource abuse by retrieving AWS credentials from the Instance Metadata Service (IMDS) and attempting to launch expensive EC2 instances across multiple regions. This demonstrates how attackers pivot from workload compromise to cloud infrastructure abuse.
- **Attack Vector**: IMDS credential theft, unauthorized EC2 instance launches
- **Impact**: Cloud credential theft, unauthorized resource provisioning, financial abuse
- **Detection**: CloudTrail events for unauthorized EC2 RunInstances calls, IMDS access patterns

## How to Run

```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it -n playground deploy/playground-app -- /scenarios/cloud-access/detonate.sh --wait
```
