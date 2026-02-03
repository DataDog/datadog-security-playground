# JuiceShop Deployment

This directory contains Kubernetes manifests for deploying OWASP JuiceShop with MySQL database.

## Components

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates the `playground` namespace |
| `db-service.yaml` | MySQL service (internal, port 3306) |
| `db-deployment.yaml` | MySQL 8.0 deployment |
| `juiceshop-service.yaml` | JuiceShop service (port 8081 → 3000) |
| `juiceshop-deployment.yaml` | JuiceShop app with Datadog APM (contains template variables) |
| `juiceshop-networkpolicy.yaml` | Restricts access to cluster-internal only |
| `kustomization.yaml` | Kustomize orchestration file |

## Manual Deployment

### Prerequisites

Set your Datadog credentials as environment variables:

```bash
export DD_API_KEY="your-datadog-api-key"
export DD_SITE="datadoghq.com"  # or datadoghq.eu, us3.datadoghq.com, etc.
```

### Deploy

The `juiceshop-deployment.yaml` contains template variables (`${dd_api_key}`, `${dd_site}`) used by Terraform. For manual deployment, substitute them with `sed`:

```bash
# Create namespace first
kubectl apply -f deploy/juiceshop/namespace.yaml

# Deploy db and other resources (no template vars)
kubectl apply -f deploy/juiceshop/db-service.yaml
kubectl apply -f deploy/juiceshop/db-deployment.yaml
kubectl apply -f deploy/juiceshop/juiceshop-networkpolicy.yaml
kubectl apply -f deploy/juiceshop/juiceshop-service.yaml

# Deploy juiceshop with variable substitution
sed -e "s/\${dd_api_key}/$DD_API_KEY/g" \
    -e "s/\${dd_site}/$DD_SITE/g" \
    deploy/juiceshop/juiceshop-deployment.yaml | kubectl apply -f -

# Verify pods are running
kubectl get pods -n playground -w
```

### Access

JuiceShop is not exposed externally (by design). Use port-forward to access locally:

```bash
kubectl port-forward svc/juiceshop 8081:8081 -n playground
```

Then open http://localhost:8081

### Tear Down

```bash
kubectl delete -k deploy/juiceshop/
```

## Alternative: Apply Individual Files

If you don't have kustomize, apply files manually:

```bash
kubectl apply -f deploy/juiceshop/namespace.yaml
kubectl apply -f deploy/juiceshop/db-service.yaml
kubectl apply -f deploy/juiceshop/db-deployment.yaml
kubectl apply -f deploy/juiceshop/juiceshop-networkpolicy.yaml
kubectl apply -f deploy/juiceshop/juiceshop-service.yaml
kubectl apply -f deploy/juiceshop/juiceshop-deployment.yaml
```

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n playground
kubectl describe pod -l app=juiceshop -n playground
```

### Check logs
```bash
kubectl logs -l app=juiceshop -n playground --tail=100
kubectl logs -l app=db -n playground --tail=100
```

### Database connection issues
JuiceShop connects to MySQL via hostname `db`. Ensure the db pod is ready before JuiceShop starts:
```bash
kubectl get pods -n playground -w
```

## Security Notes

- JuiceShop is intentionally vulnerable - never expose it to the internet
- NetworkPolicy restricts ingress to cluster-internal traffic only
- Service type is ClusterIP (no external LoadBalancer/NodePort)
- Use `kubectl port-forward` for local access only
