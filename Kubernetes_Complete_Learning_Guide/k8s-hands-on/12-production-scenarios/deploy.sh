#!/bin/bash
# Production Zero-Downtime Deployment Script
# Usage: ./deploy.sh <image-tag>
# Example: ./deploy.sh myapp:2.1.0

set -euo pipefail

NAMESPACE="production"
DEPLOYMENT="webapp"
NEW_IMAGE="${1:-myapp:2.1.0}"
TIMEOUT="5m"
HEALTH_URL="http://localhost:80/health"

echo "=================================================="
echo " Production Deploy: $NEW_IMAGE"
echo "=================================================="

echo ""
echo "=== Step 1: Pre-deployment health check ==="
UNHEALTHY=$(kubectl get nodes | grep -c NotReady || true)
if [ "$UNHEALTHY" -gt 0 ]; then
  echo "FAIL: $UNHEALTHY unhealthy nodes detected"
  kubectl get nodes
  exit 1
fi
echo "✓ All nodes are Ready"

echo ""
echo "=== Step 2: Check PodDisruptionBudgets ==="
kubectl get pdb -n "$NAMESPACE" || echo "(no PDBs found)"

echo ""
echo "=== Step 3: Save current revision for rollback ==="
CURRENT_REVISION=$(kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE" \
  --no-headers 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
echo "Current revision: $CURRENT_REVISION"

echo ""
echo "=== Step 4: Deploy $NEW_IMAGE ==="
kubectl set image deployment/"$DEPLOYMENT" webapp="$NEW_IMAGE" -n "$NAMESPACE"
kubectl annotate deployment/"$DEPLOYMENT" \
  kubernetes.io/change-cause="Deploy $NEW_IMAGE by ${USER:-ci} at $(date)" \
  -n "$NAMESPACE" --overwrite

echo ""
echo "=== Step 5: Wait for rollout ==="
if ! kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
  echo "FAIL: Rollout timed out or failed! Rolling back..."
  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE" \
    --to-revision="$CURRENT_REVISION"
  echo "Rollback initiated to revision $CURRENT_REVISION"
  exit 1
fi
echo "✓ Rollout completed"

echo ""
echo "=== Step 6: Smoke test ==="
POD=$(kubectl get pod -n "$NAMESPACE" -l app=webapp \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
  echo "FAIL: No pods found for app=webapp in $NAMESPACE"
  exit 1
fi

RESPONSE=$(kubectl exec "$POD" -n "$NAMESPACE" -- \
  curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null || echo "000")

if [ "$RESPONSE" != "200" ]; then
  echo "FAIL: Health check returned HTTP $RESPONSE – rolling back"
  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
  exit 1
fi
echo "✓ Health check passed (HTTP 200)"

echo ""
echo "=== Step 7: Post-deploy summary ==="
kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app=webapp -o wide

echo ""
echo "=================================================="
echo "SUCCESS: $NEW_IMAGE deployed to $NAMESPACE"
echo "=================================================="
