# Kubernetes Hands-On: Capstone Projects
> Revised & Expanded Edition — Practical, Production-Focused

---

## How to Use This Guide

Each section follows a **Scenario → Requirements → Verification → Challenge** format.
Work through sections in order for progressive skill building, or jump to any section
independently. Every exercise is designed around real incidents and production patterns.

**Skill levels used throughout:**
- `[CORE]` — Must know; appears in almost every production environment
- `[PROD]` — Intermediate; critical for day-to-day platform engineering
- `[ADV]` — Advanced; senior/staff engineer territory

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

## Bonus: Interview Prep — 25 Questions to Be Able to Answer

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
11. What is the difference between `ClusterRole` and `Role`? Between `RoleBinding` and `ClusterRoleBinding`?
12. A service has no endpoints. What are all possible root causes and how do you diagnose each?
13. How does a canary deployment work without a service mesh? What is its fundamental limitation?
14. What is `podAntiAffinity` with `topologyKey: kubernetes.io/hostname`? What happens if replicas > nodes with `required`?
15. Explain the difference between `maxSkew` in `TopologySpreadConstraints` and `podAntiAffinity`.
16. How does Kubernetes decide which pod to preempt when a high-priority pod cannot schedule?
17. What is a headless service? When would you use it? What DNS record does it return vs ClusterIP?
18. A node has disk pressure. What taint is automatically applied? What happens to pods on that node?
19. Explain base64 encoding of Secrets. Why is it NOT encryption? What should you use instead in production?
20. What happens during an etcd snapshot restore? What are all the required steps?
21. A pod is `OOMKilled`. How do you find the correct memory limit to set?
22. A rolling update is leaving pods in `Terminating` state for 10 minutes. What are the possible causes?
23. You run `kubectl apply` and the resource version is wrong. What error do you see and how do you fix it?
24. What is the difference between `Deployment` update strategy `RollingUpdate` and `Recreate`? When would you choose each?
25. Explain the reconciliation loop. Why does Kubernetes describe desired vs actual state rather than issuing imperative commands?

---

## Quick Reference: Essential Commands

```bash
# Cluster health
kubectl get nodes -o wide
kubectl top nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl get events --sort-by=.metadata.creationTimestamp -n <namespace>

# Pod debugging
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -c <container> --previous
kubectl exec -it <pod> -- /bin/sh
kubectl debug node/<node> -it --image=ubuntu

# Networking
kubectl get endpoints <svc>
kubectl get networkpolicies -n <ns>

# RBAC
kubectl auth can-i <verb> <resource> -n <ns> --as system:serviceaccount:<ns>:<sa>
kubectl auth can-i --list --as system:serviceaccount:<ns>:<sa>

# Resource governance
kubectl describe node <node> | grep -A10 "Allocated resources"
kubectl get resourcequota -n <ns>
kubectl get limitrange -n <ns>

# Rollouts
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name> --to-revision=2

# etcd backup
ETCDCTL_API=3 etcdctl snapshot save /backup/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```
