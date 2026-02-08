# Kubernetes Basics — “Hard Way (Pragmatic)” Step‑by‑Step

> **Goal:** Build a *strong foundation* in Kubernetes (K8s) by doing the work manually enough to truly understand what’s happening—**without** hiding behind fully managed services. You’ll create a small cluster with `kubeadm`, then learn to operate it like a real SRE/DevOps engineer: debug, recover, and survive production‑style incidents.
>
> **Why “Pragmatic Hard Way”?** The absolute “pure hard way” (manual certs + etcd + apiserver + controller-manager + scheduler + kubelet wiring) is excellent but time‑heavy. This README gives you **90% of the real-world value** in the shortest time:
> - You **provision and bootstrap** your own cluster (no EKS/GKE/AKS magic)
> - You **inspect and reason** about control-plane components, certs, kubeconfigs, etc.
> - You practice **hands-on troubleshooting and critical commands** used in interviews and on-call.
> - Optional appendix shows how to go even deeper.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Lab Setup (2 Nodes)](#2-lab-setup-2-nodes)
3. [Install Container Runtime (containerd)](#3-install-container-runtime-containerd)
4. [Install Kubernetes Tools](#4-install-kubernetes-tools)
5. [Bootstrap Cluster with kubeadm](#5-bootstrap-cluster-with-kubeadm)
6. [Kubernetes Objects — Basics You Must Know](#6-kubernetes-objects--basics-you-must-know)
7. [Networking + Service Discovery](#7-networking--service-discovery)
8. [Storage Basics](#8-storage-basics)
9. [ConfigMaps, Secrets, and Safer Patterns](#9-configmaps-secrets-and-safer-patterns)
10. [RBAC + Namespaces (Minimum Survival)](#10-rbac--namespaces-minimum-survival)
11. [Probes, Resources, and Autoscaling](#11-probes-resources-and-autoscaling)
12. [Debugging & Incident Commands (Must-Memorize)](#12-debugging--incident-commands-must-memorize)
13. [Control Plane Internals (Real “Hard Way” Understanding)](#13-control-plane-internals-real-hard-way-understanding)
14. [Disaster Recovery Drills](#14-disaster-recovery-drills)
15. [Interview Drills (Fast Questions + Commands)](#15-interview-drills-fast-questions--commands)
16. [Appendix A — Going “Full Hard Way” (Optional)](#appendix-a--going-full-hard-way-optional)

---

## 1) Prerequisites

### Recommended lab
- **2 Linux VMs** (Ubuntu 22.04/24.04 recommended)
  - **Control-plane**: 2 CPU, 4–8 GB RAM
  - **Worker**: 2 CPU, 4 GB RAM
- Static IPs or stable DHCP leases
- Passwordless sudo for your user

### Must-have basics
- Comfortable with:
  - `systemctl`, `journalctl`, `ip a`, `ss -lntp`, `curl`, `openssl`
  - YAML editing (`vim`/`nano`)

### Naming
Set these (adjust IPs/hostnames):

```bash
# On control-plane
sudo hostnamectl set-hostname k8s-cp

# On worker
sudo hostnamectl set-hostname k8s-w1
```

Ensure both nodes can resolve each other (use `/etc/hosts` if needed):

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
10.0.0.10 k8s-cp
10.0.0.11 k8s-w1
EOF
```

Disable swap (required):

```bash
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab
```

Kernel modules + sysctl:

```bash
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

---

## 2) Lab Setup (2 Nodes)

> You will install:
> - Container runtime: **containerd**
> - Kubernetes: **kubeadm**, **kubelet**, **kubectl**
> - CNI: **Calico** (common and interview-friendly)

Repeat sections **3** and **4** on **both nodes**.

---

## 3) Install Container Runtime (containerd)

> If you already have containerd, still confirm `SystemdCgroup = true`.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
```

Install containerd:

```bash
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Important: enable systemd cgroups
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

Verify:

```bash
sudo systemctl status containerd --no-pager
```

---

## 4) Install Kubernetes Tools

> Choose a stable K8s version and keep it consistent across nodes.
> Replace `v1.29` with your desired minor release.

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

# Kubernetes apt repository key + repo
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Check:

```bash
kubeadm version
kubectl version --client
kubelet --version
```

---

## 5) Bootstrap Cluster with kubeadm

### 5.1 Control-plane init (on `k8s-cp`)

Pick a Pod CIDR (Calico commonly uses `192.168.0.0/16`):

```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=10.0.0.10
```

Configure kubectl for your user:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 5.2 Install CNI (Calico)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait:

```bash
kubectl get nodes
kubectl get pods -A -w
```

Expected: CoreDNS + Calico pods become `Running`.

### 5.3 Join worker (on `k8s-w1`)

From the `kubeadm init` output, copy the join command:

```bash
sudo kubeadm join 10.0.0.10:6443 --token <...> --discovery-token-ca-cert-hash sha256:<...>
```

Back on control-plane:

```bash
kubectl get nodes -o wide
```

---

## 6) Kubernetes Objects — Basics You Must Know

### 6.1 Pods (the basic unit)

Create a pod:

```bash
kubectl run nginx-pod --image=nginx:1.25 --restart=Never
kubectl get pod nginx-pod -o wide
kubectl describe pod nginx-pod
```

Exec inside:

```bash
kubectl exec -it nginx-pod -- bash
# inside:
nginx -v
exit
```

Delete:

```bash
kubectl delete pod nginx-pod
```

### 6.2 Deployments (stateless workloads)

```bash
kubectl create deployment web --image=nginx:1.25
kubectl scale deployment web --replicas=3
kubectl get deploy,rs,pods -o wide
```

Rolling update:

```bash
kubectl set image deployment/web nginx=nginx:1.26
kubectl rollout status deployment/web
kubectl rollout history deployment/web
```

Rollback:

```bash
kubectl rollout undo deployment/web
```

### 6.3 ReplicaSets (usually managed by Deployments)

```bash
kubectl get rs
kubectl describe rs -l app=web
```

### 6.4 DaemonSets (one pod per node)

```bash
kubectl create deployment dummy --image=busybox -- sleep 3600 || true
kubectl delete deploy dummy || true

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-logger
spec:
  selector:
    matchLabels:
      app: node-logger
  template:
    metadata:
      labels:
        app: node-logger
    spec:
      containers:
      - name: bb
        image: busybox:1.36
        command: ["sh","-c","while true; do echo $(date) $(hostname); sleep 10; done"]
EOF

kubectl get ds,pods -o wide
```

### 6.5 Jobs / CronJobs (batch)

```bash
kubectl create job once --image=busybox:1.36 -- sh -c 'echo hello; sleep 2; echo done'
kubectl logs job/once
kubectl delete job once
```

---

## 7) Networking + Service Discovery

### 7.1 Services (ClusterIP/NodePort/LoadBalancer)

Expose the `web` Deployment:

```bash
kubectl expose deployment web --port=80 --target-port=80 --name=web-svc
kubectl get svc web-svc -o wide
```

Test DNS and service reachability from inside the cluster:

```bash
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- sh
# inside
nslookup web-svc
wget -qO- http://web-svc
exit
```

Port-forward for local debugging (super useful):

```bash
kubectl port-forward svc/web-svc 8080:80
# open http://localhost:8080
```

### 7.2 Ingress (concept)

Ingress requires an Ingress Controller (nginx, traefik, etc.).
In real-world, you will install one and route HTTP using Ingress resources.

**Survival concept:**
- Service = L4 load balancing inside cluster
- Ingress = L7 routing from outside into services

---

## 8) Storage Basics

### 8.1 Volumes in a Pod (emptyDir)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vol-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","echo hi > /data/hello.txt; sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    emptyDir: {}
EOF

kubectl exec -it vol-demo -- cat /data/hello.txt
kubectl delete pod vol-demo
```

### 8.2 PersistentVolumeClaim (PVC) concept

In cloud, StorageClasses dynamically provision PVs. In bare-metal, you often use NFS/Longhorn/Rook.

**Must-know interview points:**
- PVC = request for storage
- PV = actual storage resource
- StorageClass = dynamic provisioning policy

---

## 9) ConfigMaps, Secrets, and Safer Patterns

### 9.1 ConfigMap from literals

```bash
kubectl create configmap app-config --from-literal=LOG_LEVEL=debug --from-literal=FEATURE_X=true
kubectl get cm app-config -o yaml
```

Consume in a Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cm-demo
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c","env | grep -E 'LOG_LEVEL|FEATURE_X'; sleep 3600"]
    envFrom:
    - configMapRef:
        name: app-config
EOF

kubectl logs cm-demo
kubectl delete pod cm-demo
```

### 9.2 Secrets (base64 ≠ encryption)

```bash
kubectl create secret generic db-secret --from-literal=DB_USER=admin --from-literal=DB_PASS='S3cr3t!'
kubectl get secret db-secret -o yaml
```

**Survival rule:** Treat Secrets carefully; don’t paste them in tickets/chats. Use sealed-secrets or external secret managers in real production.

---

## 10) RBAC + Namespaces (Minimum Survival)

Create namespace:

```bash
kubectl create ns dev
kubectl get ns
```

List permissions (amazing for debugging access issues):

```bash
kubectl auth can-i create pods -n dev
kubectl auth can-i '*' '*' --all-namespaces
```

Basic RBAC example (read-only pods in `dev`):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","list","watch"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: read-sa
  namespace: dev
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: dev
subjects:
- kind: ServiceAccount
  name: read-sa
  namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

---

## 11) Probes, Resources, and Autoscaling

### 11.1 Liveness/Readiness probes

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: probe-demo
  template:
    metadata:
      labels:
        app: probe-demo
    spec:
      containers:
      - name: web
        image: nginx:1.25
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
EOF

kubectl get pods -l app=probe-demo -w
```

### 11.2 Requests & limits (critical in production)

```bash
kubectl set resources deployment/probe-demo \
  --requests=cpu=50m,memory=64Mi \
  --limits=cpu=200m,memory=128Mi

kubectl describe deploy probe-demo | sed -n '/Limits:/,/Environment:/p'
```

### 11.3 HPA (concept)

HPA needs metrics-server installed. On many clusters it exists already.

Check:

```bash
kubectl top nodes || true
kubectl top pods -A || true
```

---

## 12) Debugging & Incident Commands (Must-Memorize)

> This section is your **real-time survival playbook**.

### 12.1 “What’s broken?” — fastest triage

```bash
# cluster health
kubectl get nodes -o wide
kubectl get pods -A | head

# sort by restarts
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'

# events (often reveals scheduling/image pull issues)
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 30

# what changed recently?
kubectl rollout history deploy/<name>
```

### 12.2 Pod stuck in Pending

```bash
kubectl describe pod <pod>
# Look for: Insufficient cpu/memory, taints, node selectors, PVC pending

kubectl get nodes
kubectl describe node <node>
kubectl get pvc -A
```

### 12.3 Pod CrashLoopBackOff

```bash
kubectl logs <pod> -c <container> --previous
kubectl describe pod <pod>

# quick shell
kubectl exec -it <pod> -c <container> -- sh

# copy files out
kubectl cp <pod>:/path/in/container ./localfile
```

### 12.4 ImagePullBackOff

```bash
kubectl describe pod <pod>
# verify image name, tag, registry auth secret

kubectl get secret -A | grep -i docker || true
```

### 12.5 Service not reachable

```bash
kubectl get svc,ep -n <ns>
kubectl describe svc <svc> -n <ns>

# confirm endpoints exist
kubectl get endpoints <svc> -n <ns> -o yaml

# DNS check inside cluster
kubectl run -it --rm net --image=busybox:1.36 --restart=Never -- sh
nslookup <svc>.<ns>.svc.cluster.local
wget -qO- http://<svc>.<ns>.svc.cluster.local:<port>
exit
```

### 12.6 Node troubleshooting (on the node)

```bash
# kubelet status + logs
sudo systemctl status kubelet --no-pager
sudo journalctl -u kubelet -n 200 --no-pager

# container runtime
sudo systemctl status containerd --no-pager
sudo journalctl -u containerd -n 200 --no-pager

# ports
sudo ss -lntp | egrep '6443|2379|2380|10250|10257|10259' || true

# networking
ip a
ip route
sudo iptables -S | head
```

### 12.7 Critical rollout commands

```bash
# Pause/Resume rollouts
kubectl rollout pause deploy/<name>
kubectl rollout resume deploy/<name>

# Monitor rollout
kubectl rollout status deploy/<name>

# Roll back quickly
kubectl rollout undo deploy/<name>

# Restart deployment (forces new ReplicaSet)
kubectl rollout restart deploy/<name>
```

### 12.8 Debug without changing images (ephemeral debug pods)

```bash
# Create a temporary debugging pod in same namespace
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Or attach ephemeral container (if enabled)
# kubectl debug -it <pod> --image=nicolaka/netshoot --target=<container>
```

### 12.9 Powerful query patterns (JSONPath, wide, labels)

```bash
# Get pod node placement
kubectl get pod -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.spec.nodeName}{"\n"}{end}' | head

# List images used
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{","}{end}{"\n"}{end}' | head

# See resources quickly
kubectl get pod <pod> -o yaml | sed -n '/resources:/,/securityContext:/p'
```

### 12.10 Node maintenance (cordon/drain)

```bash
kubectl cordon <node>

# Drain safely (ignore daemonsets, delete emptydir data)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

kubectl uncordon <node>
```


### 12.11 Real‑World Survival Commands (Quick Reference)

> **Use this during on‑call / production incidents.** These are the commands you’ll run again and again.
> ⚠️ Destructive commands are marked **DANGER**.

#### A) Context, namespace, and speed setup

```bash
# see contexts / switch context
kubectl config get-contexts
kubectl config use-context <context>

# set default namespace for your current context
kubectl config set-context --current --namespace=<ns>

# quick aliases (put in ~/.bashrc)
alias k=kubectl
alias kg='kubectl get'
alias kd='kubectl describe'
alias ka='kubectl apply -f'
alias ke='kubectl explain'
```

#### B) Find “what changed” and “what’s failing” fast

```bash
# all namespaces overview
kubectl get pods -A -o wide
kubectl get deploy,ds,sts -A

# show non-Running pods only
kubectl get pods -A | egrep -v 'Running|Completed'

# events: always check during incidents
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50

# which pods restarted the most
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' | tail -n 20

# last applied / diff before applying
kubectl diff -f <file.yaml> || true
```

#### C) Live log tailing and quick attach

```bash
# follow logs
kubectl logs -f <pod> -c <container>

# get previous crash logs
kubectl logs <pod> -c <container> --previous

# attach (useful for one-shot debugging)
kubectl attach -it <pod> -c <container>

# run a temporary debug pod with useful tools
kubectl run -it --rm netshoot --image=nicolaka/netshoot --restart=Never -- bash
```

#### D) Emergency rollout control (deployments)

```bash
# stop the bleeding
kubectl rollout pause deploy/<name>

# check rollout status
kubectl rollout status deploy/<name>

# rollback to previous revision
kubectl rollout undo deploy/<name>

# restart pods without changing image
kubectl rollout restart deploy/<name>

# scale down quickly
kubectl scale deploy/<name> --replicas=0
# scale back
kubectl scale deploy/<name> --replicas=<n>
```

#### E) Labels, selectors, and “show me exactly these”

```bash
# by label
kubectl get pods -n <ns> -l app=<name> -o wide

# show labels
kubectl get pods -n <ns> --show-labels

# edit labels (common fix for Service endpoints mismatch)
kubectl label pod <pod> -n <ns> app=<name> --overwrite

# field selector (e.g., pods on a node)
kubectl get pods -A --field-selector spec.nodeName=<node> -o wide
```

#### F) Service and DNS debugging (classic outage)

```bash
kubectl get svc,ep -n <ns>
kubectl describe svc <svc> -n <ns>

# if endpoints are empty, check selectors + readiness
kubectl get pods -n <ns> -l <selector> -o wide
kubectl describe pod <pod> -n <ns>

# DNS inside cluster
kubectl run -it --rm dns --image=busybox:1.36 --restart=Never -- sh
nslookup kubernetes.default
nslookup <svc>.<ns>.svc.cluster.local
wget -qO- http://<svc>.<ns>.svc.cluster.local:<port>
exit
```

#### G) “It won’t delete!” — stuck resources and finalizers (**DANGER**)

```bash
# see finalizers
kubectl get <type> <name> -n <ns> -o jsonpath='{.metadata.finalizers}'

# DANGER: remove finalizers (use only when you understand impact)
kubectl patch <type> <name> -n <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge

# DANGER: force delete a stuck pod
kubectl delete pod <pod> -n <ns> --grace-period=0 --force

# DANGER: stuck namespace cleanup
kubectl get ns <ns> -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

> If you don’t have `jq`, install it: `sudo apt-get install -y jq`.

#### H) Node-level triage (when kubectl is not enough)

```bash
# kubelet logs
sudo journalctl -u kubelet -n 200 --no-pager

# container runtime
sudo systemctl status containerd --no-pager
sudo journalctl -u containerd -n 200 --no-pager

# install crictl (if missing)
# sudo apt-get install -y cri-tools

# list running containers in the node runtime
sudo crictl ps
sudo crictl pods

# inspect and logs
sudo crictl logs <container_id>
sudo crictl inspect <container_id> | head
```

#### I) Control-plane / kubeadm “oh no” commands

```bash
# check certificate expiry (very common real-world issue)
sudo kubeadm certs check-expiration

# renew all certs (control-plane node)
# sudo kubeadm certs renew all

# see static pod manifests
sudo ls -l /etc/kubernetes/manifests/

# if a control-plane component is unhealthy, check kubelet + container logs
sudo journalctl -u kubelet -n 200 --no-pager
```

#### J) Resource pressure & scheduling (why pods won't schedule)

```bash
# node pressure
kubectl describe node <node> | egrep -i 'Pressure|Allocatable|Allocated|Taints' -n

# if metrics-server exists
kubectl top nodes || true
kubectl top pods -A --sort-by=cpu || true
kubectl top pods -A --sort-by=memory || true

# see pod QoS class (helps understand eviction)
kubectl get pod <pod> -n <ns> -o jsonpath='{.status.qosClass}' ; echo
```

---

## 13) Control Plane Internals (Real “Hard Way” Understanding)

> This is where you become “dangerous” (in a good way). You’ll learn where K8s stores its truth and how components run.

### 13.1 Control plane is static pods (kubeadm)

On control-plane node:

```bash
ls -l /etc/kubernetes/manifests/
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
# etcd.yaml
```

These files are watched by kubelet; changing them changes control-plane behavior.

### 13.2 Certificates and kubeconfigs

```bash
sudo ls -l /etc/kubernetes/pki/
# apiserver.crt, apiserver.key, ca.crt, etc.

sudo ls -l /etc/kubernetes/
# admin.conf, controller-manager.conf, scheduler.conf, kubelet.conf
```

**Interview must-know:**
- API Server is the front door
- etcd stores cluster state
- Controller Manager makes desired state real
- Scheduler assigns pods to nodes
- Kubelet runs pods on each node
- kube-proxy programs service routing

### 13.3 etcd health + snapshot (very real-world)

etcd runs as a static pod. Find it:

```bash
kubectl -n kube-system get pods | grep etcd
```

Snapshot etcd (safe practice):

```bash
# run inside etcd container via kubectl exec
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl -n kube-system exec $ETCD_POD -- sh -c 'ETCDCTL_API=3 etcdctl version' || true

# common kubeadm cert paths (inside the pod)
kubectl -n kube-system exec $ETCD_POD -- sh -c '\
ETCDCTL_API=3 etcdctl \\
  --endpoints=https://127.0.0.1:2379 \\
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\
  --cert=/etc/kubernetes/pki/etcd/server.crt \\
  --key=/etc/kubernetes/pki/etcd/server.key \\
  snapshot save /var/lib/etcd/snapshot.db\
ls -lh /var/lib/etcd/snapshot.db\
'
```

Copy snapshot to your local machine:

```bash
kubectl -n kube-system cp ${ETCD_POD}:/var/lib/etcd/snapshot.db ./snapshot.db
ls -lh snapshot.db
```

---

## 14) Disaster Recovery Drills

> Do these in a lab only.

### 14.1 Break DNS and fix it

1) Scale CoreDNS to 0:

```bash
kubectl -n kube-system scale deploy/coredns --replicas=0
```

2) Watch apps failing name resolution from a test pod.

3) Restore:

```bash
kubectl -n kube-system scale deploy/coredns --replicas=2
kubectl -n kube-system rollout status deploy/coredns
```

### 14.2 Simulate a bad rollout and recover fast

```bash
kubectl create deployment bad --image=nginx:1.25
kubectl set image deployment/bad nginx=nginx:this-tag-does-not-exist
kubectl rollout status deployment/bad || true

# Investigate
kubectl get pods -l app=bad
kubectl describe pod -l app=bad | sed -n '/Events:/,$p'

# Recover
kubectl rollout undo deployment/bad
kubectl rollout status deployment/bad
```

### 14.3 Node drain + uncordon drill

```bash
kubectl get nodes
kubectl cordon k8s-w1
kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data

# confirm pods rescheduled
kubectl get pods -A -o wide | head

kubectl uncordon k8s-w1
```

---

## 15) Interview Drills (Fast Questions + Commands)

### 15.1 “Explain flow” (say this confidently)

1. `kubectl` talks to **API Server**
2. API Server validates/admission, stores desired state in **etcd**
3. **Scheduler** assigns Pods to Nodes
4. **Kubelet** on node pulls images and runs containers via runtime
5. **Controllers** keep reconciling desired vs current
6. **kube-proxy** / CNI implement service routing + pod networking

### 15.2 Must-know commands checklist

```bash
# Discover and learn
kubectl api-resources
kubectl explain deployment.spec.template.spec --recursive | less

# Inspect
kubectl get all -n <ns>
kubectl describe <type> <name> -n <ns>
kubectl get <type> <name> -o yaml

# Troubleshoot
kubectl logs <pod> -c <ctr> --previous
kubectl get events -A --sort-by=.lastTimestamp | tail
kubectl exec -it <pod> -- sh
kubectl port-forward pod/<pod> 8080:80

# Manage
kubectl apply -f file.yaml
kubectl delete -f file.yaml
kubectl scale deploy/<name> --replicas=5
kubectl rollout status deploy/<name>
kubectl rollout undo deploy/<name>

# Nodes
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
```

### 15.3 Common failure patterns (and what you check)

- **Pending** → resources, taints/tolerations, nodeSelectors, PVC
- **CrashLoopBackOff** → app error, bad env/config, missing secret, probe killing it
- **ImagePullBackOff** → wrong tag, auth, network/DNS to registry
- **Service no endpoints** → selectors mismatch, pods not Ready
- **DNS issues** → CoreDNS down, network policy, kube-proxy/CNI issues

---

## Appendix A — Going “Full Hard Way” (Optional)

If you want the *true* hard-way experience (manual certificates, kubeconfigs, etcd, apiserver, controller, scheduler, kubelet and networking), do this after you complete everything above:

### A.1 What you’d build manually
- PKI: CA, client/server certs
- kubeconfigs: admin, kubelet, controller-manager, scheduler
- etcd cluster
- control-plane binaries as systemd services
- worker components + CNI

### A.2 Minimum “full hard way” exercises
1. **Generate a CA + apiserver cert** with `openssl`
2. **Run etcd** and verify with `etcdctl`
3. **Run kube-apiserver** and hit `/healthz`
4. **Create a namespace** via API call
5. **Start kubelet** and run a static pod

> Tip: Search for “Kubernetes The Hard Way” (Kelsey Hightower) and follow it when you have time. Use this README first to become productive quickly.

---

## Cleanup

```bash
kubectl delete ns dev || true
kubectl delete ds node-logger || true
kubectl delete deploy web probe-demo bad || true
kubectl delete svc web-svc || true
kubectl delete cm app-config || true
kubectl delete secret db-secret || true
```

To reset the cluster (lab only):

```bash
sudo kubeadm reset -f
sudo rm -rf $HOME/.kube
```

---

## Next Steps (After You Finish This README)

1. Learn **Helm** basics and deploy a chart
2. Install and practice **Ingress Controller** + TLS
3. Learn **NetworkPolicy** (Calico)
4. Practice **multi-namespace RBAC**
5. Practice **resource limits & eviction**
6. Run a **stateful app** (Postgres) using PVC
7. Build CI/CD manifests with **Kustomize**
8. Learn **cluster upgrades** with kubeadm (very real-world)

---

### If you want, tell me:
- Your OS (Ubuntu/CentOS), VM specs, and whether you want **3 nodes** (HA-ish) or **2 nodes**.
- I can generate a **Day-by-Day “hard way” schedule** + checklists + mini incident drills.
