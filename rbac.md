# Kubernetes RBAC + Namespaces — Real‑Time Hands‑On Lab (Project Style)

This lab demonstrates **how RBAC works in real projects** using **two namespaces** (`dev`, `prod`) and **two ServiceAccounts**:

- **`dev-viewer`** → can **read (get/list/watch)** Pods **only in `dev`** (typical developer/monitoring access)
- **`dev-deployer`** → can **deploy/update Deployments** in `dev` + read Pods (typical CI/CD runner access)

You will **see real-time behavior** (watching Pods) and **RBAC enforcement** (Forbidden errors) exactly like in production.

---

## Prerequisites

- `kubectl` installed and configured
- You have **admin** access to the cluster in your current kubeconfig (so you can create namespaces/RBAC)
- Any Kubernetes cluster works: **minikube/kind/EKS/AKS/GKE**

Check your context:


kubectl config current-context
kubectl cluster-info


---

## Scenario (Real Project Pattern)

- `dev` namespace → Developers + CI/CD can deploy (limited)
- `prod` namespace → Only SRE/admin can deploy (CI/CD must be blocked)

---

## Step 0 — Create Namespaces


kubectl create ns dev
kubectl create ns prod

kubectl get ns


---

## Step 1 — Create ServiceAccounts


kubectl -n dev create sa dev-viewer
kubectl -n dev create sa dev-deployer

kubectl -n dev get sa


---

## Step 2 — Create RBAC Policies (Roles + RoleBindings)

### A) Read-only Pod access for `dev-viewer`


cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-pod-reader
  namespace: dev
subjects:
- kind: ServiceAccount
  name: dev-viewer
  namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF


### B) Deployer Role for `dev-deployer` (Deployments manage + Pods read)

This mimics a CI/CD runner (Jenkins/GitLab/Argo) that deploys into `dev`.


cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-deployer-role
  namespace: dev
rules:
# Allow CI/CD to manage deployments in dev
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Allow CI/CD to read pods for health checks
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-dev-deployer
  namespace: dev
subjects:
- kind: ServiceAccount
  name: dev-deployer
  namespace: dev
roleRef:
  kind: Role
  name: dev-deployer-role
  apiGroup: rbac.authorization.k8s.io
EOF


Verify objects:


kubectl -n dev get role,rolebinding,sa


---

## Step 3 — Real‑Time Proof (Watch + Deploy)

> Open **two terminals**.

### Terminal 1 — Watch Pods in real time as `dev-viewer`


kubectl -n dev get pods -w   --as=system:serviceaccount:dev:dev-viewer


Keep this running.

### Terminal 2 — Deploy + scale as `dev-deployer`

Create a Deployment:


kubectl -n dev create deployment web --image=nginx   --as=system:serviceaccount:dev:dev-deployer


Scale it to 3 replicas:


kubectl -n dev scale deployment web --replicas=3   --as=system:serviceaccount:dev:dev-deployer


✅ **Observe Terminal 1**: Pods appear/scale instantly. That is RBAC-enabled real-time watch.

---

## Step 4 — See RBAC Blocking (Forbidden) in Real Time

### A) Viewer tries to create a Pod (should FAIL)


kubectl -n dev run test --image=busybox --restart=Never   --as=system:serviceaccount:dev:dev-viewer


Expected output (example):


Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:dev:dev-viewer" cannot create resource "pods" in API group "" in the namespace "dev"


### B) Deployer tries to touch PROD (should FAIL)


kubectl -n prod create deployment hack --image=nginx   --as=system:serviceaccount:dev:dev-deployer


Expected: `Forbidden`

✅ This is the **real production safeguard**: dev/CI accounts cannot modify prod.

---

## Step 5 — Fast Permission Checks (Best Debugging Commands)

Check what an identity can do:


kubectl auth can-i list pods -n dev   --as=system:serviceaccount:dev:dev-viewer

kubectl auth can-i create deployments -n dev   --as=system:serviceaccount:dev:dev-deployer

kubectl auth can-i create deployments -n prod   --as=system:serviceaccount:dev:dev-deployer


Debug bindings:


kubectl -n dev describe rolebinding bind-pod-reader
kubectl -n dev describe rolebinding bind-dev-deployer


---

## Bonus — Run a Pod using the ServiceAccount (How Apps Use RBAC in Real Projects)

This is how a microservice/automation runs with limited permissions **inside the cluster**.

Create a Pod that uses `dev-viewer` service account:


cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: viewer-pod
  namespace: dev
spec:
  serviceAccountName: dev-viewer
  containers:
  - name: shell
    image: bitnami/kubectl:latest
    command: ["sh", "-c", "sleep 3600"]
EOF


Exec into it and try API calls:


kubectl -n dev exec -it viewer-pod -- sh

# should work
kubectl get pods -n dev

# should fail
kubectl create deployment x --image=nginx -n dev


---

## Cleanup


kubectl delete ns dev prod


---

## Notes / Troubleshooting

### 1) Impersonation (`--as`) fails
Your cluster must allow kubectl impersonation for your admin user. If `--as` is blocked, use service account token testing instead (advanced):


kubectl -n dev create token dev-viewer
kubectl -n dev create token dev-deployer


Then you can build a separate kubeconfig with those tokens.

### 2) Why `Role` not `ClusterRole`
`Role` is **namespace-scoped**. Perfect for **dev-only** and **least privilege**. Use `ClusterRole` only when you truly need cluster-wide permissions.

---

✅ You now have a project-style RBAC setup that demonstrates:

- Real-time watching of resources using `watch`
- CI/CD deploy permissions scoped to `dev`
- Production protection (`prod` is blocked)
- Fast debugging using `kubectl auth can-i`
