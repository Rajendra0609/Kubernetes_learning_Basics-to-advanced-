# Kubernetes Hands-On: Capstone Projects & Gap Analysis
# Generated: 2026-05-12

---

## GAP ANALYSIS – What Was Missing From the Guide

| # | Missing Topic | File Added | Why It Matters |
|---|---------------|------------|----------------|
| 1 | **Startup Probe** (all 4 probe types shown but startup missing) | `00-MISSING-ADDITIONS/probes-complete.yaml` | Prevents liveness from killing slow-starting containers |
| 2 | **Exec probe** (command-based health check) | `00-MISSING-ADDITIONS/probes-complete.yaml` | Essential for databases that have no HTTP endpoint |
| 3 | **TCP Socket probe** | `00-MISSING-ADDITIONS/probes-complete.yaml` | Used for Redis, Kafka, message brokers |
| 4 | **gRPC probe** (k8s 1.24+) | `00-MISSING-ADDITIONS/probes-complete.yaml` | Modern microservices use gRPC not HTTP |
| 5 | **Lifecycle hooks** (postStart / preStop) | `00-MISSING-ADDITIONS/lifecycle-hooks.yaml` | Critical for zero-downtime graceful shutdown |
| 6 | **terminationGracePeriodSeconds** explained | `00-MISSING-ADDITIONS/pod-termination-lifecycle.yaml` | Without this, rolling updates drop requests |
| 7 | **VPA (Vertical Pod Autoscaler)** – in TOC but not written | `09-autoscaling/vpa.yaml` | Right-sizes pods based on actual usage |
| 8 | **Init containers** – only basic example, no patterns | `00-MISSING-ADDITIONS/init-containers-advanced.yaml` | DB migrations, wait-for-deps, permission fixers |
| 9 | **successThreshold** on readiness probes not explained | `00-MISSING-ADDITIONS/probes-complete.yaml` | Prevents flapping – pod must pass N checks in a row |
| 10 | **Named ports** in probe definitions | `00-MISSING-ADDITIONS/probes-complete.yaml` | Best practice so port changes don't break probes |
| 11 | **Probe failureThreshold / timeoutSeconds** not configured | All probe yamls | Without these, defaults may be too aggressive |

---

## SECTION 1: Cluster Architecture & Setup Verification
### Capstone Project: Cluster Health Dashboard Script

**Scenario:** You just joined a company as a platform engineer. On day one, your TL asks you to
write a bash script that gives a complete health snapshot of any cluster.

**Requirements:**
1. Check all nodes are Ready; if any are NotReady, print their events.
2. List all pods that are NOT in Running or Completed state.
3. Show CPU and memory utilization per node (using `kubectl top`).
4. List any pods that have been restarted more than 5 times.
5. Check that CoreDNS pods are running.
6. Output a "PASS" or "FAIL" summary with an exit code 1 on any failure.

**Goal:** Run `./cluster-health.sh` and get a clean, actionable report.

**Interview angle:** Be ready to explain what happens when etcd is down, when the scheduler is
down, and how the cluster behaves when only the API server is restarted.

---

## SECTION 2: Core Kubernetes Objects
### Capstone Project: Multi-Tier Pod Design

**Scenario:** Deploy a web scraper application using the sidecar pattern.

**Requirements:**
1. Create a Pod with three containers:
   - `scraper`: runs a Python script that writes results to `/shared/results.json` every 30s.
   - `api-sidecar`: runs a simple HTTP server (e.g. `python -m http.server 8080`) serving `/shared/`.
   - `log-sidecar`: tails `/shared/results.json` and prints new entries to stdout.
2. All three share an `emptyDir` volume.
3. Add a **startup probe**, **liveness probe**, and **readiness probe** to the `api-sidecar`.
4. Set resource requests and limits on all containers.
5. Add an `initContainer` that creates `/shared/results.json` with an initial empty JSON array `[]`.

**Challenge:** What happens if the `scraper` container crashes? Does the pod restart? Why?

**Deployment:** Apply the YAML and use `kubectl exec` to verify data flows between containers.

---

## SECTION 3: Workload Management
### Capstone Project: Safe Canary Release Pipeline

**Scenario:** Your team wants to release v2.0 of an API. You must:

**Step 1 – Blue-Green smoke test:**
1. Deploy `webapp-blue` (nginx:1.25) with 3 replicas behind `webapp-svc` selecting `slot: blue`.
2. Deploy `webapp-green` (nginx:1.26) with 3 replicas.
3. Use `kubectl port-forward` to manually test the green deployment.
4. Switch the service selector to `slot: green` with a single `kubectl patch` command.
5. Scale blue to 0 only AFTER confirming green is healthy.

**Step 2 – Canary with traffic splitting:**
1. Delete both deployments and recreate: `webapp-stable` (19 replicas, nginx:1.25).
2. Add `webapp-canary` (1 replica, nginx:1.26).
3. Run a load test loop: `for i in $(seq 1 100); do curl http://<svc-ip>; done`.
4. Check logs: confirm approximately 5% of requests hit the canary pod.
5. Graduate the canary: scale stable to 0, scale canary to 10, rename it.

**StatefulSet challenge:**
1. Deploy `mongodb-statefulset.yaml`.
2. Exec into `mongodb-0` and create a test collection.
3. Scale the StatefulSet from 3 to 1, then back to 3.
4. Verify the data still exists in `mongodb-0` after scaling.

---

## SECTION 4: Services & Networking
### Capstone Project: Zero-Trust Namespace

**Scenario:** Build a fully locked-down `payment` namespace where ONLY specific traffic is allowed.

**Requirements:**
1. Create namespace `payment` and apply `default-deny-all` (both ingress + egress).
2. Deploy a `payment-api` pod (nginx) and a `fraud-checker` pod (busybox).
3. Apply a NetworkPolicy that ONLY allows:
   - `fraud-checker` → `payment-api` on port 80.
   - `payment-api` → external HTTPS (port 443) for card processing.
   - DNS (UDP/TCP 53) for all pods.
4. Verify:
   - `fraud-checker` CAN curl `payment-api`.
   - A third pod (`kubectl run attacker --image=curlimages/curl`) CANNOT reach `payment-api`.
   - `payment-api` CAN reach `https://httpbin.org/get`.
   - `payment-api` CANNOT reach any internal cluster services.
5. Add an `ipBlock` rule to block a specific external IP (e.g. `1.2.3.4/32`).

**DNS debugging sub-task:**
- Intentionally break DNS by applying a policy that blocks port 53 egress.
- Observe what error message you see when `nslookup` fails inside the pod.
- Fix it and document the exact rule that restores DNS.

---

## SECTION 5: Configuration & Secrets
### Capstone Project: Config Hot-Reload System

**Scenario:** Build an application that detects ConfigMap changes without restarting.

**Requirements:**
1. Create a ConfigMap with a key `app.properties` containing `LOG_LEVEL=INFO`.
2. Mount it as a volume (not env vars – env vars don't hot-reload).
3. Deploy an nginx pod that reads the mounted file and logs its content every 10 seconds
   (use a sidecar `busybox` with `watch -n10 cat /etc/config/app.properties`).
4. Edit the ConfigMap to change `LOG_LEVEL=DEBUG`.
5. Observe (within ~60s) that the sidecar picks up the new value WITHOUT pod restart.

**Secrets challenge:**
1. Create a Secret with username/password.
2. Mount it as a volume with `defaultMode: 0400`.
3. Exec into the pod and verify the file permissions are correct.
4. Try: `kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d` — see the value.
5. Research and explain in comments: why `base64` is NOT encryption and what to use instead.

---

## SECTION 6: Storage
### Capstone Project: Persistent Counter Application

**Scenario:** Build a counter app that survives pod restarts using persistent storage.

**Requirements:**
1. Create a `StorageClass` (or use the default one in your cluster).
2. Create a `PersistentVolumeClaim` for 1Gi storage.
3. Deploy a pod that runs: `while true; do echo $(($(cat /data/count 2>/dev/null || echo 0)+1)) > /data/count; cat /data/count; sleep 5; done`
4. Watch the counter increment. Delete the pod (`kubectl delete pod`).
5. When the pod restarts, verify the counter continues from where it left off (not reset to 0).
6. Expand the PVC from 1Gi to 2Gi using `kubectl patch`.
7. Verify the expansion succeeded with `kubectl describe pvc`.

**StatefulSet storage challenge:**
- Deploy MongoDB StatefulSet with 2 replicas.
- Exec into `mongodb-0`, write a document.
- Delete `mongodb-0` pod (the StatefulSet recreates it).
- Exec into the new `mongodb-0` and verify your document is still there.
- Answer: why is the data still there? What would happen if you used `emptyDir` instead?

---

## SECTION 7: RBAC & Security
### Capstone Project: Least-Privilege Developer Environment

**Scenario:** Your team needs to give a junior developer access to the `dev` namespace only,
with no ability to delete resources or access secrets.

**Requirements:**
1. Create namespace `dev`.
2. Create ServiceAccount `junior-dev-sa` in `dev`.
3. Create a Role that allows: `get, list, watch` on pods, deployments, services; `create, update` on deployments only. No delete. No secrets.
4. Bind the role to `junior-dev-sa`.
5. Test with `kubectl auth can-i`:
   - Can list pods in `dev`? → YES
   - Can delete pods in `dev`? → NO
   - Can get secrets in `dev`? → NO
   - Can do anything in `production`? → NO
6. Deploy a pod that uses `junior-dev-sa` and verify it cannot call `kubectl get secrets` even from inside the pod (using the ServiceAccount token).

**Security hardening challenge:**
- Take the `secure-pod.yaml` and attempt to deploy it.
- If it fails (likely because nginx needs to write to /var/cache), fix it by adding the correct emptyDir volumes.
- Verify the pod is running as non-root: `kubectl exec <pod> -- id`.

---

## SECTION 8: Helm
### Capstone Project: Build and Publish Your Own Chart

**Scenario:** Package the multi-tier application from Section 12 as a Helm chart.

**Requirements:**
1. `helm create myapp` and clean out the defaults.
2. Create templates for: Deployment, Service, ConfigMap, HPA, Ingress.
3. In `values.yaml` expose: `replicaCount`, `image.tag`, `ingress.host`, `resources.*`, `autoscaling.enabled`.
4. Add a `_helpers.tpl` with a named template for labels (use `{{ include "myapp.labels" . }}`).
5. Add an `NOTES.txt` that prints the URL to reach the app after install.
6. Run `helm lint myapp/` — fix all warnings.
7. Install with: `helm install myapp ./myapp --set ingress.host=test.local --dry-run` first, then for real.
8. Upgrade: change `image.tag` and run `helm upgrade --atomic --timeout 3m`.
9. Run `helm rollback myapp 1` and verify the old version is restored.

**Bonus:** Add a `Chart.lock` and a dependency on the `bitnami/redis` chart.

---

## SECTION 9: Auto-Scaling
### Capstone Project: Load Test + Auto-Scale Observation

**Scenario:** Prove that HPA works end-to-end under real load.

**Requirements:**
1. Deploy the webapp with: `requests.cpu: 100m`, `limits.cpu: 500m`.
2. Apply the HPA targeting 50% CPU utilization, min=2, max=10.
3. Install `metrics-server` (required for HPA).
4. Verify: `kubectl top pods` shows CPU numbers.
5. Generate load with:
   ```
   kubectl run load-gen --image=busybox --rm -it --restart=Never \
     -- sh -c 'while true; do wget -q -O- http://webapp-clusterip; done'
   ```
6. In a second terminal, watch: `kubectl get hpa -w`.
7. Observe pods scaling UP. Record how long it takes.
8. Stop the load generator. Observe pods scaling DOWN (should take 5+ minutes due to cooldown).
9. Apply the VPA in "Off" mode and run `kubectl describe vpa` after 30 minutes. Note its recommendations.

**Interview question to practice:** Explain why HPA doesn't work if resource requests are not set.

---

## SECTION 10: Monitoring & Logging
### Capstone Project: Alert That Pages You

**Scenario:** Set up end-to-end alerting that detects a crashing pod and fires an alert.

**Requirements:**
1. Install `kube-prometheus-stack` via Helm.
2. Deploy a pod that crashes every 30 seconds:
   ```yaml
   command: ["/bin/sh", "-c", "sleep 30 && exit 1"]
   ```
3. Apply `prometheus-rule.yaml` with the `PodCrashLooping` alert.
4. Wait for the alert to fire. Check in the Prometheus UI (port-forward to 9090):
   - Go to Alerts tab → verify `PodCrashLooping` is firing.
5. Add a second alert: `HighRestartCount` that fires when any pod restarts > 3 times in 5 minutes.
6. Use Grafana (port-forward to 3000) to build a dashboard panel showing restart counts per pod.
7. Add a custom annotation to the crashing deployment and verify it appears in Grafana.

---

## SECTION 11: Debugging
### Capstone Project: Intentional Breakage Lab

**Scenario:** Break things deliberately and fix them. This is the most valuable real-world practice.

**Exercise set – break and fix each:**

1. **ImagePullBackOff:** Deploy with image `nginx:doesnotexist999`. Debug and fix.
2. **CrashLoopBackOff:** Deploy with command `["false"]`. Investigate logs, fix command.
3. **OOMKilled:** Deploy with `limits.memory: 10Mi` and nginx. Watch it OOMKill. Fix the limit.
4. **Pending – no resources:** Deploy 20 replicas with `requests.cpu: 10`. Fix with lower requests.
5. **Pending – taint mismatch:** Taint all nodes. Deploy without toleration. Add toleration to fix.
6. **Service with no endpoints:** Deploy with label `app: myapp` but service selects `app: myApp` (capital A). Debug with `kubectl get endpoints`. Fix the selector.
7. **PVC stuck Pending:** Create a PVC requesting StorageClass that doesn't exist. Fix by using correct class.
8. **DNS broken:** Apply a NetworkPolicy that blocks port 53 egress. Show the pod can't resolve names. Fix it.
9. **Node NotReady:** SSH into a worker node and run `systemctl stop kubelet`. Observe in `kubectl get nodes`. Restart kubelet to fix.
10. **readiness probe too aggressive:** Set `failureThreshold: 1` and `periodSeconds: 1` on a slow app. Watch it never become Ready. Fix the thresholds.

---

## SECTION 12: Real-World Production Scenarios
### Capstone Project: Full Production Deployment

**Scenario:** Deploy a complete e-commerce stack with zero-downtime releases.

**Requirements:**
1. Deploy the 3-tier application (`full-stack-app.yaml`) in separate namespaces.
2. Apply NetworkPolicies: frontend → backend only, backend → databases only, no direct frontend → database.
3. Apply PodDisruptionBudgets to all three tiers.
4. Add HPA to the backend (min=2, max=8, CPU target=70%).
5. Use the `deploy.sh` script to perform a rolling update of the backend to a new image tag.
6. While the update is in progress (slow it down by reducing `maxSurge: 0`), run continuous curl:
   ```
   while true; do curl -s -o /dev/null -w "%{http_code}\n" http://<frontend-ip>/; sleep 0.1; done
   ```
   Verify: zero 5xx errors during the update.
7. Simulate a bad deploy (use image `nginx:doesnotexist`) and verify the script auto-rolls back.
8. Perform an etcd backup using the command from Section 12.3.

---

## SECTION 13: Scheduling, Placement & Workload Control
### Capstone Project: Multi-Tenant Cluster Simulation

**Scenario:** Simulate a multi-tenant cluster with two teams: `team-alpha` (prod) and `team-beta` (batch).

**Requirements:**
1. Label nodes:
   - `worker-node-1`: `team=alpha`
   - `worker-node-2`: `team=beta`
2. Taint `worker-node-1`: `team=alpha:NoSchedule`.
3. Taint `worker-node-2`: `team=beta:NoSchedule`.
4. Create namespace `alpha` with ResourceQuota: `limits.cpu: 4, limits.memory: 8Gi`.
5. Create namespace `beta` with ResourceQuota: `limits.cpu: 8, limits.memory: 16Gi`.
6. Deploy `team-alpha` app with:
   - Toleration for `team=alpha:NoSchedule`.
   - NodeAffinity: `required` for `team=alpha`.
   - PriorityClass: `high-priority` (value: 100000).
   - PodAntiAffinity: prefer not on same node.
7. Deploy `team-beta` batch job with:
   - Toleration for `team=beta:NoSchedule`.
   - PriorityClass: `low-priority-batch` (value: 100, preemptionPolicy: Never).
8. Apply TopologySpreadConstraints to `team-alpha` to spread evenly.
9. Simulate resource pressure: fill `worker-node-1` with batch pods. Deploy a `critical-production` priority pod. Watch it preempt the batch pods.
10. Set up PDBs for both teams. Try to drain `worker-node-1` and observe it being blocked by the PDB. Fix by scaling up first.

---

## BONUS: Interview Prep – Top 20 Questions to Be Able to Answer

1. What is the difference between a liveness probe and a readiness probe? When does each fire?
2. What is a startup probe and why was it added? What problem does it solve?
3. You apply a NetworkPolicy. Immediately all pods stop resolving DNS. Why? Fix it.
4. Explain the full sequence of events when you run `kubectl delete pod`.
5. What is the difference between `kubectl cordon` and `kubectl taint`?
6. How does HPA calculate the desired replica count? What is the formula?
7. A PVC is stuck in `Pending`. Walk me through the full debugging process.
8. What is `terminationGracePeriodSeconds` and how does it interact with `preStop`?
9. When would you use a StatefulSet vs a Deployment? Give 3 examples of each.
10. What is the difference between `ClusterRole` and `Role`? Between `RoleBinding` and `ClusterRoleBinding`?
11. A service has no endpoints. What are all the possible causes?
12. How does a canary deployment work without a service mesh? What is its limitation?
13. What is `podAntiAffinity` with `topologyKey: kubernetes.io/hostname` doing? What happens if replicas > nodes?
14. Explain the difference between `maxSkew` in TopologySpreadConstraints and podAntiAffinity.
15. How does Kubernetes decide which pod to preempt when a high-priority pod can't schedule?
16. What is a headless service? When would you use it? What DNS response does it return vs ClusterIP?
17. A node has disk pressure. What happens to pods on that node? What taint is automatically applied?
18. Explain base64 encoding of secrets. Why is it NOT encryption? What should you use in production?
19. What happens during an etcd snapshot restore? What steps are required?
20. A pod is in `OOMKilled` state. How do you find the right memory limit to set?

---

## File Structure of This ZIP

```
k8s-hands-on/
├── 00-MISSING-ADDITIONS/          ← What was missing from the guide
│   ├── probes-complete.yaml       ← All 4 probe types + startup probe
│   ├── lifecycle-hooks.yaml       ← postStart + preStop patterns
│   ├── pod-termination-lifecycle.yaml ← Graceful shutdown deep-dive
│   └── init-containers-advanced.yaml ← 3 real-world init patterns
├── 02-core-objects/
│   ├── multi-container-pod.yaml
│   └── webapp-deployment.yaml
├── 03-workload-management/
│   ├── blue-green.yaml
│   ├── canary.yaml
│   ├── mongodb-statefulset.yaml
│   ├── node-exporter-daemonset.yaml
│   └── db-backup-cronjob.yaml
├── 04-services-networking/
│   ├── all-services.yaml          ← All 5 service types
│   ├── ingress.yaml
│   ├── default-deny-all.yaml
│   ├── allow-frontend-to-backend.yaml
│   ├── allow-internet-egress.yaml
│   └── restrict-external-ips.yaml ← 3-layer IP blocking
├── 05-config-secrets/
│   ├── configmap.yaml             ← All 3 consumption patterns
│   └── secret.yaml
├── 06-storage/
│   └── storage.yaml
├── 07-rbac-security/
│   ├── rbac.yaml
│   └── secure-pod.yaml
├── 09-autoscaling/
│   ├── hpa.yaml
│   └── vpa.yaml                   ← ADDED: VPA was in TOC but not written
├── 10-monitoring/
│   └── prometheus-rule.yaml       ← 6 production alerts
├── 12-production-scenarios/
│   ├── full-stack-app.yaml
│   └── deploy.sh                  ← Zero-downtime deploy script
├── 13-scheduling/
│   ├── toleration-examples.yaml
│   ├── node-affinity.yaml
│   ├── pod-affinity-antiaffinity.yaml
│   ├── priority-classes.yaml
│   ├── pdb-examples.yaml
│   ├── resource-governance.yaml
│   └── topology-spread.yaml
└── CAPSTONE-PROJECTS.md           ← This file
```
