# Kubernetes (Intermediate) — *The Hard Way* (Step-by-Step, Real-World & Interview-Ready)

> **Goal:** Build a **strong intermediate foundation** by doing things the “hard way” (manually, intentionally, and with troubleshooting in mind).  
> This guide is designed to help you **survive real production incidents** and **answer interview questions with confidence**.

✅ What you will learn
- How Kubernetes actually works (components + workflows)
- Core objects, scheduling, probes, rollouts, and app lifecycle
- Networking basics (Services, DNS, Ingress) + troubleshooting
- Storage basics (PV/PVC/SC) + common failures
- RBAC basics + access debugging
- Practical “on-call” commands (events/logs/top/jsonpath/patch)

> **Time suggestion:** 10–14 days (2–3 hours/day) with labs.

---


# Table of Contents

- [0) Prerequisites](#0-prerequisites)
  - [0.1 Required tools](#01-required-tools)
  - [0.2 Must-know Linux basics (fast)](#02-must-know-linux-basics-fast)
- [1) Create Your Learning Cluster (the “hard way” for intermediate)](#1-create-your-learning-cluster-the-hard-way-for-intermediate)
  - [Option A (recommended): **kubeadm** on 1 control-plane + 1 worker (best realism)](#option-a-recommended-kubeadm-on-1-control-plane-1-worker-best-realism)
  - [Option B: **kind** (fast, great for repeatable labs)](#option-b-kind-fast-great-for-repeatable-labs)
- [2) kubectl Power — Survival Commands (use daily)](#2-kubectl-power-survival-commands-use-daily)
  - [2.1 Contexts, namespaces, and sanity checks](#21-contexts-namespaces-and-sanity-checks)
  - [2.2 Fast triage: “What is broken?”](#22-fast-triage-what-is-broken)
  - [2.3 JSONPath/JQ (interview + real life)](#23-jsonpathjq-interview-real-life)
  - [2.4 Patch quickly (critical incidents)](#24-patch-quickly-critical-incidents)
  - [2.5 Rollout control](#25-rollout-control)
- [3) Core Objects — Learn by Building](#3-core-objects-learn-by-building)
  - [3.1 Pod → Deployment → ReplicaSet (hands-on)](#31-pod-deployment-replicaset-hands-on)
  - [3.2 Labels & selectors (mandatory)](#32-labels-selectors-mandatory)
  - [3.3 ConfigMap & Secret (and how apps consume them)](#33-configmap-secret-and-how-apps-consume-them)
- [4) Scheduling & Placement — The Interview Favorites](#4-scheduling-placement-the-interview-favorites)
  - [4.1 Requests/Limits (avoid OOM/CPU starvation)](#41-requestslimits-avoid-oomcpu-starvation)
  - [4.2 Node selection](#42-node-selection)
  - [4.3 PodDisruptionBudget (production stability)](#43-poddisruptionbudget-production-stability)
- [5) Health Checks — Probes That Save You in Production](#5-health-checks-probes-that-save-you-in-production)
  - [5.1 Readiness vs Liveness](#51-readiness-vs-liveness)
- [6) Networking — Services, DNS, Ingress (and debugging)](#6-networking-services-dns-ingress-and-debugging)
  - [6.1 Cluster DNS checks](#61-cluster-dns-checks)
  - [6.2 Service types & when to use](#62-service-types-when-to-use)
  - [6.3 Ingress basics (Nginx Ingress or Traefik)](#63-ingress-basics-nginx-ingress-or-traefik)
  - [6.4 Network troubleshooting toolkit](#64-network-troubleshooting-toolkit)
- [7) Storage — PV/PVC/SC (intermediate must-have)](#7-storage-pvpvcsc-intermediate-must-have)
  - [7.1 Understand flow](#71-understand-flow)
  - [7.2 Common failures (PVC Pending)](#72-common-failures-pvc-pending)
  - [7.3 StatefulSet intro (why it matters)](#73-statefulset-intro-why-it-matters)
- [8) RBAC (Intermediate Security) — Practical & Interview](#8-rbac-intermediate-security-practical-interview)
  - [8.1 Can-I checks (fast permission debugging)](#81-can-i-checks-fast-permission-debugging)
  - [8.2 Create a limited Role + RoleBinding](#82-create-a-limited-role-rolebinding)
- [9) Debugging Playbooks — “On-call Survival”](#9-debugging-playbooks-on-call-survival)
  - [9.1 Pod stuck in Pending](#91-pod-stuck-in-pending)
  - [9.2 CrashLoopBackOff](#92-crashloopbackoff)
  - [9.3 ImagePullBackOff](#93-imagepullbackoff)
  - [9.4 Service not reachable](#94-service-not-reachable)
  - [9.5 Node NotReady / pressure](#95-node-notready-pressure)
  - [9.6 Debug containers & ephemeral debugging](#96-debug-containers-ephemeral-debugging)
- [10) Safe Operations — Cordon/Drain and Rollbacks](#10-safe-operations-cordondrain-and-rollbacks)
  - [10.1 Cordon and drain (maintenance)](#101-cordon-and-drain-maintenance)
  - [10.2 Emergency rollback](#102-emergency-rollback)
- [11) Intermediate Labs (Do these in order)](#11-intermediate-labs-do-these-in-order)
  - [Lab 1: Build and validate cluster](#lab-1-build-and-validate-cluster)
  - [Lab 2: Deploy & expose an app](#lab-2-deploy-expose-an-app)
  - [Lab 3: Config and secrets](#lab-3-config-and-secrets)
  - [Lab 4: Probes + zero-downtime rollout](#lab-4-probes-zero-downtime-rollout)
  - [Lab 5: Scheduling controls](#lab-5-scheduling-controls)
  - [Lab 6: Storage basics](#lab-6-storage-basics)
  - [Lab 7: RBAC](#lab-7-rbac)
  - [Lab 8: Incident simulation](#lab-8-incident-simulation)
- [12) Interview Checklist (Intermediate)](#12-interview-checklist-intermediate)
- [13) Quick Reference — Critical Command Cheat Sheet](#13-quick-reference-critical-command-cheat-sheet)
- [Next Step: Move to **Advanced — The Hard Way**](#next-step-move-to-advanced-the-hard-way)



## 0) Prerequisites

### 0.1 Required tools
- Linux machine (or WSL2) with sudo
- `kubectl`, `kubeadm`, `kubelet`, container runtime (containerd recommended)
- `jq`, `curl`, `iproute2`, `net-tools`, `dnsutils`

**Verify tools:**

kubectl version --client --output=yaml
kubeadm version
crictl --version || true
jq --version


### 0.2 Must-know Linux basics (fast)

# CPU/RAM/Disk quick checks
lscpu | head
free -h
df -h

# Network quick checks
ip a
ip r
ss -lntp | head


---

## 1) Create Your Learning Cluster (the “hard way” for intermediate)

### Option A (recommended): **kubeadm** on 1 control-plane + 1 worker (best realism)
> This is closer to real work than minikube, and still manageable.

#### 1.1 Prepare nodes
On **all nodes**:

# Disable swap (Kubernetes requirement)
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl for networking
cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
sudo sysctl --system

# Install containerd (distribution-specific steps omitted)
# Ensure containerd uses SystemdCgroup=true for kubelet stability.


#### 1.2 Initialize control plane
On **control-plane**:

sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubectl access
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes


#### 1.3 Install a CNI (Calico example)

# Install Calico (apply official manifest you trust from the vendor docs)
# kubectl apply -f <calico-manifest.yaml>

kubectl get pods -n kube-system -w


#### 1.4 Join worker node
On **worker**: use the `kubeadm join ...` command printed during init.

sudo kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>


Confirm:

kubectl get nodes -o wide


### Option B: **kind** (fast, great for repeatable labs)

kind create cluster --name k8s-labs
kubectl cluster-info


---

## 2) kubectl Power — Survival Commands (use daily)

### 2.1 Contexts, namespaces, and sanity checks

kubectl config get-contexts
kubectl config use-context <ctx>

kubectl get ns
kubectl get nodes -o wide
kubectl get pods -A | head


### 2.2 Fast triage: “What is broken?”

kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 30
kubectl describe pod <pod>
kubectl logs <pod> -c <container> --tail=200
kubectl logs <pod> --previous --tail=200


### 2.3 JSONPath/JQ (interview + real life)

# Images used in a deployment
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[*].image}'

# Node of a pod
kubectl get pod <pod> -o jsonpath='{.spec.nodeName}{"\n"}'

# Show pod labels
kubectl get pod <pod> -o json | jq '.metadata.labels'


### 2.4 Patch quickly (critical incidents)

# Add an env var without editing full YAML
kubectl patch deploy <name> -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","env":[{"name":"LOG_LEVEL","value":"debug"}]}]}}}}'


### 2.5 Rollout control

kubectl rollout status deploy/<name>
kubectl rollout history deploy/<name>
kubectl rollout undo deploy/<name>

# Pause/Resume during incident
kubectl rollout pause deploy/<name>
kubectl rollout resume deploy/<name>


---

## 3) Core Objects — Learn by Building

### 3.1 Pod → Deployment → ReplicaSet (hands-on)
Create a deployment:

kubectl create deploy web --image=nginx:1.25 --replicas=2
kubectl get deploy,rs,pods -o wide


Expose it:

kubectl expose deploy web --port=80 --type=ClusterIP
kubectl get svc web -o wide


### 3.2 Labels & selectors (mandatory)

kubectl get pods -l app=web
kubectl label pod <pod> tier=frontend --overwrite
kubectl get pods --show-labels


### 3.3 ConfigMap & Secret (and how apps consume them)

kubectl create configmap app-cm --from-literal=MODE=prod
kubectl create secret generic app-secret --from-literal=TOKEN='abc123'

kubectl get cm,secret
kubectl describe cm app-cm


Mount them into a pod (practice YAML editing):

kubectl get deploy web -o yaml > web.yaml
# Edit web.yaml: add envFrom and secretRef, then apply
kubectl apply -f web.yaml
kubectl rollout status deploy/web


---

## 4) Scheduling & Placement — The Interview Favorites

### 4.1 Requests/Limits (avoid OOM/CPU starvation)

kubectl set resources deploy/web -c nginx --requests=cpu=100m,memory=128Mi --limits=cpu=300m,memory=256Mi
kubectl describe pod -l app=web | egrep -i 'Requests|Limits' -n


### 4.2 Node selection
- `nodeSelector`
- `nodeAffinity`
- `taints/tolerations`

**Practice:**

# Taint a node (pods won't schedule unless tolerated)
kubectl taint nodes <node> dedicated=apps:NoSchedule

# Remove taint
kubectl taint nodes <node> dedicated=apps:NoSchedule-


### 4.3 PodDisruptionBudget (production stability)
yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: web

Apply:

kubectl apply -f pdb.yaml
kubectl get pdb


---

## 5) Health Checks — Probes That Save You in Production

### 5.1 Readiness vs Liveness
- **Readiness**: remove pod from Service endpoints (no traffic)
- **Liveness**: restart container if unhealthy

Add probes to `web.yaml`:
yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 20
  periodSeconds: 10


Verify endpoints:

kubectl get endpoints web -o wide


---

## 6) Networking — Services, DNS, Ingress (and debugging)

### 6.1 Cluster DNS checks

kubectl -n kube-system get pods -l k8s-app=kube-dns

# From a debug pod
kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -- sh
nslookup kubernetes.default
nslookup web.default.svc.cluster.local


### 6.2 Service types & when to use
- `ClusterIP`: internal-only
- `NodePort`: quick testing
- `LoadBalancer`: cloud


kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'
kubectl get svc web -o wide


### 6.3 Ingress basics (Nginx Ingress or Traefik)
> Install an ingress controller first (vendor docs). Then create Ingress.

Common debugging:

kubectl describe ingress -A
kubectl get pods -n ingress-nginx -o wide
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=200


### 6.4 Network troubleshooting toolkit

# Service endpoints empty? -> readiness/labels mismatch
kubectl get endpoints web -o yaml
kubectl get pod -l app=web --show-labels

# Check kube-proxy / CNI pods
kubectl -n kube-system get pods -o wide | egrep 'kube-proxy|calico|cilium|flannel'


---

## 7) Storage — PV/PVC/SC (intermediate must-have)

### 7.1 Understand flow
StorageClass → PVC → PV → Pod

Check what exists:

kubectl get sc
kubectl get pv
kubectl get pvc -A


### 7.2 Common failures (PVC Pending)

kubectl describe pvc <pvc>
# Look for: no StorageClass, no provisioner, insufficient capacity, access mode mismatch


### 7.3 StatefulSet intro (why it matters)

kubectl create deploy stateless --image=nginx:1.25
# Now compare with a StatefulSet lab once you add storage.


---

## 8) RBAC (Intermediate Security) — Practical & Interview

### 8.1 Can-I checks (fast permission debugging)

kubectl auth can-i get pods
kubectl auth can-i create deploy -n default
kubectl auth can-i list secrets -A


### 8.2 Create a limited Role + RoleBinding
yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: default
subjects:
- kind: User
  name: dev-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io


---

## 9) Debugging Playbooks — “On-call Survival”

### 9.1 Pod stuck in Pending

kubectl describe pod <pod>
# Look for: Insufficient cpu/memory, taints, nodeSelector mismatch, image pull, PVC pending
kubectl get nodes
kubectl top nodes || true


### 9.2 CrashLoopBackOff

kubectl describe pod <pod>
kubectl logs <pod> --previous --tail=200
kubectl logs <pod> --tail=200


### 9.3 ImagePullBackOff

kubectl describe pod <pod> | egrep -i 'image|pull|back-off' -n
# On node (if you have access)
crictl images | head
crictl pull <image>


### 9.4 Service not reachable
Checklist:
- pod Ready? (readiness)
- endpoints populated?
- correct selector labels?
- network policies?

Commands:

kubectl get svc web -o wide
kubectl get endpoints web -o wide
kubectl get pod -l app=web -o wide
kubectl describe pod -l app=web | egrep -i 'readiness|liveness|ready' -n


### 9.5 Node NotReady / pressure

kubectl get nodes
kubectl describe node <node> | egrep -i 'Ready|MemoryPressure|DiskPressure|PIDPressure' -n

# If you can SSH to node
sudo journalctl -u kubelet -n 200 --no-pager
sudo dmesg | tail -n 50


### 9.6 Debug containers & ephemeral debugging

kubectl debug -it pod/<pod> --image=busybox:1.36 --target=<container> -- sh


---

## 10) Safe Operations — Cordon/Drain and Rollbacks

### 10.1 Cordon and drain (maintenance)

kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Bring back
kubectl uncordon <node>


### 10.2 Emergency rollback

kubectl rollout undo deploy/<name>
kubectl rollout status deploy/<name>


---

## 11) Intermediate Labs (Do these in order)

### Lab 1: Build and validate cluster
- Install cluster (kubeadm or kind)
- Verify CoreDNS and CNI pods are Running

### Lab 2: Deploy & expose an app
- Create Deployment, Service
- Validate endpoints and DNS

### Lab 3: Config and secrets
- ConfigMap + Secret
- Mount as env + volume

### Lab 4: Probes + zero-downtime rollout
- Add readiness/liveness
- Rolling update; undo

### Lab 5: Scheduling controls
- Add requests/limits
- Add taints & tolerations
- Verify scheduling behavior

### Lab 6: Storage basics
- Create PVC
- Debug a `Pending` PVC

### Lab 7: RBAC
- Create Role/RoleBinding
- Validate `kubectl auth can-i`

### Lab 8: Incident simulation
- Break DNS (delete CoreDNS pod) and recover
- Simulate CrashLoop with bad command and recover
- Simulate image pull failure and fix

---

## 12) Interview Checklist (Intermediate)

Be able to explain confidently:
- Pod vs Deployment vs ReplicaSet
- Readiness vs liveness
- How Service selects endpoints
- Why pods can be Pending
- ConfigMap/Secret usage patterns
- Requests/Limits and OOMKilled
- Basic RBAC and `auth can-i`
- How DNS works inside cluster
- CNI and kube-proxy at a high level

---

## 13) Quick Reference — Critical Command Cheat Sheet


# What’s wrong now?
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 50

# Pod deep dive
kubectl describe pod <pod>
kubectl logs <pod> --tail=200
kubectl logs <pod> --previous --tail=200
kubectl exec -it <pod> -- sh

# Network
kubectl get svc,endpoints -o wide
kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -- sh

# Rollouts
kubectl rollout status deploy/<name>
kubectl rollout undo deploy/<name>

# Nodes
kubectl describe node <node>
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Access
kubectl auth can-i <verb> <resource> -n <ns>


---

## Next Step: Move to **Advanced — The Hard Way**
Once you finish all labs above, you’re ready for advanced topics like:
- etcd backup/restore, HA control plane
- custom admission webhooks, advanced RBAC
- deep networking (eBPF, policies), service meshes
- production-grade observability and SLOs

If you want, I can generate the **Advanced README** as a full 30-day “hard way” with labs + solutions.
