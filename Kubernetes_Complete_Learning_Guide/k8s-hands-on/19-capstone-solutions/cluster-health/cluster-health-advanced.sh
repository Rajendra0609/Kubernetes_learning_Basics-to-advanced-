#!/usr/bin/env bash
# ============================================================
# cluster-health-advanced.sh — Full Cluster Health Report
# Capstone Solution: Section 1 (complete implementation)
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

FAILURES=0; WARNINGS=0
REPORT_FILE="/tmp/cluster-health-$(date +%Y%m%d-%H%M%S).txt"

pass()  { local m="[PASS] $*"; echo -e "${GREEN}${m}${NC}"; echo "$m" >> "$REPORT_FILE"; }
fail()  { local m="[FAIL] $*"; echo -e "${RED}${m}${NC}"; echo "$m" >> "$REPORT_FILE"; ((FAILURES++)); }
warn()  { local m="[WARN] $*"; echo -e "${YELLOW}${m}${NC}"; echo "$m" >> "$REPORT_FILE"; ((WARNINGS++)); }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
header(){ echo -e "\n${BOLD}━━━ $* ━━━${NC}"; echo "=== $* ===" >> "$REPORT_FILE"; }

echo "Cluster Health Report — $(date)" > "$REPORT_FILE"
echo "Cluster: $(kubectl config current-context)" >> "$REPORT_FILE"

header "1. NODES"
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" || true)
if [[ -z "$NOT_READY" ]]; then
  NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
  pass "All $NODE_COUNT nodes Ready"
else
  fail "Nodes NOT Ready:"; echo "$NOT_READY"
  while IFS= read -r line; do
    NODE=$(echo "$line" | awk '{print $1}')
    kubectl describe node "$NODE" | tail -20
  done <<< "$NOT_READY"
fi

header "2. NODE UTILIZATION"
kubectl top nodes 2>/dev/null || warn "metrics-server unavailable"

header "3. UNHEALTHY PODS"
BAD=$(kubectl get pods -A --no-headers | grep -vE "\s+(Running|Completed|Succeeded)\s+" | grep -v "Terminating" || true)
[[ -z "$BAD" ]] && pass "All pods healthy" || { fail "Problem pods:"; echo "$BAD"; }

header "4. HIGH-RESTART PODS (>5)"
kubectl get pods -A --no-headers \
  -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
  2>/dev/null | awk '$3+0>5{print}' | while read -r line; do fail "$line"; done || true
pass "Restart check complete"

header "5. COREDNS"
DNS_COUNT=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c Running || echo 0)
[[ "$DNS_COUNT" -ge 1 ]] && pass "CoreDNS: $DNS_COUNT pod(s) running" || fail "CoreDNS not running!"

header "6. PENDING/UNBOUND PVCs"
PENDING=$(kubectl get pvc -A --no-headers | grep -v Bound || true)
[[ -z "$PENDING" ]] && pass "All PVCs Bound" || { fail "Unbound PVCs:"; echo "$PENDING"; }

header "7. EXPIRING CERTIFICATES (within 30 days)"
if command -v kubeadm &>/dev/null; then
  kubeadm certs check-expiration 2>/dev/null | grep -E "EXPIRES|days" | head -20 || true
  EXPIRING=$(kubeadm certs check-expiration 2>/dev/null | awk '/[0-9]+ days/{if($NF+0 < 30) print}' || true)
  [[ -z "$EXPIRING" ]] && pass "No certs expiring within 30 days" || fail "EXPIRING CERTS: $EXPIRING"
else
  warn "kubeadm not found — skipping cert check"
fi

header "8. RESOURCE QUOTA PRESSURE (>80% used)"
kubectl get resourcequota -A --no-headers -o json 2>/dev/null | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
  ns = item['metadata']['namespace']
  hard = item['status'].get('hard', {})
  used = item['status'].get('used', {})
  for key in hard:
    h = hard[key].rstrip('Ki').rstrip('Mi').rstrip('Gi')
    u = used.get(key, '0').rstrip('Ki').rstrip('Mi').rstrip('Gi')
    try:
      pct = float(u) / float(h) * 100
      if pct > 80:
        print(f'WARN {ns} {key}: {used.get(key,\"0\")}/{hard[key]} ({pct:.0f}% used)')
    except: pass
" || true
pass "Quota check complete"

header "SUMMARY"
echo -e "Failures: ${RED}${FAILURES}${NC}  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo "Report saved to: $REPORT_FILE"
[[ $FAILURES -eq 0 ]] && { echo -e "${GREEN}${BOLD}✔ CLUSTER HEALTHY${NC}"; exit 0; } || \
  { echo -e "${RED}${BOLD}✘ CLUSTER ISSUES: $FAILURES failure(s)${NC}"; exit 1; }
