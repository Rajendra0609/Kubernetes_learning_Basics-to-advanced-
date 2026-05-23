#!/usr/bin/env bash
# =============================================================
# cluster-health.sh — Cluster Health Snapshot
# Capstone Solution: Section 1 — Cluster Architecture
# =============================================================
# Usage: ./cluster-health.sh [--namespace <ns>] [--json]
# Exit: 0 = all PASS, 1 = one or more checks FAILED
# =============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

FAILURES=0
WARNINGS=0

pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; ((FAILURES++)); }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; ((WARNINGS++)); }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
header(){ echo -e "\n${BOLD}══════════════════════════════════════════${NC}"; echo -e "${BOLD} $* ${NC}"; echo -e "${BOLD}══════════════════════════════════════════${NC}"; }

# ── 1. Node health ─────────────────────────────────────────
header "1. NODE STATUS"
NOT_READY=$(kubectl get nodes --no-headers | grep -v " Ready" | grep -v "SchedulingDisabled" || true)
if [[ -z "$NOT_READY" ]]; then
  NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
  pass "All $NODE_COUNT nodes are Ready"
else
  fail "Nodes NOT Ready:"
  echo "$NOT_READY"
  echo "--- Events for problem nodes ---"
  while IFS= read -r line; do
    NODE=$(echo "$line" | awk '{print $1}')
    kubectl describe node "$NODE" | grep -A5 "Events:" || true
  done <<< "$NOT_READY"
fi

# ── 2. Node resource utilization ────────────────────────────
header "2. NODE RESOURCE UTILIZATION"
if kubectl top nodes 2>/dev/null; then
  true
else
  warn "metrics-server not available — install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

# ── 3. Problem pods (non Running/Completed/Succeeded) ───────
header "3. POD HEALTH (all namespaces)"
BAD_PODS=$(kubectl get pods --all-namespaces --no-headers \
  | grep -v -E "\s(Running|Completed|Succeeded)\s" || true)
if [[ -z "$BAD_PODS" ]]; then
  pass "All pods are in Running/Completed state"
else
  fail "Pods NOT in healthy state:"
  echo "$BAD_PODS"
fi

# ── 4. High restart count pods ──────────────────────────────
header "4. CRASH-LOOPING / HIGH-RESTART PODS"
HIGH_RESTART=$(kubectl get pods --all-namespaces --no-headers \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount' \
  2>/dev/null | awk '$3+0 > 5 {print}' || true)
if [[ -z "$HIGH_RESTART" ]]; then
  pass "No pods with >5 restarts"
else
  fail "High restart pods:"
  echo "$HIGH_RESTART"
fi

# ── 5. CoreDNS check ────────────────────────────────────────
header "5. COREDNS"
DNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null || true)
DNS_RUNNING=$(echo "$DNS_PODS" | grep -c "Running" || true)
if [[ "$DNS_RUNNING" -ge 1 ]]; then
  pass "CoreDNS: $DNS_RUNNING pod(s) running"
else
  fail "CoreDNS pods not running!"
  echo "$DNS_PODS"
fi

# ── 6. Control plane component health ───────────────────────
header "6. CONTROL PLANE COMPONENTS"
for comp in kube-apiserver kube-controller-manager kube-scheduler etcd; do
  POD=$(kubectl get pods -n kube-system --no-headers 2>/dev/null \
    | grep "$comp" | head -1 || true)
  if [[ -n "$POD" ]]; then
    STATUS=$(echo "$POD" | awk '{print $4}')
    if [[ "$STATUS" == "Running" ]]; then
      pass "$comp: Running"
    else
      fail "$comp: $STATUS"
    fi
  else
    warn "$comp: not found as pod (may be external/managed)"
  fi
done

# ── 7. PVC health ────────────────────────────────────────────
header "7. PERSISTENT VOLUME CLAIMS"
PENDING_PVC=$(kubectl get pvc --all-namespaces --no-headers \
  | grep -v "Bound" || true)
if [[ -z "$PENDING_PVC" ]]; then
  pass "All PVCs are Bound"
else
  fail "Unbound PVCs:"
  echo "$PENDING_PVC"
fi

# ── 8. Certificate expiry (control plane) ───────────────────
header "8. CERTIFICATE EXPIRY"
if command -v kubeadm &>/dev/null; then
  kubeadm certs check-expiration 2>/dev/null | grep -E "(CERTIFICATE|EXPIRES)" | head -20 || true
else
  warn "kubeadm not found — skipping cert check"
fi

# ── Summary ──────────────────────────────────────────────────
header "SUMMARY"
echo -e "Failures : ${RED}${FAILURES}${NC}"
echo -e "Warnings : ${YELLOW}${WARNINGS}${NC}"
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✔ Cluster health: PASS${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}✘ Cluster health: FAIL — $FAILURES issue(s) found${NC}"
  exit 1
fi
