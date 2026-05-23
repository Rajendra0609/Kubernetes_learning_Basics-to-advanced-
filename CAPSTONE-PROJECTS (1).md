# Kubernetes & Microservices: Advanced Capstone Projects & Roadmap
> Comprehensive Edition — Practical, Production-Focused | 23 Sections · 60+ Projects

---

## How to Use This Guide

Each section follows a **Scenario → Requirements → Verification → Challenge** format.
Work through sections in order for progressive skill building, or jump to any section
independently. Every exercise is designed around real incidents and production patterns.

**Skill levels used throughout:**
- `[CORE]` — Must know; appears in almost every production environment
- `[PROD]` — Intermediate; critical for day-to-day platform engineering
- `[ADV]` — Advanced; senior/staff engineer territory

**Roadmap overview — what this guide covers:**

| # | Domain | Focus |
|---|--------|-------|
| 1–2 | Cluster Architecture | Health scripts, control plane internals |
| 2–6 | Core Objects & Storage | Pods, workloads, config, PVCs |
| 7–8 | Security & Helm | RBAC, PSS, Helm chart authoring |
| 9–10 | Scaling & Monitoring | HPA/VPA/KEDA, Prometheus, Loki |
| 11–12 | Debugging & Production | Breakage lab, full production deploy, GitOps |
| 13–16 | Scheduling & Automation | Multi-tenancy, Istio, Operators, CI/CD |
| 17 | Microservices Patterns | Saga, CQRS, Event Sourcing, Strangler Fig |
| 18 | Observability in Depth | OpenTelemetry, SLOs, Chaos Engineering |
| 19 | Performance & Scalability | eBPF, image optimisation, DB tuning |
| 20 | Supply Chain Security | Trivy, Cosign, SBOM, Admission Control |
| 21 | Advanced GitOps | Flux, Argo Rollouts, Policy-as-Code |
| 22 | Stateful Applications | Kafka/Strimzi, DB Operators, Snapshots |
| 23 | Platform Engineering | Multi-cluster, IDP, FinOps, Upgrade strategy |

---

## SECTION 1: Cluster Architecture & Health
### Project 1.1 — Cluster Health Dashboard Script `[CORE]`

**Scenario:** You just joined a company as a platform engineer. On day one, your TL asks you to
write a bash script that produces a complete, actionable health snapshot of any cluster.

**Requirements:**
1. Check all nodes are `Ready`; for any `NotReady` node, print its last 5 events automatically.
2. List all pods NOT in `Running` or `Completed` state, grouped by namespace.
3. Show CPU and memory utilization per node using `kubectl top nodes`.
4. List any pods that have restarted more than 5 times (sorted by restart count, highest first).
5. Check that `coredns` pods in `kube-system` are running and ready.
6. Check that `kube-proxy` daemonset has desired == ready on every node.
7. Output a colour-coded `PASS ✓` or `FAIL ✗` per check, with a final exit code of `1` if any check fails.

**Expected script output skeleton:**
```
[PASS] Nodes: 3/3 Ready
[FAIL] Unhealthy Pods: 2 found (see below)
  kube-system / metrics-server-xxxx  → CrashLoopBackOff (restarts: 8)
  staging     / api-worker-xxxx      → OOMKilled         (restarts: 12)
[PASS] CoreDNS: 2/2 Running
[PASS] kube-proxy: 3/3 Ready
[FAIL] High-Restart Pods:
  staging / api-worker-xxxx → 12 restarts
```

**Interview scenarios to reason through:**
- What happens when `etcd` is down? Which kubectl commands still work and which fail?
- The scheduler is stopped. Existing pods keep running — why? What happens to new ones?
- You restart only the API server. What is the brief window of impact?
- A node shows `NotReady` for 5 minutes. What happens to its pods automatically?

---

### Project 1.2 — Control Plane Component Deep Dive `[PROD]`

**Scenario:** Understand exactly what each control plane component does by temporarily disabling each one on a test cluster (use `minikube` or `kind`).

**Requirements:**
1. Stop `kube-scheduler`. Create a new deployment. Observe pods stay `Pending` indefinitely.
   Manually patch the pod's `nodeName` to schedule it yourself. Restart the scheduler.
2. Stop `kube-controller-manager`. Delete a pod from a ReplicaSet. Observe that no replacement is created.
   Restart the controller manager. Watch it reconcile.
3. Drain a node (`kubectl drain --ignore-daemonsets`). Observe DaemonSet pods stay (they always do).
   Uncordon the node.
4. Find which component owns these responsibilities:
   - Garbage-collecting completed pods
   - Watching the `Node` object for heartbeats
   - Assigning `nodeName` to unscheduled pods
   - Syncing `iptables` rules for services

**Deliverable:** A one-page runbook in comments within your script explaining which component to
check first for each class of failure.

---

## SECTION 2: Core Kubernetes Objects
### Project 2.1 — Multi-Container Pod Patterns `[CORE]`

**Scenario:** Deploy a web scraper using three multi-container patterns in one pod.

**Requirements:**
1. Create a Pod with three containers sharing an `emptyDir` volume at `/shared`:
   - `scraper`: runs `while true; do echo "{\"ts\":$(date +%s)}" >> /shared/results.json; sleep 30; done`
   - `api-sidecar`: serves `/shared/` using `python3 -m http.server 8080`
   - `log-sidecar`: tails `/shared/results.json` and prints new lines to stdout
2. Add an `initContainer` that writes `[]` to `/shared/results.json` and sets `chmod 666` on it.
3. On `api-sidecar`, configure all four probe types:
   ```yaml
   startupProbe:
     httpGet: { path: /, port: 8080 }
     failureThreshold: 30      # 30 × 10s = 5 min window for slow start
     periodSeconds: 10
   livenessProbe:
     httpGet: { path: /, port: 8080 }
     initialDelaySeconds: 0    # startup probe handles the delay
     periodSeconds: 15
     failureThreshold: 3
     timeoutSeconds: 5
   readinessProbe:
     httpGet: { path: /, port: 8080 }
     periodSeconds: 5
     successThreshold: 2       # must pass twice in a row to avoid flapping
     failureThreshold: 2
   ```
4. Set resource `requests` and `limits` on every container.
5. Use named ports in the probe definitions so port changes don't silently break probes.

**Verification:**
```bash
kubectl exec <pod> -c log-sidecar -- tail -f /shared/results.json
kubectl exec <pod> -c api-sidecar -- wget -qO- http://localhost:8080/results.json
```

**Critical questions:**
- The `scraper` container crashes. Does the whole pod restart? Which containers restart? Why?
- What is `successThreshold` on a readiness probe? What production problem does it prevent?
- Why must `startupProbe.failureThreshold × periodSeconds` cover your slowest possible start time?
- What is `terminationGracePeriodSeconds` and how does it interact with a `preStop` hook?

---

### Project 2.2 — Advanced Init Container Patterns `[PROD]`

**Scenario:** Use init containers for three real production patterns.

**Requirements (deploy each as a separate pod):**

**Pattern A — Wait for dependency:**
```yaml
initContainers:
- name: wait-for-postgres
  image: busybox
  command: ['sh', '-c', 'until nc -z postgres-svc 5432; do sleep 2; done']
```
Deploy `postgres-svc` (ClusterIP pointing at nothing initially). Watch the init container loop.
Create the backing pod. Watch the init container complete and the main container start.

**Pattern B — Database migration:**
```yaml
initContainers:
- name: run-migrations
  image: your-app:latest
  command: ["python", "manage.py", "migrate"]
  env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: url
```
Simulate this with: `command: ["sh", "-c", "echo Running migrations; sleep 5; echo Done"]`.
Verify the main container only starts after migration succeeds.

**Pattern C — Permission fixer (common in OpenShift/PSS environments):**
```yaml
initContainers:
- name: fix-perms
  image: busybox
  command: ["sh", "-c", "chown -R 1000:1000 /data"]
  volumeMounts:
  - name: data, mountPath: /data
  securityContext:
    runAsUser: 0      # init runs as root only to fix permissions
```

**Challenge:** What happens if an init container exits with code 1? With code 0 but after 10 minutes?

---

### Project 2.3 — Graceful Shutdown with Lifecycle Hooks `[PROD]`

**Scenario:** Prove that a missing `preStop` hook causes dropped requests during rolling updates.

**Requirements:**
1. Deploy nginx with 3 replicas and NO `preStop` hook.
2. Run a continuous load test: `while true; do curl -s -o /dev/null -w "%{http_code}\n" http://<svc>; sleep 0.05; done`
3. Trigger a rolling update. Count the number of non-200 responses.
4. Now add a `preStop` hook:
   ```yaml
   lifecycle:
     preStop:
       exec:
         command: ["/bin/sh", "-c", "sleep 5"]
   terminationGracePeriodSeconds: 30
   ```
5. Repeat the rolling update. Count non-200 responses again.
6. Record the difference. This is the business case for `preStop`.

**Why `sleep 5` works:** When a pod is deleted, kube-proxy takes ~1-2s to remove the pod's
endpoint from iptables. The `preStop` sleep bridges this gap so no new requests arrive after
the app starts shutting down.

---

## SECTION 3: Workload Management
### Project 3.1 — Safe Canary Release Pipeline `[CORE]`

**Scenario:** Release v2.0 of an API with zero downtime and the ability to instantly rollback.

**Step 1 — Blue-Green deployment:**
1. Deploy `webapp-blue` (nginx:1.25) with 3 replicas; label pods `slot: blue`.
2. Create `webapp-svc` selecting `slot: blue`.
3. Deploy `webapp-green` (nginx:1.26) with 3 replicas; label pods `slot: green`.
4. Verify green works: `kubectl port-forward deploy/webapp-green 8080:80`
5. Cut over: `kubectl patch svc webapp-svc -p '{"spec":{"selector":{"slot":"green"}}}'`
6. Scale blue to 0 ONLY after confirming green is healthy for 5 minutes.
7. Practice rollback: switch selector back to `blue` in under 30 seconds.

**Step 2 — Replica-based canary (no service mesh required):**
1. `webapp-stable`: 19 replicas of nginx:1.25
2. `webapp-canary`: 1 replica of nginx:1.26 — same Service selector labels as stable
3. Load test: `for i in $(seq 1 200); do curl -s http://<svc-ip>; done | grep -c "canary-header"`
4. Verify ~5% of responses came from the canary pod (check pod logs).
5. Graduate: scale stable → 0, canary → 20. Rename deployment.

**Limitation to understand:** Pod-count canary cannot split traffic more precisely than 1/N.
For precise traffic splitting (e.g. 1%) you need Istio or Nginx-Ingress weight annotations.

---

### Project 3.2 — StatefulSet: Stable Identity & Ordered Operations `[CORE]`

**Scenario:** Deploy a MongoDB replica set and understand why StatefulSet is required.

**Requirements:**
1. Create a headless Service (`clusterIP: None`) named `mongo` for DNS-based discovery.
2. Deploy a MongoDB StatefulSet with 3 replicas and a `volumeClaimTemplate` for 2Gi per pod.
3. Observe ordered startup: `mongo-0` starts first, then `mongo-1`, then `mongo-2`.
4. Exec into `mongo-0`: write a test document.
5. Delete `mongo-0`: `kubectl delete pod mongo-0`. Watch it recreate with the SAME name and SAME PVC.
6. Exec into the new `mongo-0`. Verify the document still exists.
7. Scale StatefulSet from 3 → 1. Observe ordered termination (2 first, then 1).
8. Scale back to 3. Observe ordered creation (1 first, then 2).
9. Verify DNS: `kubectl exec mongo-0 -- nslookup mongo-1.mongo` — returns the pod IP.

**Answer these to confirm understanding:**
- What is a headless service and what DNS record does it create vs a ClusterIP service?
- Why does a StatefulSet keep the same pod name on restart? What would break if it didn't?
- What is `podManagementPolicy: Parallel`? When would you use it?

---

### Project 3.3 — DaemonSet + CronJob Patterns `[PROD]`

**Scenario A — Node-level agent (DaemonSet):**
1. Deploy `node-exporter` as a DaemonSet (or simulate with busybox printing node info).
2. Verify one pod runs on every node, including the control plane (add toleration for `node-role.kubernetes.io/control-plane`).
3. Add a `nodeSelector` to restrict to only nodes with label `monitoring: enabled`.
4. Label one node `monitoring=enabled`. Observe the DaemonSet add a pod to that node.
5. Remove the label. Observe the pod is terminated.

**Scenario B — Database backup CronJob:**
1. Create a CronJob that runs every minute: `command: ["sh", "-c", "echo Backup started at $(date); sleep 10; echo Done"]`
2. Set `successfulJobsHistoryLimit: 3` and `failedJobsHistoryLimit: 1`.
3. Set `concurrencyPolicy: Forbid` — verify the second run doesn't start if the first is still running.
4. Set `startingDeadlineSeconds: 30` — what happens if the cluster is down during a scheduled window?
5. Manually trigger: `kubectl create job --from=cronjob/db-backup manual-backup-001`

---

## SECTION 4: Services & Networking
### Project 4.1 — Service Types & Internal Traffic `[CORE]`

**Scenario:** Understand when to use each service type by deploying all of them.

**Requirements:**
1. Deploy a simple nginx pod with label `app: webserver`.
2. Create a `ClusterIP` service. Verify another pod can reach it by service name (DNS).
3. Create a `NodePort` service on port 30080. Access it via `<node-ip>:30080`.
4. Create a `headless` service (`clusterIP: None`). From a pod, run `nslookup <svc-name>`.
   Observe it returns individual pod IPs, not a single virtual IP.
5. Create an `ExternalName` service pointing to `httpbin.org`.
   From a pod: `curl http://<externalname-svc>` — observe the request goes to httpbin.
6. (If cloud cluster) Create a `LoadBalancer` service and observe the `EXTERNAL-IP` provisioned.

**DNS exercise:**
- From inside a pod, resolve: `<svc-name>.<namespace>.svc.cluster.local`
- Understand the search domain chain: `.`, `.cluster.local`, `.<namespace>.svc.cluster.local`

---

### Project 4.2 — Zero-Trust Namespace with NetworkPolicies `[PROD]`

**Scenario:** Build a fully locked-down `payment` namespace where only specific traffic is allowed.

**Requirements:**
1. Create namespace `payment`. Apply a `default-deny-all` policy (ingress + egress):
   ```yaml
   spec:
     podSelector: {}
     policyTypes: [Ingress, Egress]
   ```
2. Deploy `payment-api` (nginx) and `fraud-checker` (curlimages/curl — keep it alive with `sleep infinity`).
3. Apply policies that ONLY allow:
   - `fraud-checker` → `payment-api` on port 80 (ingress to payment-api from fraud-checker)
   - `payment-api` → external HTTPS port 443 (egress)
   - DNS (UDP+TCP port 53) for all pods in the namespace
4. Verification matrix (run each test):
   ```
   fraud-checker  → payment-api:80      SHOULD SUCCEED
   attacker-pod   → payment-api:80      SHOULD FAIL (connection timeout)
   payment-api    → https://httpbin.org SHOULD SUCCEED
   payment-api    → kube-dns (internal) SHOULD FAIL (blocked egress)
   ```
5. Add an `ipBlock` egress rule to explicitly block a known-bad IP (e.g. `203.0.113.0/24`).
6. Create a third pod (`kubectl run attacker --image=curlimages/curl`) in the `payment` namespace.
   Verify it CANNOT reach `payment-api` (policy only allows `fraud-checker` by label).

**Debugging sub-task — break and fix DNS:**
1. Remove the DNS egress policy.
2. From inside `payment-api`: `nslookup google.com` — observe the exact error message.
3. Add DNS egress back. Test it restores name resolution.
4. Document: what is the error message for a DNS timeout vs a connection refused?

---

### Project 4.3 — Ingress: TLS, Routing, and Rate Limiting `[PROD]`

**Scenario:** Expose multiple services through a single Ingress controller with TLS.

**Requirements:**
1. Install `ingress-nginx` controller via Helm.
2. Create two deployments: `frontend` (nginx serving "Hello from frontend") and `backend` (serving "Hello from backend").
3. Create an Ingress that routes:
   - `app.local/` → frontend service
   - `app.local/api` → backend service (with `rewrite-target` annotation)
4. Generate a self-signed cert: `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=app.local"`
5. Create a TLS Secret: `kubectl create secret tls app-tls --cert=tls.crt --key=tls.key`
6. Add TLS to the Ingress. Verify HTTPS works and HTTP redirects to HTTPS.
7. Add annotations:
   ```yaml
   nginx.ingress.kubernetes.io/limit-rps: "10"
   nginx.ingress.kubernetes.io/limit-connections: "5"
   ```
8. Test rate limiting: `for i in $(seq 1 50); do curl -sk https://app.local/; done | sort | uniq -c`
   — observe 429 responses once limit is exceeded.

---

## SECTION 5: Configuration & Secrets
### Project 5.1 — ConfigMap Hot-Reload `[CORE]`

**Scenario:** Build a system that detects ConfigMap changes without pod restarts — a critical
pattern for feature flags and log-level toggles in production.

**Requirements:**
1. Create a ConfigMap with `app.properties`:
   ```
   LOG_LEVEL=INFO
   FEATURE_FLAG_NEW_CHECKOUT=false
   ```
2. Mount it as a volume (not env vars — env vars require pod restart to update).
3. Deploy a pod with a sidecar that prints the config every 10s:
   `watch -n10 cat /etc/config/app.properties`
4. Edit the ConfigMap: change `LOG_LEVEL=DEBUG`.
5. Observe the sidecar pick up the new value within ~60s WITHOUT restarting.
6. Verify: `kubectl exec <pod> -c sidecar -- cat /etc/config/app.properties` shows `LOG_LEVEL=DEBUG`.

**Why this works:** Volume-mounted ConfigMaps are updated via a symlink swap by kubelet.
The file content changes but the inode changes too — applications using `inotify` detect this.
Applications that cache the file at startup need a SIGHUP or similar signal.

**Critical limitation to document:** If the same ConfigMap is consumed as an env var
(`envFrom: configMapRef`), the env var does NOT update until the pod restarts.

---

### Project 5.2 — Secrets: Security Layers `[PROD]`

**Scenario:** Understand what Kubernetes Secrets actually protect and where they fall short.

**Requirements:**
1. Create a Secret with `username: admin` and `password: supersecret`.
2. Mount it as a volume with `defaultMode: 0400` (read-only by owner).
3. Exec into the pod: `ls -la /etc/secrets/` — confirm file permissions.
4. Retrieve from outside: `kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d`
5. Write a comment block explaining:
   - Why base64 is NOT encryption (it's encoding — anyone with API access can decode)
   - What `etcd` encryption at rest does and where to configure it
   - Why RBAC on Secrets (`verbs: get` on the Secret resource) matters

**Production alternatives to native Secrets:**
- **Sealed Secrets:** Encrypt locally with a public key; only the controller in-cluster can decrypt.
  `kubeseal --fetch-cert` → `kubeseal < secret.yaml > sealed-secret.yaml` → commit to Git safely.
- **External Secrets Operator:** Syncs from AWS Secrets Manager / GCP Secret Manager / Vault.
  The Secret never exists in Git; ESO creates it in-cluster at runtime.
- **HashiCorp Vault:** Pods authenticate via ServiceAccount JWT; Vault Agent injects secrets as files.

**Challenge:** Attempt to commit a plain Secret YAML to a Git repo and set up `git-secrets`
or `gitleaks` to detect and block it at pre-commit hook level.

---

### Project 5.3 — Environment Variable Injection Patterns `[CORE]`

**Scenario:** Understand all four ways to inject config into pods and when to use each.

**Requirements — deploy four pods, each using a different injection method:**
1. **Inline env:** `env: [{name: LOG_LEVEL, value: INFO}]` — simplest, not reusable.
2. **ConfigMap envFrom:** `envFrom: [{configMapRef: {name: app-config}}]` — whole ConfigMap as env.
3. **Secret valueFrom:** `valueFrom: {secretKeyRef: {name: db-creds, key: password}}` — single key.
4. **Downward API:**
   ```yaml
   env:
   - name: POD_NAME
     valueFrom: {fieldRef: {fieldPath: metadata.name}}
   - name: POD_NAMESPACE
     valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
   - name: NODE_NAME
     valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
   ```
   Useful for logging: the pod logs its own name without hardcoding.

---

## SECTION 6: Storage
### Project 6.1 — Persistent Counter: Survive Pod Restarts `[CORE]`

**Scenario:** Prove that PersistentVolumes survive pod lifecycle events.

**Requirements:**
1. Create a PVC for 1Gi using the default StorageClass.
2. Deploy a pod that increments a counter stored on the PVC every 5 seconds:
   ```bash
   while true; do
     count=$(cat /data/count 2>/dev/null || echo 0)
     echo $((count + 1)) > /data/count
     echo "Count: $((count + 1))"
     sleep 5
   done
   ```
3. Watch the counter increment. Delete the pod with `kubectl delete pod`.
4. When the replacement pod starts (Deployment ensures this), verify the counter continues from where it stopped — not reset to 0.
5. Delete the Deployment (NOT the PVC). Recreate the Deployment. Verify data persists.
6. Expand the PVC: `kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'`
7. Verify expansion: `kubectl describe pvc my-pvc | grep Capacity`.

**Answer:** Why is data still there even after the pod is deleted? What would happen with `emptyDir`?

---

### Project 6.2 — StorageClass Strategies & Volume Snapshots `[ADV]`

**Scenario:** Manage different storage tiers and implement a backup/restore workflow.

**Requirements:**
1. Inspect available StorageClasses: `kubectl get sc` — identify the default one.
2. Create two PVCs: one with `ReadWriteOnce`, one with `ReadWriteMany` (if your cluster supports it).
3. Attempt to schedule two pods on different nodes both mounting the `ReadWriteOnce` PVC.
   Observe the second pod stays `Pending`. Understand why.
4. (If VolumeSnapshot is available):
   - Install the snapshot CRDs and controller.
   - Create a `VolumeSnapshotClass`.
   - Write data to a PVC. Take a snapshot: `kubectl apply -f volumesnapshot.yaml`.
   - Restore: create a new PVC with `dataSource` pointing to the snapshot.
   - Verify the restored data is present.
5. Simulate data loss: delete the original PVC's data. Switch the pod to the restored PVC.

**StatefulSet storage deep dive:**
- Each StatefulSet replica gets its own PVC via `volumeClaimTemplates`.
- Deleting the StatefulSet does NOT delete the PVCs — intentional safety feature.
- Show this: `kubectl delete statefulset mongo`. Run `kubectl get pvc`. PVCs still exist.
- Recreate the StatefulSet. Verify pods reattach to their original PVCs (same names).

---

## SECTION 7: RBAC & Security
### Project 7.1 — Least-Privilege Developer Access `[CORE]`

**Scenario:** Give a junior developer scoped access to the `dev` namespace without touching production.

**Requirements:**
1. Create namespace `dev`. Create ServiceAccount `junior-dev-sa` in `dev`.
2. Create a `Role` that allows:
   - `get, list, watch` on: pods, deployments, services, events
   - `create, update` on: deployments only
   - No `delete`. No access to Secrets or ConfigMaps.
3. Create a `RoleBinding` attaching the role to `junior-dev-sa`.
4. Verification matrix using `kubectl auth can-i --as system:serviceaccount:dev:junior-dev-sa`:
   ```
   list pods -n dev         → yes
   delete pods -n dev       → no
   get secrets -n dev       → no
   list pods -n production  → no
   list nodes               → no (ClusterRole needed for cluster-scoped resources)
   ```
5. Deploy a pod using `junior-dev-sa`. Exec into it. Attempt:
   `curl -sk https://kubernetes.default.svc/api/v1/namespaces/dev/secrets \
     -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"`
   — expect a 403 Forbidden.

**Understanding the difference:**
- `Role` + `RoleBinding`: namespace-scoped only.
- `ClusterRole` + `RoleBinding`: ClusterRole permissions but restricted to one namespace.
- `ClusterRole` + `ClusterRoleBinding`: cluster-wide; use for admin-level access only.

---

### Project 7.2 — Pod Security Hardening `[PROD]`

**Scenario:** Harden a pod to meet Pod Security Standards (PSS) `restricted` profile.

**Requirements:**
1. Label the namespace to enforce restricted PSS:
   `kubectl label namespace secure pod-security.kubernetes.io/enforce=restricted`
2. Attempt to deploy a standard nginx pod. Observe it is rejected with a policy violation.
3. Fix the pod to be PSS-compliant:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     runAsGroup: 3000
     fsGroup: 2000
     seccompProfile:
       type: RuntimeDefault
   containers:
   - securityContext:
       allowPrivilegeEscalation: false
       readOnlyRootFilesystem: true
       capabilities:
         drop: [ALL]
   ```
4. Nginx needs to write to `/var/cache/nginx` and `/var/run`. Add `emptyDir` volumes for these paths.
5. Verify: `kubectl exec <pod> -- id` → shows non-root. `kubectl exec <pod> -- whoami` → non-root user.

**OPA Gatekeeper (Advanced):**
1. Install Gatekeeper via Helm.
2. Create a `ConstraintTemplate` that enforces all containers must have resource limits.
3. Apply the `Constraint`. Try deploying a pod without limits. Observe the admission webhook reject it.
4. This is policy-as-code: the constraint lives in Git and applies cluster-wide automatically.

---

### Project 7.3 — Audit Logging & RBAC Debugging `[ADV]`

**Scenario:** Find which service account or user is causing unauthorized API calls.

**Requirements:**
1. Enable audit logging in your cluster with a policy that captures `ResponseComplete` events
   for all Secrets access (check your cluster's audit policy location, usually `/etc/kubernetes/audit-policy.yaml`).
2. Create a pod with a ServiceAccount that has NO permissions.
3. From inside the pod, attempt to list pods via the API. Observe the 403 in audit logs.
4. Use `kubectl auth can-i --list --as system:serviceaccount:<ns>:<sa>` to enumerate what
   a specific SA can do.
5. Practice: given an audit log showing `"user":{"username":"system:serviceaccount:prod:worker-sa"}`,
   find which ClusterRoleBindings give this SA its permissions.

---

## SECTION 8: Helm
### Project 8.1 — Build, Package & Publish a Production Chart `[PROD]`

**Scenario:** Package the full application stack as a reusable Helm chart with multi-environment values.

**Requirements:**
1. `helm create myapp` and clean out the default templates.
2. Create templates for: `Deployment`, `Service`, `ConfigMap`, `HPA`, `Ingress`, `ServiceAccount`, `PodDisruptionBudget`.
3. In `values.yaml` expose:
   ```yaml
   replicaCount: 2
   image: { repository: nginx, tag: latest, pullPolicy: IfNotPresent }
   ingress: { enabled: false, host: "" }
   resources: { requests: { cpu: 100m, memory: 128Mi }, limits: { cpu: 500m, memory: 256Mi } }
   autoscaling: { enabled: false, minReplicas: 2, maxReplicas: 10, targetCPUUtilizationPercentage: 70 }
   pdb: { enabled: true, minAvailable: 1 }
   ```
4. Create `values-staging.yaml` and `values-production.yaml` with environment-specific overrides.
5. Add a `_helpers.tpl` with named templates for labels and selectors:
   ```
   {{- define "myapp.labels" }}
   app.kubernetes.io/name: {{ .Chart.Name }}
   app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
   {{- end }}
   ```
6. Add a `NOTES.txt` that prints the correct access URL based on whether Ingress is enabled.
7. Add a `sha256sum` annotation on the Deployment to force pod restarts when ConfigMap changes:
   `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`
8. Run `helm lint myapp/`. Fix all warnings.
9. `helm install myapp ./myapp -f values-staging.yaml --dry-run --debug` — review output.
10. Install for real. Upgrade with a new image tag. Rollback: `helm rollback myapp 1`.

**Bonus:** Add `bitnami/redis` as a chart dependency in `Chart.yaml`. Run `helm dependency update`.

---

## SECTION 9: Auto-Scaling
### Project 9.1 — HPA + VPA: Observe Real Scaling Behaviour `[PROD]`

**Scenario:** Prove HPA and VPA work end-to-end under real load, and understand their limitations.

**Requirements:**
1. Deploy nginx with `requests.cpu: 100m`, `limits.cpu: 500m`.
2. Install `metrics-server` if not present.
3. Apply HPA: `kubectl autoscale deployment webapp --cpu-percent=50 --min=2 --max=10`
4. Verify: `kubectl top pods` shows actual usage numbers.
5. Generate load:
   ```bash
   kubectl run load-gen --image=busybox --rm -it --restart=Never \
     -- sh -c 'while true; do wget -q -O- http://webapp-svc; done'
   ```
6. In a second terminal: `watch -n5 'kubectl get hpa; echo; kubectl get pods | grep webapp'`
7. Observe pods scale UP. Record the lag time between load spike and new pods receiving traffic.
8. Kill the load generator. Observe pods scale DOWN after the cooldown (~5 minutes by default).
   Understand why the cooldown period exists (prevents thrashing).
9. Deploy a VPA in `Off` mode alongside the HPA (use separate deployments — don't run both on same):
   `kubectl describe vpa webapp-vpa` after 30 minutes — note the recommended `requests`.

**HPA formula to memorise:**
```
desiredReplicas = ceil(currentReplicas × (currentMetricValue / desiredMetricValue))
```
Example: 4 pods at 90% CPU, target 50% → `ceil(4 × 90/50)` = `ceil(7.2)` = 8 pods.

**Critical interview answer:** Why does HPA not work if `resources.requests` is not set?
Because HPA expresses utilisation as a percentage of *requests*. Without requests, there is no
denominator — the metric cannot be calculated.

---

### Project 9.2 — KEDA: Event-Driven Scale-to-Zero `[ADV]`

**Scenario:** Scale a worker deployment to zero when a queue is empty, and up when jobs arrive.

**Requirements:**
1. Install KEDA via Helm: `helm install keda kedacore/keda -n keda --create-namespace`
2. Deploy a worker deployment with 0 initial replicas.
3. Create a `ScaledObject` targeting the deployment with a Prometheus scaler (or cron scaler for testing):
   ```yaml
   triggers:
   - type: cron
     metadata:
       timezone: UTC
       start: "*/2 * * * *"   # scale up every 2 minutes
       end:   "1-59/2 * * * *" # scale down on odd minutes
       desiredReplicas: "3"
   ```
4. Observe the deployment scale from 0 → 3 → 0 → 3 on the cron schedule.
5. (If SQS/RabbitMQ available) Replace cron scaler with a queue-based scaler.
   Send 20 messages to the queue. Observe workers scale up. Process messages. Observe scale to zero.

**Why KEDA over HPA for queues:** HPA targets CPU/memory. A queue worker at 0% CPU with
1000 messages in queue should scale up — KEDA handles this; HPA cannot.

---

## SECTION 10: Monitoring & Alerting
### Project 10.1 — End-to-End Alerting Pipeline `[PROD]`

**Scenario:** Set up complete observability: metrics → alert → notification.

**Requirements:**
1. Install `kube-prometheus-stack` via Helm. This includes Prometheus, Alertmanager, and Grafana.
2. Deploy a deliberately crashing pod:
   ```yaml
   command: ["/bin/sh", "-c", "sleep 30 && exit 1"]
   ```
3. Apply a PrometheusRule:
   ```yaml
   - alert: PodCrashLooping
     expr: rate(kube_pod_container_status_restarts_total[5m]) * 60 > 1
     for: 5m
     labels: { severity: critical }
     annotations:
       summary: "Pod {{ $labels.pod }} is crash-looping"
       runbook: "https://wiki.internal/runbooks/pod-crashloop"
   - alert: HighMemoryUsage
     expr: container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.85
     for: 10m
     labels: { severity: warning }
     annotations:
       summary: "{{ $labels.pod }} using >85% of memory limit"
   - alert: PVCNearFull
     expr: (kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) < 0.1
     for: 5m
     labels: { severity: critical }
     annotations:
       summary: "PVC {{ $labels.persistentvolumeclaim }} is >90% full"
   ```
4. Port-forward Prometheus to 9090. Go to Alerts tab. Wait for `PodCrashLooping` to fire.
5. Port-forward Grafana to 3000. Build a dashboard panel:
   - Panel 1: Pod restart rate (bar chart, last 1h)
   - Panel 2: CPU usage % of limit per pod (time series)
   - Panel 3: Memory usage % of limit per pod (time series)
6. Add an annotation: `kubectl annotate deployment crashing-app event="intentional-crash-test"`.
   View it in Grafana as a vertical line on the timeline.

---

### Project 10.2 — Log Aggregation with Loki `[PROD]`

**Scenario:** Aggregate logs from all pods into a queryable system without running Elasticsearch.

**Requirements:**
1. Install Loki + Promtail via Helm (lightweight alternative to EFK):
   ```bash
   helm install loki grafana/loki-stack -n logging --create-namespace \
     --set grafana.enabled=false,prometheus.enabled=false
   ```
2. Promtail runs as a DaemonSet — verify one pod per node.
3. In Grafana, add Loki as a data source.
4. Query pod logs by label: `{namespace="default", pod=~"webapp.*"}` — see all webapp logs.
5. Count error rate: `rate({namespace="default"} |= "ERROR" [5m])`
6. Create an alert in Grafana when error rate exceeds 10/minute.

**EFK comparison (when to use which):**
- **Loki:** Indexes only labels (not log content). Lower cost, lower resource usage. Best for label-based queries.
- **EFK:** Indexes full log content. Expensive but enables full-text search across all log content.
- **Rule of thumb:** Start with Loki; migrate to EFK only if full-text search is required.

---

## SECTION 11: Debugging — Intentional Breakage Lab
### Project 11.1 — Fix 10 Real Production Failure Modes `[CORE]`

**Scenario:** Deliberately break things and diagnose them from scratch — the most valuable production skill.

For each failure: break it, observe symptoms, diagnose with the listed commands, fix it, document the root cause.

---

**Failure 1 — ImagePullBackOff:**
Break: `image: nginx:doesnotexist999`
Diagnose:
```bash
kubectl describe pod <pod> | grep -A5 Events
kubectl get events --sort-by=.metadata.creationTimestamp
```
Fix: Correct the image tag. If it's a private registry, check if the imagePullSecret is attached.

---

**Failure 2 — CrashLoopBackOff:**
Break: `command: ["false"]`
Diagnose:
```bash
kubectl logs <pod>                    # current logs
kubectl logs <pod> --previous         # logs from last crash
kubectl describe pod <pod>            # exit code in Last State section
```
Fix: Fix the command. Note: exit code 1 = generic error; exit code 137 = OOMKilled; exit code 143 = SIGTERM.

---

**Failure 3 — OOMKilled:**
Break: `limits.memory: 5Mi` with nginx.
Diagnose:
```bash
kubectl describe pod <pod> | grep -A3 "Last State"
# Look for: Reason: OOMKilled
kubectl top pod <pod>   # compare usage vs limit
```
Fix: Increase the memory limit. To find the right value, run VPA in `Off` mode for 24h and use its recommendation.

---

**Failure 4 — Pending: Insufficient Resources:**
Break: `requests.cpu: 10` with 20 replicas.
Diagnose:
```bash
kubectl describe pod <pod> | grep "Insufficient"
kubectl describe nodes | grep -A5 "Allocated resources"
```
Fix: Reduce requests or add nodes. In production: check cluster autoscaler logs.

---

**Failure 5 — Pending: Taint Mismatch:**
Break: Taint all nodes; deploy without toleration.
Diagnose:
```bash
kubectl describe pod <pod> | grep "node(s) had"
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```
Fix: Add the matching toleration to the pod spec.

---

**Failure 6 — Service With No Endpoints:**
Break: Deployment labels `app: myapp`, service selector `app: myApp` (capital A).
Diagnose:
```bash
kubectl get endpoints <svc>         # shows <none>
kubectl get pods --show-labels      # compare labels vs selector
```
Fix: Fix the selector mismatch. This is the #1 most common Kubernetes issue.

---

**Failure 7 — PVC Stuck Pending:**
Break: PVC requesting StorageClass `fast-ssd` which does not exist.
Diagnose:
```bash
kubectl describe pvc <pvc>          # shows "no matching StorageClass"
kubectl get sc                      # list available StorageClasses
```
Fix: Use a valid StorageClass name. In production, check if the provisioner's pod is running.

---

**Failure 8 — DNS Broken by NetworkPolicy:**
Break: Apply egress policy that blocks port 53.
Diagnose:
```bash
kubectl exec <pod> -- nslookup kubernetes.default   # hangs then times out
kubectl exec <pod> -- cat /etc/resolv.conf           # shows kube-dns IP
```
Error message to recognise: `nslookup: can't resolve 'kubernetes.default': Name or service not known`
Fix: Add DNS egress rule:
```yaml
egress:
- ports:
  - port: 53, protocol: UDP
  - port: 53, protocol: TCP
```

---

**Failure 9 — Node NotReady:**
Break: `ssh <worker-node> sudo systemctl stop kubelet`
Diagnose:
```bash
kubectl get nodes                   # worker shows NotReady
kubectl describe node <worker>      # check Conditions section
# Wait 5 minutes: Kubernetes adds taint node.kubernetes.io/not-ready:NoExecute
# After default 300s, pods are evicted and rescheduled elsewhere
```
Fix: `ssh <worker-node> sudo systemctl start kubelet`

---

**Failure 10 — Readiness Probe Too Aggressive:**
Break: `failureThreshold: 1, periodSeconds: 1` on a slow-starting app.
Diagnose:
```bash
kubectl describe pod <pod>          # Events: Readiness probe failed
kubectl get pod <pod>               # READY shows 0/1 even though pod is Running
```
Consequence: Traffic is never sent to this pod by the service. From the outside, it looks like the app is down.
Fix: Increase `failureThreshold` or `periodSeconds`. Use `startupProbe` for the initial wait period.

---

### Project 11.2 — Systematic Debugging Runbook `[PROD]`

**Scenario:** Pod is not serving traffic. Diagnose root cause in under 5 minutes.

**Decision tree to follow every time:**
```
Is the pod Running?
├── NO → kubectl describe pod → check Events (image? resources? taint? affinity?)
└── YES
    Is the pod Ready? (READY column shows N/N)
    ├── NO → readiness probe failing → kubectl logs, kubectl exec to test probe manually
    └── YES
        Does the service have endpoints?
        ├── NO → selector mismatch → kubectl get endpoints, compare with pod labels
        └── YES
            Can you reach it via ClusterIP from inside the cluster?
            ├── NO → kube-proxy issue or NetworkPolicy blocking
            └── YES
                Can you reach it via Ingress?
                ├── NO → Ingress controller issue, TLS cert problem, wrong host/path
                └── IT WORKS → client-side issue (DNS, firewall)
```

**Command toolkit — memorise these:**
```bash
kubectl describe pod <pod>
kubectl logs <pod> --previous
kubectl exec -it <pod> -- /bin/sh
kubectl get events --sort-by=.metadata.creationTimestamp -n <ns>
kubectl get endpoints <svc>
kubectl top pod <pod>
kubectl auth can-i <verb> <resource> --as system:serviceaccount:<ns>:<sa>
```

---

## SECTION 12: Production Scenarios
### Project 12.1 — Full Production Deployment `[PROD]`

**Scenario:** Deploy a complete 3-tier application with all production safeguards.

**Architecture:**
```
Internet → LoadBalancer → Ingress → frontend (ns: frontend)
                                  → backend  (ns: backend)
                                            → postgres (ns: database)
```

**Requirements:**
1. Create three namespaces: `frontend`, `backend`, `database`.
2. Apply NetworkPolicies:
   - `frontend` → `backend` on port 8080 only
   - `backend` → `database` on port 5432 only
   - No direct `frontend` → `database`
   - Default-deny all other ingress and egress in each namespace
3. Deploy all three tiers with:
   - Resource `requests` and `limits` on every container
   - A readiness probe and liveness probe
   - A `preStop: sleep 5` lifecycle hook
   - `terminationGracePeriodSeconds: 30`
4. Apply PodDisruptionBudgets:
   - frontend: `minAvailable: 2`
   - backend:  `minAvailable: 2`
   - database: `minAvailable: 1`
5. Apply HPA to backend: `min=2, max=8, cpu=70%`
6. Create a `deploy.sh` script that:
   - Updates the backend image tag
   - Sets `maxSurge: 1, maxUnavailable: 0` for rolling update
   - Monitors rollout: `kubectl rollout status deployment/backend -n backend --timeout=5m`
   - On failure, auto-rolls back: `kubectl rollout undo deployment/backend -n backend`
7. Run a continuous health check during the update:
   ```bash
   while true; do curl -s -o /dev/null -w "%{http_code}\n" http://<frontend>/; sleep 0.1; done
   ```
   Verify: zero 5xx errors during the rolling update.
8. Simulate a bad deploy: `image: nginx:doesnotexist`. Verify the script auto-rolls back.

---

### Project 12.2 — Disaster Recovery: etcd Backup & Restore `[ADV]`

**Scenario:** Practice the procedure you'd follow after a catastrophic cluster failure.

**Requirements:**
1. Take an etcd snapshot (on a kubeadm cluster):
   ```bash
   ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key
   ```
2. Deploy a test deployment: `kubectl create deployment before-backup --image=nginx --replicas=3`
3. Verify the snapshot: `etcdctl snapshot status /backup/etcd-<timestamp>.db`
4. Simulate data loss: `kubectl delete deployment before-backup`
5. Restore the snapshot:
   ```bash
   etcdctl snapshot restore /backup/etcd-<timestamp>.db --data-dir=/var/lib/etcd-restored
   # Update etcd manifest to point to the restored data dir
   # Restart kubelet
   ```
6. Verify: `kubectl get deployment before-backup` — it exists again.

**Velero for application-level backup:**
1. Install Velero with an S3-compatible backend.
2. Take a backup: `velero backup create my-backup --include-namespaces backend`
3. Delete the namespace. Restore: `velero restore create --from-backup my-backup`
4. Verify all resources are restored including PVCs.

**RTO/RPO planning exercise:**
- What is your Recovery Time Objective (how long can the cluster be down)?
- What is your Recovery Point Objective (how much data loss is acceptable)?
- How often should etcd snapshots run given your RPO?

---

### Project 12.3 — GitOps with ArgoCD `[ADV]`

**Scenario:** Implement GitOps so every cluster change is tracked, auditable, and reversible via Git.

**Requirements:**
1. Install ArgoCD: `kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
2. Create an ArgoCD `Application` pointing to a Git repo with your Kubernetes manifests:
   ```yaml
   spec:
     source:
       repoURL: https://github.com/your-org/k8s-manifests
       path: production/webapp
       targetRevision: main
     destination:
       server: https://kubernetes.default.svc
       namespace: production
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```
3. Push a change to the Git repo (change a replica count).
4. Watch ArgoCD auto-sync within 3 minutes: `argocd app get webapp --watch`
5. Make a manual change to the cluster: `kubectl scale deployment webapp --replicas=10`
6. With `selfHeal: true`, watch ArgoCD revert it back to Git-declared state.
7. Roll back: `argocd app rollback webapp`

**Why this matters:** Every production change is a Git commit. Audit trail is automatic.
"Who changed the replica count at 2am?" → `git log`.

---

## SECTION 13: Scheduling, Placement & Resource Governance
### Project 13.1 — Multi-Tenant Cluster Simulation `[ADV]`

**Scenario:** Simulate a multi-tenant cluster with two teams: `team-alpha` (prod) and `team-beta` (batch).

**Requirements:**
1. Label nodes:
   - `worker-1`: `team=alpha, environment=production`
   - `worker-2`: `team=beta, environment=batch`
2. Taint `worker-1`: `team=alpha:NoSchedule`
3. Taint `worker-2`: `team=beta:NoSchedule`
4. Create namespaces with ResourceQuota:
   ```yaml
   # alpha namespace
   hard:
     limits.cpu: "4"
     limits.memory: 8Gi
     pods: "20"
   # beta namespace
   hard:
     limits.cpu: "8"
     limits.memory: 16Gi
     pods: "50"
   ```
5. Add LimitRange to both namespaces to set defaults (so pods without limits still get them):
   ```yaml
   default: { cpu: 200m, memory: 256Mi }
   defaultRequest: { cpu: 100m, memory: 128Mi }
   ```
6. Deploy `team-alpha` app with:
   - Toleration for `team=alpha:NoSchedule`
   - `nodeAffinity: requiredDuringScheduling` for `team=alpha`
   - `podAntiAffinity: preferredDuringScheduling` with `topologyKey: kubernetes.io/hostname`
   - PriorityClass `high-priority` (value: 100000)
7. Deploy `team-beta` batch job with:
   - Toleration for `team=beta:NoSchedule`
   - PriorityClass `low-priority-batch` (value: 100, `preemptionPolicy: Never`)
8. Apply `TopologySpreadConstraints` to `team-alpha` to spread evenly across zones:
   ```yaml
   topologySpreadConstraints:
   - maxSkew: 1
     topologyKey: topology.kubernetes.io/zone
     whenUnsatisfiable: DoNotSchedule
     labelSelector: { matchLabels: { team: alpha } }
   ```
9. Preemption test: Fill `worker-1` with low-priority pods. Deploy a `high-priority` pod.
   Watch it preempt the low-priority pods.
10. PDB drain test: Apply PDB `minAvailable: 2` to `team-alpha`. Attempt `kubectl drain worker-1`.
    Observe it blocks (cannot evict below minAvailable). Scale up to 3 replicas. Drain succeeds.

---

### Project 13.2 — Pod Topology & Anti-Affinity Patterns `[PROD]`

**Scenario:** Ensure a 3-replica deployment never puts two pods on the same node or zone.

**Requirements:**
1. Deploy with `podAntiAffinity: requiredDuringSchedulingIgnoredDuringExecution`:
   ```yaml
   podAntiAffinity:
     requiredDuringSchedulingIgnoredDuringExecution:
     - labelSelector:
         matchLabels: { app: webapp }
       topologyKey: kubernetes.io/hostname
   ```
2. Verify: `kubectl get pods -o wide` — all on different nodes.
3. Scale to more replicas than nodes. Observe pods stuck `Pending` because the REQUIRED rule cannot be satisfied.
4. Switch to `preferredDuringSchedulingIgnoredDuringExecution` (soft rule).
   Scale again. Pods schedule even if they share a node (tries to avoid, but doesn't block).
5. Understand the difference: `required` = hard constraint (can cause Pending); `preferred` = best effort.
6. Add `TopologySpreadConstraints` as an alternative. Compare behaviour with anti-affinity.

---

## SECTION 14: Service Mesh with Istio
### Project 14.1 — mTLS, Traffic Splitting & Circuit Breaking `[ADV]`

**Scenario:** Add Istio to get zero-trust mTLS between services, fine-grained traffic control,
and automatic circuit breaking — without changing application code.

**Requirements:**
1. Install Istio: `istioctl install --set profile=demo`
2. Label namespace for sidecar injection: `kubectl label namespace default istio-injection=enabled`
3. Deploy v1 and v2 of a service (same selector labels). Create Istio `DestinationRule` and `VirtualService`:
   ```yaml
   # 90% to v1, 10% to v2
   http:
   - route:
     - destination: { host: myapp, subset: v1 }
       weight: 90
     - destination: { host: myapp, subset: v2 }
       weight: 10
   ```
4. Verify: `while true; do curl myapp; done | sort | uniq -c` — approximately 9:1 split.
5. Enable mTLS for the namespace:
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: PeerAuthentication
   spec:
     mtls:
       mode: STRICT
   ```
   Verify: a pod without the Istio sidecar cannot reach services in this namespace.
6. Configure a circuit breaker:
   ```yaml
   trafficPolicy:
     outlierDetection:
       consecutiveGatewayErrors: 5
       interval: 10s
       baseEjectionTime: 30s
   ```
7. Break one backend pod (deploy with `command: ["false"]`).
   Observe Istio ejects it from the load balancer after 5 consecutive errors.

---

## SECTION 15: CRDs & Operators
### Project 15.1 — Build a Simple Operator `[ADV]`

**Scenario:** Understand the operator pattern by building one that manages a custom resource.

**Requirements:**
1. Define a CRD `WebApp` with fields: `image`, `replicas`, `port`.
2. Implement a simple controller (use `controller-runtime` or write a bash loop for learning):
   ```bash
   while true; do
     kubectl get webapp -o json | jq -r '.items[] | .metadata.name + " " + .spec.image' | \
     while read name image; do
       kubectl create deployment $name --image=$image --dry-run=client -o yaml | kubectl apply -f -
     done
     sleep 10
   done
   ```
3. Create a `WebApp` custom resource. Observe the controller create a Deployment.
4. Update the `WebApp`'s `replicas`. Observe the controller reconcile (scale the Deployment).
5. Delete the `WebApp`. Observe the Deployment is deleted (via ownerReference garbage collection).

**What this teaches:** Every Kubernetes component (Deployment, HPA, etc.) is itself an operator.
Operators automate day-2 operations using the same reconciliation pattern as built-in controllers.

---

## SECTION 16: CI/CD Pipeline
### Project 16.1 — Full CI/CD: Build → Scan → Deploy → Verify `[ADV]`

**Scenario:** Build a GitHub Actions pipeline that tests, builds, scans, and deploys to Kubernetes.

**Pipeline stages:**
```yaml
jobs:
  test:    Run unit tests
  build:   Docker build → push to registry with commit SHA tag
  scan:    Trivy vulnerability scan → fail on CRITICAL CVEs
  deploy:  helm upgrade --atomic --timeout 5m --set image.tag=${{ github.sha }}
  verify:  kubectl rollout status + smoke test curl
  notify:  Slack notification on success/failure
```

**Requirements:**
1. Create `.github/workflows/deploy.yaml` implementing the above stages.
2. Use GitHub Environments for `staging` and `production` with a required reviewer gate for production.
3. On failure in `deploy` or `verify`, the `--atomic` flag ensures Helm auto-rolls back.
4. Store kubeconfig as a GitHub Secret. Use a dedicated ServiceAccount with minimal RBAC (not `cluster-admin`).
5. Add a `smoke-test` job that waits for the deployment to roll out, then curls the health endpoint.

---

---

## SECTION 17: Advanced Microservices Patterns
### Project 17.1 — Saga Pattern: Distributed Transactions `[PROD]`

**Scenario:** An order service must coordinate across payment, inventory, and shipping services.
A failure in any step must roll back all previous steps automatically.

**Why this matters:** ACID transactions cannot span microservices. The Saga pattern coordinates
multi-step workflows using compensating transactions — the industry-standard solution.

**Step 1 — Understand both Saga variants:**

| Variant | How It Works | When to Use |
|---------|-------------|-------------|
| Choreography | Each service emits events; others react | Simple flows, low coupling |
| Orchestration | A central orchestrator (Temporal, Conductor) drives each step | Complex flows, easier debugging |

**Step 2 — Implement a choreography-based Saga (simulate with Kubernetes Jobs):**
1. Deploy four services as Deployments: `order-svc`, `payment-svc`, `inventory-svc`, `shipping-svc`.
2. Each service publishes events to a shared topic (simulate with a ConfigMap as a message log).
3. Define the happy path:
   ```
   order-svc: OrderPlaced  →  payment-svc: PaymentProcessed  →
   inventory-svc: ItemReserved  →  shipping-svc: ShipmentScheduled
   ```
4. Inject a failure: configure `inventory-svc` to fail on specific item IDs.
5. Implement compensating transactions:
   ```
   inventory-svc: ReservationFailed  →  payment-svc: PaymentRefunded
                                     →  order-svc: OrderCancelled
   ```
6. Run end-to-end. Verify the compensation chain fires on failure and the system reaches a consistent state.

**Step 3 — Implement an orchestration-based Saga using a simple controller:**
1. Deploy a `saga-orchestrator` service that holds the workflow state in a ConfigMap.
2. The orchestrator calls each service synchronously and tracks step completion.
3. On failure at step N, the orchestrator calls compensating endpoints for steps N-1 down to 1.
4. Verify: kill `inventory-svc` mid-flow — the orchestrator detects the failure and compensates.

**Critical design rules:**
- Every Saga step must be idempotent — the orchestrator may retry on timeout.
- Compensating transactions must also be idempotent.
- Never mix Saga steps and database transactions across service boundaries.

**Interview angle:** What is the difference between a Saga and two-phase commit (2PC)?
Why is 2PC impractical for microservices? What does "eventual consistency" mean in a Saga context?

---

### Project 17.2 — CQRS: Separate Read and Write Models `[PROD]`

**Scenario:** A product catalogue service is being overwhelmed by read queries that are slowing
down write operations. You need to separate the two models without breaking clients.

**Why this matters:** CQRS allows independent scaling, optimised query paths, and prevents reads
from blocking writes. It is the foundation for event-driven read models at scale.

**Requirements:**
1. Deploy a `product-write-svc` that accepts `POST /products` and `PUT /products/:id`.
   It writes to a PostgreSQL StatefulSet and publishes a `ProductUpdated` event.
2. Deploy a `product-read-svc` that serves `GET /products` and `GET /products/:id`.
   It reads from a Redis cache (pre-joined, denormalised view optimised for queries).
3. Build an `event-projector` service that consumes `ProductUpdated` events and updates Redis.
4. Test the flow:
   - Write a product via the write service.
   - Observe the projector update Redis within 1 second.
   - Read the product via the read service — it comes from Redis (fast).
5. Kill the `event-projector`. Write a product. Observe the read model is stale.
   Restart the projector. Observe it catches up from the event log.

**Key questions to answer:**
- What does "eventual consistency" mean here — what is the window of inconsistency?
- When should you NOT use CQRS? (answer: most simple CRUDs — it adds significant complexity)
- How do you rebuild a corrupted read model? (replay the event log from scratch)

---

### Project 17.3 — Event Sourcing: The Immutable Event Log `[ADV]`

**Scenario:** Instead of storing the current state of an order, store every state change as
an immutable event. This enables full audit trails and temporal queries.

**Why this matters:** Event sourcing is the append-only, auditable alternative to mutable state.
Combined with CQRS, it unlocks event replay, debugging of historical states, and new projections.

**Requirements:**
1. Design an event schema for an `Order` aggregate:
   ```json
   { "eventType": "OrderPlaced",    "orderId": "123", "items": [...], "ts": 1234567890 }
   { "eventType": "PaymentReceived","orderId": "123", "amount": 99.99, "ts": 1234567900 }
   { "eventType": "ItemShipped",    "orderId": "123", "trackingId": "T001", "ts": 1234567910 }
   ```
2. Store events in a Kafka topic (or simulate with a PostgreSQL append-only table).
3. Build an `order-projector` that replays all events for an order to reconstruct current state.
4. Query historical state: replay only events up to timestamp T to see the order state at time T.
5. Implement a snapshot: after 100 events, write a snapshot of current state to avoid replaying from the beginning every time.
6. Add a new read projection (e.g. "all orders by customer") by replaying the event log — no schema migration required.

**Challenge:** Simulate an event store with an incorrect event. Implement an event correction
pattern (append a `CorrectionEvent` rather than mutating the original).

---

### Project 17.4 — Strangler Fig: Migrate a Monolith `[PROD]`

**Scenario:** You have a monolithic e-commerce application. The team wants to extract the
`user-auth` module as a standalone microservice without a big-bang rewrite.

**Why this matters:** The Strangler Fig is the dominant real-world migration pattern. Every team
that has moved from monolith to microservices has used some form of this approach.

**Requirements:**
1. Deploy a monolith simulator (nginx serving all routes: `/auth/*`, `/products/*`, `/orders/*`).
2. Place an API Gateway (nginx or Envoy) in front of the monolith.
3. Deploy a new standalone `auth-svc` microservice.
4. Configure the gateway to route `/auth/*` to `auth-svc` and all other traffic to the monolith.
5. Verify: `curl /auth/login` → hits `auth-svc`. `curl /products/list` → hits monolith.
6. Run both in parallel for 1 week (simulate: 2 minutes). Gradually move 10% → 50% → 100% of `/auth` traffic to the new service.
7. Once stable at 100%, remove the monolith's `/auth` routes.

**Anti-pattern to document:** Extracting a service that still shares the monolith's database.
Why this causes tight coupling and defeats the purpose of the migration.

---

### Project 17.5 — Circuit Breaker & Bulkhead Patterns `[PROD]`

**Scenario:** The `payment-svc` is degraded and taking 30 seconds to respond.
Without a circuit breaker, every incoming request to `order-svc` hangs for 30 seconds,
exhausting thread pools and taking down the entire service.

**Requirements:**
1. Deploy `payment-svc` with an endpoint that sleeps for 30 seconds before responding.
2. Deploy `order-svc` calling `payment-svc` WITHOUT a circuit breaker.
   Run 20 concurrent requests. Observe: all 20 threads are blocked. The service becomes unresponsive.
3. Add a circuit breaker (use Resilience4j if Java, or implement manually):
   ```
   State: CLOSED  →  5 consecutive failures  →  State: OPEN (fail fast, no calls for 30s)
   State: OPEN    →  30s elapsed             →  State: HALF-OPEN (let 1 request through)
   State: HALF-OPEN → success               →  State: CLOSED
   State: HALF-OPEN → failure               →  State: OPEN (again)
   ```
4. With the circuit breaker active, repeat the 20 concurrent requests. After 5 failures, remaining requests fail fast (no waiting). Service stays responsive.
5. Implement a **Bulkhead**: limit `payment-svc` calls to a dedicated thread pool of size 5.
   Other thread pools (for other dependencies) are unaffected even if payment hangs.
6. Test: with payment hanging, verify the `/health` endpoint still responds within 200ms.

**Istio alternative:** Implement the same circuit breaker via `DestinationRule.outlierDetection`
instead of application-level code. This is the cloud-native, language-agnostic approach.

---

### Project 17.6 — Outbox Pattern: Reliable Event Publishing `[ADV]`

**Scenario:** When an order is placed, `order-svc` must write to the database AND publish an event
to Kafka. If the service crashes between the two operations, you have inconsistent state.

**Why this matters:** The dual-write problem is one of the most common sources of data inconsistency
in event-driven systems. The Outbox Pattern solves it atomically.

**Requirements:**
1. Deploy a PostgreSQL StatefulSet and a Kafka broker (or use a mock).
2. Implement the naive approach: write order to DB → publish to Kafka. Kill the service after DB write but before Kafka publish. Observe the event is lost.
3. Implement the Outbox Pattern:
   - Write the order AND the event to an `outbox` table in the SAME database transaction.
   - A separate `event-relay` service (or Debezium CDC) polls the outbox table and publishes to Kafka.
   - Mark published rows as `processed = true`.
4. Kill the `order-svc` mid-write. Verify the event is eventually published (outbox ensures it survives crashes).
5. (Advanced) Replace polling with Debezium + Kafka Connect to tail the PostgreSQL WAL — zero polling overhead, sub-second latency.
6. Implement idempotent consumers: handle the same event being published twice without side effects.

**Dual-write alternatives to understand:**
- Transactional outbox (above): strongest guarantee, slightly complex.
- Change Data Capture (CDC): elegant but requires Debezium infrastructure.
- Saga choreography: avoids dual-write by design (events drive the next step).

---

## SECTION 18: Observability in Depth
### Project 18.1 — Distributed Tracing with OpenTelemetry `[PROD]`

**Scenario:** An API call taking 3 seconds. Logs show the service received and responded, but
you cannot see which downstream call is slow. Implement distributed tracing to find it.

**Why this matters:** Logs and metrics tell you *that* something is slow. Traces tell you *where*
in the call chain the latency originates. OpenTelemetry is the vendor-neutral standard.

**Requirements:**
1. Deploy a 3-service call chain: `frontend-svc` → `backend-svc` → `data-svc`.
2. Instrument each service with the OpenTelemetry SDK (use auto-instrumentation agent if Java/Python):
   ```yaml
   # Inject OTEL Java agent as initContainer
   initContainers:
   - name: otel-agent
     image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
     command: ["cp", "/javaagent.jar", "/otel/javaagent.jar"]
   env:
   - name: JAVA_TOOL_OPTIONS
     value: "-javaagent:/otel/javaagent.jar"
   - name: OTEL_SERVICE_NAME
     value: "backend-svc"
   - name: OTEL_EXPORTER_OTLP_ENDPOINT
     value: "http://otel-collector:4317"
   ```
3. Deploy the OTEL Collector to receive spans and forward to Jaeger (or Grafana Tempo).
4. Make an API call from `frontend-svc`. Port-forward Jaeger UI (port 16686).
5. Find the trace for your request — see all 3 spans in a waterfall diagram.
6. Inject artificial latency into `data-svc` (add `time.sleep(2)`).
7. Re-run the trace. Observe the 2-second span clearly attributed to `data-svc`.

**Context propagation exercise:**
- Explain what the `traceparent` HTTP header contains and how it links spans across services.
- Add a custom span attribute: `db.query = "SELECT * FROM orders WHERE id = ?"`.
- Use tail-based sampling: only store traces that contain an error or take >500ms.

**Sampling strategies to understand:**
- Head-based: random % decision at trace start — cheap but misses rare slow traces.
- Tail-based: buffer all spans; decision made at trace completion — catches all errors and slow traces.

---

### Project 18.2 — SLOs, Error Budgets & Multi-Window Alerting `[PROD]`

**Scenario:** Your team is asked to define an SLO for the API and implement alerting that
fires before users notice degradation — not after it's already too late.

**Why this matters:** SLOs are the contract between engineering and the business. Error budgets
translate abstract uptime percentages into a concrete limit on how much risk you can take.

**Requirements:**

**Step 1 — Define SLIs and SLOs:**
```yaml
# SLI: percentage of requests with HTTP status < 500 and latency < 300ms
# SLO: 99.9% of requests meet the SLI over a 30-day rolling window
# Error budget: 0.1% × 30 days × 24h × 60min = 43.2 minutes of allowed failure per month
```

**Step 2 — Implement recording rules:**
```yaml
# 5-minute error rate
- record: job:request_errors:rate5m
  expr: rate(http_requests_total{status=~"5.."}[5m])

# 5-minute total request rate
- record: job:request_total:rate5m
  expr: rate(http_requests_total[5m])

# Availability ratio
- record: job:availability:ratio5m
  expr: 1 - (job:request_errors:rate5m / job:request_total:rate5m)
```

**Step 3 — Multi-window burn rate alerts (Google SRE methodology):**
```yaml
# Fast burn: consuming budget 14× faster than allowed (fires in ~1h window)
- alert: SLOFastBurn
  expr: |
    job:availability:ratio5m < (1 - 14 * 0.001)
    AND
    avg_over_time(job:availability:ratio5m[1h]) < (1 - 14 * 0.001)
  labels: { severity: critical }
  annotations:
    summary: "SLO fast burn — budget exhausted in < 1h at current rate"

# Slow burn: consuming budget 2× faster than allowed (fires in ~3 day window)
- alert: SLOSlowBurn
  expr: |
    job:availability:ratio5m < (1 - 2 * 0.001)
    AND
    avg_over_time(job:availability:ratio5m[6h]) < (1 - 2 * 0.001)
  labels: { severity: warning }
  annotations:
    summary: "SLO slow burn — budget will exhaust in < 3 days at current rate"
```

**Step 4 — Error budget policy exercise:**
- Calculate: how many 5xx errors per hour are acceptable given a 99.9% SLO?
- Define what happens when 50% of the error budget is consumed in one week.
- Define what happens when the budget is fully exhausted (freeze all non-critical deploys).

**Use Sloth to generate SLO rules from a simple YAML specification:**
```yaml
# sloth.yaml
service: api
slos:
- name: availability
  objective: 99.9
  sli:
    events:
      error_query: rate(http_requests_total{status=~"5.."}[{{.window}}])
      total_query: rate(http_requests_total[{{.window}}])
```
Run: `sloth generate -i sloth.yaml -o prometheus-rules.yaml`

---

### Project 18.3 — Chaos Engineering: Validate Resilience `[ADV]`

**Scenario:** Your team claims the system is resilient to pod failures and network latency.
Chaos engineering turns this claim into a verifiable fact.

**Why this matters:** The only way to know your system handles failures gracefully is to
intentionally cause failures in a controlled environment before a real incident does it for you.

**Requirements:**

**Step 1 — Define your hypothesis first (always):**
```
Hypothesis: "If we kill one random pod from the backend deployment,
P99 latency will remain below 500ms and zero 5xx errors will be returned
to users for the duration of the experiment."
```

**Step 2 — Install LitmusChaos:**
```bash
helm install chaos litmuschaos/litmus --namespace=litmus --create-namespace \
  --set portal.frontend.service.type=NodePort
```

**Step 3 — Run experiments sequentially:**

Experiment A — Pod deletion:
```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
spec:
  appinfo:
    appns: production
    applabel: "app=backend"
  experiments:
  - name: pod-delete
    spec:
      components:
        env:
        - name: TOTAL_CHAOS_DURATION
          value: "60"          # 60 seconds
        - name: CHAOS_INTERVAL
          value: "10"          # kill a pod every 10s
        - name: FORCE
          value: "false"       # graceful kill (SIGTERM)
```

Experiment B — Network latency injection:
```yaml
- name: pod-network-latency
  spec:
    components:
      env:
      - name: NETWORK_LATENCY
        value: "2000"          # 2000ms latency
      - name: TARGET_PODS
        value: "payment-svc"
      - name: TOTAL_CHAOS_DURATION
        value: "120"
```

Experiment C — CPU stress (simulate noisy-neighbour):
```yaml
- name: pod-cpu-hog
  spec:
    components:
      env:
      - name: CPU_CORES
        value: "2"
      - name: TOTAL_CHAOS_DURATION
        value: "60"
```

**Step 4 — Monitor during experiments:**
```bash
# Terminal 1: continuous load
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://<svc>; sleep 0.1; done

# Terminal 2: watch HPA
watch -n2 kubectl get hpa,pods -n production

# Terminal 3: watch Prometheus alerts
# Port-forward to 9090 and open Alerts tab
```

**Step 5 — Document results vs hypothesis:**
```
Hypothesis: P99 < 500ms, zero 5xx
Actual result:
  Pod deletion: P99 = 420ms ✓, 0 5xx ✓  — hypothesis confirmed
  Network latency: P99 = 2800ms ✗         — hypothesis FAILED
  Action: implement circuit breaker for payment-svc (Section 17.5)
```

**Integrate chaos into CI (advanced):**
Run lightweight chaos experiments (10s pod kill) in the staging pipeline.
If error rate spikes, fail the CI run — resilience is now a deploy gate.

---

### Project 18.4 — Continuous Profiling with Pyroscope `[ADV]`

**Scenario:** CPU usage is high but logs and metrics show no obvious cause.
Continuous profiling reveals the exact function consuming CPU — without stopping the service.

**Requirements:**
1. Deploy Pyroscope:
   ```bash
   helm install pyroscope grafana/pyroscope -n monitoring
   ```
2. Instrument a Go or Python application with the Pyroscope SDK:
   ```python
   import pyroscope
   pyroscope.configure(
       app_name="backend-svc",
       server_address="http://pyroscope:4040",
       tags={"namespace": os.getenv("POD_NAMESPACE"), "pod": os.getenv("POD_NAME")}
   )
   ```
3. Generate load: run the load test from Section 9.1.
4. Open the Pyroscope UI. Select your service. View the flame graph.
5. Read the flame graph: the width of each bar is proportional to CPU time spent in that function.
   The root cause of CPU usage is always the widest bar near the bottom of the call stack.
6. Add Pyroscope as a Grafana data source. Correlate: CPU metric spike → jump to flame graph for that time window.

**eBPF-based zero-instrumentation profiling:**
```bash
helm install parca parca-dev/parca -n monitoring
```
Parca profiles ALL processes on the node via eBPF — no SDK required, no language restrictions.
View call stacks for any container in the cluster without redeployment.

---

## SECTION 19: Performance & Scalability
### Project 19.1 — Container Image Optimisation `[CORE]`

**Scenario:** Your CI builds a 1.4GB Docker image. Pull time is 45 seconds cold.
Startup time is 20 seconds. The security scan returns 47 CVEs. Fix all three problems.

**Why this matters:** Image size directly affects pull time, startup time, and attack surface.
At scale (100 pod restarts per day), a 30-second improvement per pull saves 50 minutes/day.

**Requirements:**
1. Start with this bloated Dockerfile:
   ```dockerfile
   FROM python:3.11                          # 1.0 GB
   RUN apt-get update && apt-get install -y \
       git curl wget vim build-essential    # adds 500MB
   COPY requirements.txt .
   RUN pip install -r requirements.txt
   COPY . .
   CMD ["python", "app.py"]
   ```
2. Measure baseline: `docker build -t app:v1 .` → `docker images app:v1` → note size.
3. Optimise with multi-stage build:
   ```dockerfile
   # Stage 1: build
   FROM python:3.11-slim AS builder
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

   # Stage 2: runtime (distroless — no shell, no package manager)
   FROM gcr.io/distroless/python3-debian12
   COPY --from=builder /install /usr/local
   COPY --from=builder /app /app
   WORKDIR /app
   USER nonroot:nonroot
   CMD ["app.py"]
   ```
4. Measure again: note size reduction (target < 100MB).
5. Fix layer ordering for cache efficiency:
   ```dockerfile
   # WRONG: COPY . before pip install — every code change invalidates the pip cache
   COPY . .
   RUN pip install -r requirements.txt

   # RIGHT: copy only requirements first
   COPY requirements.txt .
   RUN pip install -r requirements.txt   # cached unless requirements.txt changes
   COPY . .                              # only invalidates subsequent layers
   ```
6. Run Trivy scan: `trivy image app:v1` vs `trivy image app:v2-distroless` — compare CVE counts.
7. Add a HEALTHCHECK instruction and verify it shows in `docker inspect`.

**Benchmark in Kubernetes:**
- Deploy both image versions. Compare time from pod creation to `Running` and `Ready`.
- Use `kubectl get pod -o jsonpath='{.status.conditions}'` to measure exact timestamps.

---

### Project 19.2 — eBPF Networking with Cilium `[ADV]`

**Scenario:** Your cluster has 8,000 services. `kubectl get svc` takes 2 seconds.
kube-proxy has generated 300,000 iptables rules. CPU usage on nodes is elevated from iptables processing.
Switch to Cilium to eliminate this bottleneck.

**Why this matters:** iptables is O(n) — lookup time grows linearly with rule count. eBPF is O(1).
At >5,000 services, the difference in latency and CPU is measurable.

**Requirements:**
1. Install Cilium replacing kube-proxy:
   ```bash
   helm install cilium cilium/cilium \
     --set kubeProxyReplacement=strict \
     --set k8sServiceHost=<API_SERVER_IP> \
     --set k8sServicePort=6443
   ```
2. Verify kube-proxy is fully replaced: `cilium status` shows `KubeProxy: Disabled`.
3. Verify iptables rules are drastically reduced: `iptables -L | wc -l` — compare before/after.
4. Enable Cilium's L7 network policies (HTTP-aware, not just port-based):
   ```yaml
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   spec:
     endpointSelector:
       matchLabels:
         app: payment-api
     ingress:
     - fromEndpoints:
       - matchLabels:
           app: fraud-checker
       toPorts:
       - ports:
         - port: "80"
           protocol: TCP
         rules:
           http:
           - method: POST
             path: /api/v1/charge    # only this exact path is allowed
   ```
5. Test: `curl payment-api/api/v1/charge` from `fraud-checker` → succeeds.
   `curl payment-api/api/v1/refund` → blocked (L7 policy rejects this path).
6. Enable Hubble for eBPF-based network observability:
   ```bash
   cilium hubble enable
   hubble observe --namespace payment --follow
   ```
   Watch real-time packet flow — see allowed and dropped connections live.

---

### Project 19.3 — Database Performance on Kubernetes `[ADV]`

**Scenario:** PostgreSQL running in Kubernetes is showing high connection counts (>500) and
occasional query timeouts under load. Connection exhaustion is a common Kubernetes DB issue.

**Requirements:**

**Step 1 — Reproduce the problem:**
1. Deploy PostgreSQL StatefulSet with `max_connections = 100`.
2. Deploy 10 replicas of `backend-svc`, each maintaining a connection pool of 20 connections.
3. Observe: `10 replicas × 20 connections = 200 connections`, exceeding the limit.
   New connections fail: `FATAL: remaining connection slots are reserved for non-replication`.

**Step 2 — Add PgBouncer as a connection pooler:**
```yaml
# PgBouncer sidecar alongside PostgreSQL
containers:
- name: pgbouncer
  image: bitnami/pgbouncer:latest
  env:
  - name: POSTGRESQL_HOST
    value: "localhost"
  - name: PGBOUNCER_POOL_MODE
    value: "transaction"        # connection shared per transaction, not per session
  - name: PGBOUNCER_MAX_CLIENT_CONN
    value: "500"                # PgBouncer accepts up to 500 clients
  - name: PGBOUNCER_DEFAULT_POOL_SIZE
    value: "20"                 # maintains only 20 real DB connections
```

3. Redirect `backend-svc` to connect to PgBouncer (port 5432 → PgBouncer → PostgreSQL).
4. Scale `backend-svc` to 50 replicas. Verify PostgreSQL connection count stays at ~20.

**Step 3 — Storage class selection for latency-sensitive DBs:**
```yaml
# High-performance StorageClass using local NVMe (if available)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-nvme
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer   # bind only when pod is scheduled
reclaimPolicy: Retain
```
Run: `fio --name=randwrite --ioengine=libaio --direct=1 --rw=randwrite --bs=4k --size=1G`
inside the DB pod to benchmark IOPS. Compare `gp2` vs `gp3` vs local NVMe.

**Step 4 — Online schema migrations (zero downtime):**
Never run `ALTER TABLE ADD COLUMN` on a table with millions of rows — it locks the table.
Use `gh-ost` (GitHub) or `pt-online-schema-change` (Percona) to migrate without locking:
```bash
gh-ost --host=postgres-svc --database=orders --table=order_items \
       --alter="ADD COLUMN discount_pct DECIMAL(5,2) DEFAULT 0" \
       --execute
```

---

### Project 19.4 — Load Balancing Strategies & Service Mesh `[ADV]`

**Scenario:** One pod in your backend deployment is receiving 60% of requests while others sit idle.
The issue is kube-proxy's random round-robin ignoring pod load. Fix it with Istio.

**Requirements:**
1. Deploy 5 replicas of `backend-svc` with wildly different response times:
   - Pod 0: 10ms (fast)
   - Pod 1: 500ms (slow — simulate with sleep)
   - Pods 2–4: 50ms (normal)
2. Run load test. Observe: with round-robin, ~20% of requests go to the 500ms pod.
   Tail latency (P99) is dominated by the slow pod.
3. Switch to `LEAST_CONN` load balancing via Istio `DestinationRule`:
   ```yaml
   spec:
     host: backend-svc
     trafficPolicy:
       loadBalancer:
         simple: LEAST_CONN
   ```
4. Re-run load test. Observe: the 500ms pod receives far fewer requests (it's always "busy").
   P99 latency improves significantly.
5. Test locality-aware routing: label pods by zone.
   ```yaml
   trafficPolicy:
     loadBalancer:
       localityLbSetting:
         enabled: true
         failover:
         - from: us-east-1a
           to: us-east-1b
   ```
   Verify: pods in the same zone as the caller are preferred.
   Document: this reduces cross-AZ data transfer costs (typically $0.01/GB between AZs on AWS).

---

## SECTION 20: Supply Chain Security
### Project 20.1 — Container Image Scanning in CI/CD `[PROD]`

**Scenario:** A container image in production contains a critical CVE that was present in
the base image. Implement scanning as a mandatory CI gate to prevent this.

**Why this matters:** Most production vulnerabilities enter via base images and dependencies,
not application code. Scanning at build time catches these before they reach production.

**Requirements:**
1. Install Trivy: `brew install aquasecurity/trivy/trivy` or via the CI GitHub Action.
2. Scan an existing image:
   ```bash
   trivy image nginx:1.25                                 # image vulnerabilities
   trivy fs .                                              # filesystem (source code + deps)
   trivy k8s --report=summary cluster                     # entire cluster scan
   ```
3. Add Trivy to GitHub Actions as a required check:
   ```yaml
   - name: Scan image for vulnerabilities
     uses: aquasecurity/trivy-action@master
     with:
       image-ref: myapp:${{ github.sha }}
       format: sarif
       exit-code: 1                    # fail the build on CRITICAL findings
       severity: CRITICAL,HIGH
       ignore-unfixed: true            # don't fail on CVEs without a fix yet
   ```
4. Create a `.trivyignore` file for accepted false positives (document the business reason).
5. Scan a Helm chart for misconfigurations:
   ```bash
   trivy config ./helm/myapp/
   ```
   Fix any findings (e.g. missing resource limits, running as root).

---

### Project 20.2 — Image Signing & Provenance with Cosign `[ADV]`

**Scenario:** An attacker replaces an image in your registry. Without image signing,
your cluster has no way to verify the image came from your trusted CI pipeline.

**Why this matters:** Supply chain attacks (like SolarWinds) inject malicious code via the
build pipeline. Image signing proves an image's provenance and detects tampering.

**Requirements:**
1. Generate a signing key pair: `cosign generate-key-pair`
   Store `cosign.key` in a GitHub Secret, `cosign.pub` in the cluster as a ConfigMap.
2. Sign the image after building in CI:
   ```bash
   cosign sign --key cosign.key myregistry/myapp:${{ github.sha }}
   ```
3. Verify a signature:
   ```bash
   cosign verify --key cosign.pub myregistry/myapp:abc123
   ```
4. Use keyless signing with Sigstore (no key management — uses OIDC identity):
   ```bash
   cosign sign --identity-token=$(cat $ACTIONS_ID_TOKEN_REQUEST_TOKEN) myregistry/myapp:latest
   ```
5. Add admission webhook enforcement:
   Deploy Cosign's policy controller or use Kyverno:
   ```yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   spec:
     rules:
     - name: verify-image-signature
       match:
         resources: { kinds: [Pod] }
       verifyImages:
       - imageReferences: ["myregistry/*"]
         attestors:
         - entries:
           - keys:
               publicKeys: |-
                 -----BEGIN PUBLIC KEY-----
                 <cosign.pub contents>
                 -----END PUBLIC KEY-----
   ```
6. Try deploying an unsigned image. Observe the admission webhook block it.

---

### Project 20.3 — SBOM: Know Every Package in Your Image `[ADV]`

**Scenario:** The Log4Shell vulnerability was hidden inside a transitive dependency inside
a JAR inside a container. You need a complete Software Bill of Materials to find it instantly.

**Requirements:**
1. Generate an SBOM for an image:
   ```bash
   # SBOM in SPDX format
   trivy image --format spdx-json --output sbom.json myapp:latest

   # SBOM in CycloneDX format
   syft myapp:latest -o cyclonedx-json > sbom.json
   ```
2. Attach the SBOM as an attestation to the image:
   ```bash
   cosign attest --predicate sbom.json --type spdxjson myapp:latest
   ```
3. Verify the attestation:
   ```bash
   cosign verify-attestation --type spdxjson myapp:latest | jq .payload | base64 -d | jq .
   ```
4. Use `grype` to scan the SBOM for vulnerabilities (faster than pulling the full image):
   ```bash
   grype sbom:./sbom.json
   ```
5. Automate: in CI, generate SBOM + sign + attest as a post-build step.
   In admission control, reject images without a verified SBOM attestation.

---

## SECTION 21: Advanced GitOps & Progressive Delivery
### Project 21.1 — GitOps with Flux CD `[PROD]`

**Scenario:** Implement GitOps with Flux as an alternative to Argo CD, leveraging its
native Kustomize support and stronger multi-tenant model.

**Requirements:**
1. Install Flux:
   ```bash
   flux bootstrap github \
     --owner=your-org \
     --repository=k8s-manifests \
     --branch=main \
     --path=clusters/production
   ```
2. Create a `GitRepository` source pointing to your app manifests repo.
3. Create a `Kustomization` that applies overlays per environment:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   spec:
     interval: 5m
     path: ./overlays/production
     prune: true                    # delete resources removed from Git
     wait: true                     # wait for health checks to pass
     healthChecks:
     - apiVersion: apps/v1
       kind: Deployment
       name: backend
       namespace: production
   ```
4. Create a `HelmRelease` for a third-party dependency:
   ```yaml
   apiVersion: helm.toolkit.fluxcd.io/v2beta1
   kind: HelmRelease
   spec:
     interval: 1h
     chart:
       spec:
         chart: cert-manager
         version: ">=1.13.0 <2.0.0"
         sourceRef: { kind: HelmRepository, name: jetstack }
     values:
       installCRDs: true
   ```
5. Push a change to Git. Observe Flux sync within 5 minutes.
6. Delete a resource directly in the cluster. With `prune: true`, observe Flux recreate it.
7. Configure image automation: Flux scans the container registry and auto-commits new image tags.
   ```yaml
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImageUpdateAutomation
   spec:
     interval: 5m
     sourceRef: { kind: GitRepository, name: app-manifests }
     git:
       commit:
         author: { name: "flux[bot]", email: "flux@your-org.com" }
         messageTemplate: "chore: update {{.AutomationObject.Name}} image to {{.NewValue}}"
   ```

**Flux vs Argo CD — when to choose each:**

| Aspect | Flux | Argo CD |
|--------|------|---------|
| Multi-tenancy | Strong (per-team namespaces, impersonation) | Possible but more manual |
| UI | No built-in UI | Rich UI, great for teams new to GitOps |
| Helm support | HelmRelease CRD | First-class, easier |
| Kustomize | First-class | Supported but secondary |
| Image automation | Built-in | Requires Image Updater plugin |

---

### Project 21.2 — Progressive Delivery with Argo Rollouts `[ADV]`

**Scenario:** Replace Kubernetes' all-or-nothing rolling update with an automated canary
that promotes only when SLO metrics confirm the new version is healthy.

**Why this matters:** Standard rolling updates move traffic without verifying the new version
is actually working. Argo Rollouts adds automated metric-driven promotion and rollback.

**Requirements:**
1. Install Argo Rollouts:
   ```bash
   kubectl create namespace argo-rollouts
   kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
   ```
2. Convert a Deployment to a Rollout:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Rollout
   spec:
     replicas: 10
     strategy:
       canary:
         steps:
         - setWeight: 10           # 10% traffic to canary
         - pause: { duration: 5m } # wait 5 minutes
         - analysis:               # check metrics
             templates:
             - templateName: success-rate
         - setWeight: 50
         - pause: { duration: 5m }
         - setWeight: 100
   ```
3. Create an `AnalysisTemplate` that queries Prometheus:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: AnalysisTemplate
   spec:
     metrics:
     - name: success-rate
       interval: 1m
       successCondition: result[0] >= 0.99   # 99% success rate required
       failureLimit: 3
       provider:
         prometheus:
           address: http://prometheus:9090
           query: |
             sum(rate(http_requests_total{status!~"5..",rollout_id="{{args.rollout-id}}"}[5m]))
             /
             sum(rate(http_requests_total{rollout_id="{{args.rollout-id}}"}[5m]))
   ```
4. Trigger an update: `kubectl argo rollouts set image backend backend=myapp:v2`
5. Watch the rollout: `kubectl argo rollouts get rollout backend --watch`
6. Inject errors into v2 (return 500 for 5% of requests). Observe the AnalysisRun fail.
   Watch Argo Rollouts automatically abort and roll back — zero human intervention.
7. Test traffic mirroring (shadow traffic):
   ```yaml
   steps:
   - experiment:
       templates:
       - name: canary-mirror
         specRef: canary
         weight: 0      # 0% live traffic
       analyses:
       - name: smoke-test
         templateName: smoke-test
   ```

---

### Project 21.3 — Policy as Code: Shift Left `[ADV]`

**Scenario:** Policy violations are caught at admission time — but the developer already spent
hours on the change. Shift policy enforcement left into the CI pipeline.

**Why this matters:** Admission webhooks are a safety net, not a first line of defence.
Detecting misconfigurations in PRs (before they reach the cluster) saves developer time.

**Requirements:**
1. Install Conftest: `brew install conftest`
2. Write an OPA/Rego policy:
   ```rego
   # policy/kubernetes.rego
   package kubernetes.admission

   deny[msg] {
     input.kind == "Deployment"
     container := input.spec.template.spec.containers[_]
     not container.resources.limits.cpu
     msg := sprintf("Container '%v' must have CPU limits set", [container.name])
   }

   deny[msg] {
     input.kind == "Deployment"
     container := input.spec.template.spec.containers[_]
     container.securityContext.runAsRoot == true
     msg := sprintf("Container '%v' must not run as root", [container.name])
   }

   deny[msg] {
     input.kind == "Deployment"
     not input.spec.template.spec.containers[_].readinessProbe
     msg := "Deployment must have a readiness probe"
   }
   ```
3. Test locally: `conftest test deployment.yaml --policy policy/`
4. Add to GitHub Actions as a PR check:
   ```yaml
   - name: Policy check (Conftest)
     run: |
       helm template ./helm/myapp | conftest test - --policy policy/
       exit $?
   ```
5. Test the Kyverno CLI alternative:
   ```bash
   kyverno apply policy/ --resource deployment.yaml
   ```
6. Create a cost-estimation check using Kubecost's Helm chart annotation scanner:
   Any PR that increases `resources.requests.cpu` by >200m adds a comment to the PR
   with the estimated monthly cost increase.

---

## SECTION 22: Stateful Applications at Scale
### Project 22.1 — Kafka on Kubernetes with Strimzi `[ADV]`

**Scenario:** Deploy a production-grade Kafka cluster managed by the Strimzi operator.
Use it as the event backbone for the microservices from Section 17.

**Why this matters:** Kafka is the dominant event streaming platform. Running it on Kubernetes
via Strimzi is now production-ready and used widely. Understanding it is essential for
event-driven systems at scale.

**Requirements:**
1. Install Strimzi:
   ```bash
   helm install strimzi-operator strimzi/strimzi-kafka-operator -n kafka --create-namespace
   ```
2. Create a Kafka cluster as a CRD:
   ```yaml
   apiVersion: kafka.strimzi.io/v1beta2
   kind: Kafka
   metadata:
     name: production-kafka
   spec:
     kafka:
       replicas: 3
       config:
         default.replication.factor: 3
         min.insync.replicas: 2
         offsets.topic.replication.factor: 3
       storage:
         type: persistent-claim
         size: 10Gi
         class: standard
       resources:
         requests: { cpu: 500m, memory: 2Gi }
         limits:   { cpu: 2000m, memory: 4Gi }
     zookeeper:
       replicas: 3
       storage:
         type: persistent-claim
         size: 5Gi
     entityOperator:
       topicOperator: {}
       userOperator: {}
   ```
3. Create a topic via Strimzi CRD (not `kafka-topics.sh`):
   ```yaml
   apiVersion: kafka.strimzi.io/v1beta2
   kind: KafkaTopic
   spec:
     partitions: 12              # partitions = max parallelism for consumers
     replicas: 3                 # one copy per broker
     config:
       retention.ms: "604800000" # 7 days retention
       segment.bytes: "134217728" # 128MB segment files
   ```
4. Produce and consume messages:
   ```bash
   # Produce
   kubectl exec -n kafka production-kafka-kafka-0 -- bin/kafka-console-producer.sh \
     --broker-list localhost:9092 --topic orders

   # Consume
   kubectl exec -n kafka production-kafka-kafka-0 -- bin/kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 --topic orders --from-beginning
   ```
5. Monitor consumer group lag with Prometheus + kminion:
   ```bash
   helm install kminion cloudhut/kminion -n kafka \
     --set kafka.brokers="production-kafka-kafka-bootstrap:9092"
   ```
   Create alert: `kafka_consumergroup_group_lag > 10000`

**Partition design rules to learn:**
- Partitions = maximum consumer parallelism. 12 partitions → max 12 consumers in one group.
- Cannot reduce partitions after creation (only increase).
- Replication factor 3 + min.insync.replicas 2 = can tolerate 1 broker failure with no data loss.

**Consumer group lag exercise:**
- Stop one consumer. Watch lag accumulate in the Grafana dashboard.
- Restart the consumer group with more consumers. Watch it catch up.
- Calculate: if lag = 100,000 messages and consumer rate = 10,000 msg/s, catchup time = 10s.

---

### Project 22.2 — Database Operators: Day-2 Automation `[ADV]`

**Scenario:** Deploy a PostgreSQL high-availability cluster with automated failover,
point-in-time recovery, and connection pooling — all managed as Kubernetes resources.

**Requirements:**
1. Install CloudNativePG operator:
   ```bash
   helm install cnpg cloudnativepg/cloudnativepg -n cnpg-system --create-namespace
   ```
2. Create a PostgreSQL HA cluster:
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: postgres-cluster
   spec:
     instances: 3
     primaryUpdateStrategy: unsupervised     # automatic failover
     storage:
       size: 10Gi
       storageClass: standard
     backup:
       barmanObjectStore:
         destinationPath: s3://my-bucket/cnpg-backups
         s3Credentials:
           accessKeyId:
             name: s3-creds
             key: ACCESS_KEY_ID
           secretAccessKey:
             name: s3-creds
             key: SECRET_ACCESS_KEY
       retentionPolicy: "30d"
   ```
3. Verify cluster: primary on `postgres-cluster-1`, replicas on `postgres-cluster-2` and `-3`.
4. Simulate primary failure: `kubectl delete pod postgres-cluster-1`
   Watch CNPG promote `postgres-cluster-2` to primary within 30 seconds — no manual intervention.
5. Verify the RW service now points to the new primary:
   `kubectl get svc postgres-cluster-rw -o jsonpath='{.spec.selector}'`
6. Perform Point-In-Time Recovery (PITR):
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: postgres-cluster-pitr
   spec:
     bootstrap:
       recovery:
         source: postgres-cluster
         recoveryTarget:
           targetTime: "2025-06-01 14:30:00"   # restore to this exact moment
   ```
7. Add connection pooling via PgBouncer CRD:
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Pooler
   spec:
     cluster: { name: postgres-cluster }
     instances: 3
     type: rw
     pgbouncer:
       poolMode: transaction
       parameters:
         max_client_conn: "500"
         default_pool_size: "25"
   ```

---

## SECTION 23: Platform Engineering & Multi-Cluster
### Project 23.1 — Cluster Autoscaler & Karpenter `[PROD]`

**Scenario:** Your cluster runs out of capacity at 9am every weekday.
Pod stays `Pending` for 8 minutes before a new node is provisioned.
Switch to Karpenter to reduce provisioning time to under 60 seconds.

**Why this matters:** The Cluster Autoscaler (CAS) provisions nodes via cloud Auto Scaling Groups
with a 3–5 minute bootstrap time. Karpenter provisions directly via the cloud API, cutting
cold-start to 45–90 seconds and enabling cost-optimal instance selection.

**Requirements:**

**Step 1 — Understand CAS behaviour:**
1. Scale a deployment to 50 replicas (force pods into `Pending`).
2. Watch CAS trigger: `kubectl logs -n kube-system -l app=cluster-autoscaler -f`
3. Measure time from `Pending` to pods `Running` — expect 3–8 minutes.

**Step 2 — Install and configure Karpenter (AWS EKS):**
```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --set settings.aws.clusterName=my-cluster \
  --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile
```

**Step 3 — Create a NodePool:**
```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]     # prefer Spot; fall back to On-Demand
      - key: node.kubernetes.io/instance-type
        operator: In
        values:                           # diversified for Spot availability
          ["m5.xlarge","m5a.xlarge","m4.xlarge","m5d.xlarge","m5n.xlarge"]
  limits:
    cpu: "200"                            # max 200 vCPUs in this pool
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s                 # remove underutilised nodes aggressively
```

**Step 4 — Test Karpenter:**
1. Delete all existing nodes (let Karpenter provision fresh ones).
2. Scale deployment to 50 replicas again.
3. Measure time from `Pending` to `Running` — target under 90 seconds.
4. Scale back to 5 replicas. Watch Karpenter consolidate (bin pack remaining pods onto fewer nodes and terminate empty nodes).

**Step 5 — Cost optimisation verification:**
- Check which instance types Karpenter chose: `kubectl get nodes -L node.kubernetes.io/instance-type`
- Spot instances are typically 70–90% cheaper than On-Demand for the same spec.
- Run `kubectl annotate node <node> karpenter.sh/do-not-evict=true` to protect specific nodes.

---

### Project 23.2 — Multi-Cluster Management `[ADV]`

**Scenario:** Your organisation runs 8 clusters: production-us-east, production-eu-west,
staging, and 5 team-specific clusters. Managing them manually is unsustainable.

**Requirements:**

**Step 1 — Multi-cluster deployment with Argo CD ApplicationSets:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production   # targets all clusters labelled environment=production
  template:
    spec:
      project: default
      source:
        repoURL: https://github.com/org/k8s-manifests
        path: "overlays/{{name}}"   # per-cluster overlay using cluster name
      destination:
        server: "{{server}}"
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

**Step 2 — Cluster provisioning with Cluster API:**
```bash
# Install CAPI and the AWS provider
clusterctl init --infrastructure aws

# Create a new cluster declaratively
cat > cluster.yaml <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
spec:
  controlPlaneRef:
    kind: AWSManagedControlPlane
  infrastructureRef:
    kind: AWSManagedCluster
EOF
kubectl apply -f cluster.yaml
```

**Step 3 — Federated RBAC:**
- Create a `ClusterAdminGroup` in your identity provider (Okta, Google Workspace).
- Configure OIDC on all clusters to trust the same IdP.
- Members of `ClusterAdminGroup` get admin access to all clusters without per-cluster config.

**Step 4 — Cross-cluster service discovery with Submariner:**
```bash
subctl deploy-broker --kubeconfig prod-us.kubeconfig
subctl join --kubeconfig prod-eu.kubeconfig broker-info.subm --clusterid prod-eu
```
After setup: a pod in `prod-us` can reach `payment-svc.payment.svc.clusterset.local` which
resolves to the `payment-svc` in `prod-eu` — transparent cross-cluster communication.

---

### Project 23.3 — Internal Developer Platform with Backstage `[ADV]`

**Scenario:** Developers spend 3 days setting up a new microservice: provisioning infra,
writing boilerplate, configuring CI/CD, registering in monitoring. Build a self-service
platform that reduces this to 15 minutes.

**Why this matters:** Platform engineering is about reducing cognitive load on application teams.
An IDP is the product that delivers this — and Backstage is the industry-standard foundation.

**Requirements:**
1. Deploy Backstage:
   ```bash
   npx @backstage/create-app --path backstage
   cd backstage && yarn dev
   ```
2. Add your Kubernetes clusters to the Backstage catalog:
   ```yaml
   # app-config.yaml
   kubernetes:
     serviceLocatorMethod: { type: multiTenant }
     clusterLocatorMethods:
     - type: config
       clusters:
       - url: https://prod-api.k8s.example.com
         name: production
         authProvider: serviceAccount
   ```
3. Create a service template that scaffolds a new microservice in 1 click:
   ```yaml
   apiVersion: scaffolder.backstage.io/v1beta3
   kind: Template
   spec:
     steps:
     - id: create-github-repo
       action: github:repo:create
       input:
         repoUrl: github.com?owner=your-org&repo=${{ parameters.serviceName }}
     - id: create-helm-chart
       action: fetch:template
       input:
         url: ./skeleton/helm-chart
         values:
           serviceName: ${{ parameters.serviceName }}
           owner: ${{ parameters.owner }}
     - id: register-in-catalog
       action: catalog:register
       input:
         repoContentsUrl: ${{ steps['create-github-repo'].output.repoContentsUrl }}
   ```
4. When a developer fills in the form and clicks "Create":
   - A GitHub repo is created with Dockerfile, Helm chart, and GitHub Actions CI.
   - The service is registered in the Backstage catalog.
   - An Argo CD Application is created to deploy it.
   - Grafana dashboards are provisioned automatically.
5. Measure the "golden path" time: from form submission to first deployment in staging.
   Target: under 15 minutes.

---

### Project 23.4 — FinOps: Kubernetes Cost Visibility & Optimisation `[PROD]`

**Scenario:** Your monthly cloud bill increased 40% after the Kubernetes migration.
Engineering says they have no visibility into which team or service is driving costs.
Implement cost allocation and optimisation.

**Requirements:**
1. Install Kubecost:
   ```bash
   helm install kubecost kubecost/cost-analyzer -n kubecost --create-namespace \
     --set global.prometheus.enabled=false \
     --set global.prometheus.fqdn=http://prometheus-server.monitoring.svc
   ```
2. Label all namespaces with team ownership:
   ```bash
   kubectl label namespace payments  team=payments-team  cost-centre=CC-001
   kubectl label namespace shipping  team=logistics-team cost-centre=CC-002
   ```
3. View cost allocation: navigate to Kubecost UI → Allocation → Group by: Namespace.
   You can now see which namespace is spending what per day.
4. Identify waste:
   - Pods with requests >> actual usage (over-provisioned): `kubectl top pods -A | sort -k3 -rn`
   - PVCs with no pods mounting them: `kubectl get pvc -A | grep -v Bound`
   - LoadBalancer services with no traffic (each costs ~$15/month on AWS)
5. Implement rightsizing recommendations from VPA:
   ```bash
   # After running VPA in Off mode for 24h:
   kubectl describe vpa <name> | grep Recommendation -A 20
   ```
   Apply the recommendations to `requests` (keep `limits` at 2× requests).
6. Add Spot instance diversification to save 70–80% on worker node costs (see Section 23.1).
7. Set namespace-level budget alerts:
   ```yaml
   # Kubecost Alert
   type: budget
   threshold: 500           # alert if namespace cost exceeds $500/month
   window: month
   aggregation: namespace
   filter: namespace=payments
   ```

**Cost optimisation checklist to document:**
- [ ] All pods have correct resource requests (VPA-calibrated)
- [ ] Dev/staging clusters scale to zero outside working hours (using Karpenter consolidation)
- [ ] Spot instances used for all non-critical workloads
- [ ] Unused LoadBalancers and PVCs cleaned up monthly
- [ ] Per-team cost visibility dashboard in Grafana
- [ ] Budget alerts configured per namespace

---

### Project 23.5 — Kubernetes Upgrade Strategy `[PROD]`

**Scenario:** You need to upgrade your production cluster from 1.27 to 1.29 with zero
downtime across 50 nodes and 200 running workloads.

**Why this matters:** Kubernetes releases three minor versions per year. Each removes deprecated APIs.
Unplanned upgrades cause outages; well-planned ones are invisible to users.

**Requirements:**

**Step 1 — Pre-upgrade audit:**
```bash
# Find deprecated API versions in your manifests and cluster
kubent                                     # Kubernetes No Trouble — scans for deprecated APIs
kubectl get deployments -o yaml | grep apiVersion

# Check deprecated APIs in Helm releases
helm list -A | while read rel ns; do
  helm get manifest $rel -n $ns | kubent -
done
```
Document all findings and update manifests BEFORE upgrading.

**Step 2 — Upgrade order (always control plane first):**
```
1. Upgrade control plane (API server, controller-manager, scheduler) to 1.28
   → Verify: kubectl version shows new server version
2. Upgrade worker node group 1 (drain → upgrade kubelet → uncordon → verify)
3. Upgrade worker node group 2
4. ... repeat for all node groups
5. Upgrade kubectl and other tooling
```

**Step 3 — Drain procedure with PDB awareness:**
```bash
for node in $(kubectl get nodes -l node-group=workers -o name); do
  echo "Draining $node..."
  kubectl drain $node \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period=60 \
    --timeout=10m
  # Upgrade the node's kubelet here
  kubectl uncordon $node
  kubectl wait --for=condition=Ready $node --timeout=5m
  echo "$node upgraded and ready"
done
```

**Step 4 — Verify after each node upgrade:**
```bash
kubectl get nodes                                  # all Ready
kubectl get pods -A | grep -v Running | grep -v Completed   # no stuck pods
kubectl top nodes                                  # resource usage normal
kubectl get hpa -A                                 # HPA still functioning
```

**Step 5 — Version skew rules to enforce:**
- `kubelet` must be within 1 minor version of the API server.
- `kubectl` must be within 1 minor version (above or below) of the API server.
- Components on the same node must be upgraded together.

---

## Bonus: Interview Prep — 40 Questions to Be Able to Answer

### Kubernetes Core
1. What is the difference between a liveness probe and a readiness probe? When does each fire?
2. What is a startup probe and what problem does it solve that the other probes cannot?
3. You apply a NetworkPolicy and all pods immediately stop resolving DNS. What happened and how do you fix it?
4. Walk through the full sequence of events when you run `kubectl delete pod <pod>`.
5. What is the difference between `kubectl cordon` and `kubectl taint`?
6. How does HPA calculate desired replica count? State the formula with an example.
7. Why does HPA fail to work if container resource requests are not set?
8. A PVC is stuck in `Pending`. Walk through the full debugging process step by step.
9. What is `terminationGracePeriodSeconds` and how does it interact with a `preStop` hook?
10. When would you use a StatefulSet vs a Deployment? Give 3 concrete examples of each.

### Security & RBAC
11. What is the difference between `ClusterRole` and `Role`? Between `RoleBinding` and `ClusterRoleBinding`?
12. A service has no endpoints. What are all possible root causes and how do you diagnose each?
13. Explain base64 encoding of Secrets. Why is it NOT encryption? What should you use instead in production?
14. A node has disk pressure. What taint is automatically applied? What happens to pods on that node?
15. What is the difference between Pod Security Standards `restricted` and `baseline` profiles?
16. What does an Admission Webhook do? What is the difference between mutating and validating webhooks?
17. How does Workload Identity (IRSA on AWS / Workload Identity on GCP) work? Why is it better than static credentials?

### Scaling & Scheduling
18. What is `podAntiAffinity` with `topologyKey: kubernetes.io/hostname`? What happens if replicas > nodes with `required`?
19. Explain the difference between `maxSkew` in `TopologySpreadConstraints` and `podAntiAffinity`.
20. How does Kubernetes decide which pod to preempt when a high-priority pod cannot schedule?
21. What is the difference between Cluster Autoscaler and Karpenter? Why is Karpenter faster?
22. What are the three QoS classes in Kubernetes? What determines each? Which pods are evicted first?
23. A canary deployment works without a service mesh — what is its fundamental limitation?

### Storage & Stateful
24. What is a headless service? When would you use it? What DNS record does it return vs ClusterIP?
25. What happens during an etcd snapshot restore? What are all the required steps?
26. A pod is `OOMKilled`. How do you find the correct memory limit to set?
27. Why does deleting a StatefulSet NOT delete its PVCs? What is the benefit of this behaviour?
28. What is the difference between `ReadWriteOnce` and `ReadWriteMany`? Give a use case for each.

### Observability & Reliability
29. What is an SLO? What is an error budget? How do you decide when to freeze deploys?
30. What is the difference between head-based and tail-based trace sampling? When do you use each?
31. Explain the multi-window burn rate alerting approach. Why does a single burn rate alert have gaps?
32. A rolling update is leaving pods in `Terminating` state for 10 minutes. What are the possible causes?

### Microservices Patterns
33. What is the Saga pattern? Compare choreography and orchestration approaches.
34. What is the Outbox Pattern and what problem does it solve? What is the dual-write problem?
35. When would you use CQRS? What are the risks of over-applying it?
36. What is the Strangler Fig pattern? Why should you start with the least-coupled module first?
37. What are the three states of a circuit breaker? What triggers each transition?

### Advanced & Platform
38. Explain the Kubernetes reconciliation loop. Why is declarative desired state better than imperative commands?
39. What is eBPF? How does Cilium use it to replace iptables, and why does this matter at scale?
40. What is the difference between `Deployment` update strategy `RollingUpdate` and `Recreate`? When would you choose each?

---

## Quick Reference: Essential Commands

```bash
# ─── Cluster health ────────────────────────────────────────────────────────────
kubectl get nodes -o wide
kubectl top nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl get events --sort-by=.metadata.creationTimestamp -n <namespace>
kubectl get events -A --field-selector=type=Warning

# ─── Pod debugging ─────────────────────────────────────────────────────────────
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -c <container> --previous
kubectl exec -it <pod> -- /bin/sh
kubectl debug node/<node> -it --image=ubuntu           # debug at node level
kubectl debug <pod> -it --image=ubuntu --copy-to=debug-pod  # non-intrusive copy

# ─── Networking ────────────────────────────────────────────────────────────────
kubectl get endpoints <svc>
kubectl get networkpolicies -n <ns>
# Test connectivity from inside a pod:
kubectl run test --image=curlimages/curl --rm -it --restart=Never -- curl http://<svc>

# ─── RBAC ──────────────────────────────────────────────────────────────────────
kubectl auth can-i <verb> <resource> -n <ns> --as system:serviceaccount:<ns>:<sa>
kubectl auth can-i --list --as system:serviceaccount:<ns>:<sa>
kubectl get rolebindings,clusterrolebindings -A -o wide | grep <sa-name>

# ─── Resource governance ───────────────────────────────────────────────────────
kubectl describe node <node> | grep -A10 "Allocated resources"
kubectl get resourcequota -n <ns>
kubectl get limitrange -n <ns>
kubectl top pod --containers -n <ns>                    # per-container CPU/memory

# ─── Rollouts ──────────────────────────────────────────────────────────────────
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name> --to-revision=2
kubectl set image deployment/<name> <container>=<image>:<tag>

# ─── Storage ───────────────────────────────────────────────────────────────────
kubectl get sc,pv,pvc -A
kubectl describe pvc <name>                             # check events for provisioning errors
kubectl patch pvc <name> -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# ─── etcd backup ───────────────────────────────────────────────────────────────
ETCDCTL_API=3 etcdctl snapshot save /backup/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl snapshot status /backup/snapshot.db -w table

# ─── Security scanning ─────────────────────────────────────────────────────────
trivy image <image>:<tag>                               # scan for CVEs
trivy k8s --report=summary cluster                     # cluster-wide scan
kubent                                                  # find deprecated API versions
cosign verify --key cosign.pub <image>:<tag>            # verify image signature

# ─── GitOps ────────────────────────────────────────────────────────────────────
argocd app sync <app>
argocd app get <app> --hard-refresh
flux reconcile kustomization <name> --with-source

# ─── Kafka (Strimzi) ───────────────────────────────────────────────────────────
kubectl get kafka,kafkatopic,kafkauser -n kafka
kubectl exec -n kafka <broker-pod> -- bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --all-groups

# ─── Cost optimisation ─────────────────────────────────────────────────────────
kubectl get pods -A -o json | jq -r \
  '.items[] | .metadata.namespace + "/" + .metadata.name + " CPU: " +
   .spec.containers[0].resources.requests.cpu' | sort
```
