# Kubernetes **EXPERT / Production Engineering** — The Hard Way

> **You’re training for real production**: outages, escalations, upgrades, security incidents, and high‑level interviews.
>
> This README is a **step‑by‑step path** (phases + labs + runbooks). It intentionally includes **manual (“hard way”)** tasks so you internalize how Kubernetes actually works.

---


# Table of Contents

  - [🔥 Outcome (what “expert” means)](#outcome-what-expert-means)
- [1) Mindset & Safety](#1-mindset-safety)
  - [1.1 Production rules (do this every time)](#11-production-rules-do-this-every-time)
  - [1.2 “High-risk” commands (use with explicit intent)](#12-high-risk-commands-use-with-explicit-intent)
- [2) Lab Environment](#2-lab-environment)
  - [2.1 Recommended topology (to practice HA + failures)](#21-recommended-topology-to-practice-ha-failures)
  - [2.2 Required tooling (bastion)](#22-required-tooling-bastion)
  - [2.3 Node OS baseline (ALL nodes)](#23-node-os-baseline-all-nodes)
- [3) Phase 1 — Build the Cluster (Hard Way)](#3-phase-1-build-the-cluster-hard-way)
  - [3.1 Step 1 — PKI (Certificates) by hand](#31-step-1-pki-certificates-by-hand)
    - [3.1.1 Create Cluster CA](#311-create-cluster-ca)
    - [3.1.2 API server cert (SANs matter!)](#312-api-server-cert-sans-matter)
    - [3.1.3 Admin client cert](#313-admin-client-cert)
  - [3.2 Step 2 — kubeconfigs (manual auth wiring)](#32-step-2-kubeconfigs-manual-auth-wiring)
  - [3.3 Step 3 — etcd (quorum, backup/restore)](#33-step-3-etcd-quorum-backuprestore)
    - [3.3.1 Critical etcd checks](#331-critical-etcd-checks)
    - [3.3.2 Snapshot (practice until you can do it in 2 minutes)](#332-snapshot-practice-until-you-can-do-it-in-2-minutes)
  - [3.4 Step 4 — Control Plane essentials](#34-step-4-control-plane-essentials)
    - [3.4.1 API server health endpoints](#341-api-server-health-endpoints)
    - [3.4.2 Leader election (HA signal)](#342-leader-election-ha-signal)
    - [3.4.3 Understand these flags (interview + production)](#343-understand-these-flags-interview-production)
  - [3.5 Step 5 — Workers (runtime + kubelet + CNI)](#35-step-5-workers-runtime-kubelet-cni)
    - [3.5.1 Runtime survival](#351-runtime-survival)
    - [3.5.2 Kubelet survival](#352-kubelet-survival)
    - [3.5.3 Install CNI then verify](#353-install-cni-then-verify)
- [4) Phase 2 — Production Operations](#4-phase-2-production-operations)
  - [4.1 Deployments: safe rollouts & rollback](#41-deployments-safe-rollouts-rollback)
  - [4.2 Node maintenance (cordon/drain)](#42-node-maintenance-cordondrain)
  - [4.3 Verify cluster after change (go/no-go)](#43-verify-cluster-after-change-gono-go)
- [5) Phase 3 — Expert Debugging / Incident Drills](#5-phase-3-expert-debugging-incident-drills)
  - [5.1 Universal triage commands (90% of incidents)](#51-universal-triage-commands-90-of-incidents)
  - [5.2 Debug a node **without SSH** (amazing in production)](#52-debug-a-node-without-ssh-amazing-in-production)
  - [5.3 DNS outage runbook](#53-dns-outage-runbook)
  - [5.4 “Pods Pending” runbook](#54-pods-pending-runbook)
  - [5.5 “CrashLoopBackOff” runbook](#55-crashloopbackoff-runbook)
  - [5.6 “Node NotReady” runbook](#56-node-notready-runbook)
  - [5.7 API server slow / erroring](#57-api-server-slow-erroring)
- [6) Phase 4 — Security & Policy Engineering](#6-phase-4-security-policy-engineering)
  - [6.1 RBAC: your daily bread](#61-rbac-your-daily-bread)
  - [6.2 Pod Security Standards](#62-pod-security-standards)
  - [6.3 Secrets hygiene](#63-secrets-hygiene)
  - [6.4 Audit mindset](#64-audit-mindset)
- [7) Phase 5 — Performance / Scale / Reliability](#7-phase-5-performance-scale-reliability)
  - [7.1 Resource pressure & QoS](#71-resource-pressure-qos)
  - [7.2 Scheduler controls](#72-scheduler-controls)
  - [7.3 Reliability patterns](#73-reliability-patterns)
- [8) Pocket Cheatsheets (Survival Commands)](#8-pocket-cheatsheets-survival-commands)
  - [8.1 Fast cluster snapshot (when pager rings)](#81-fast-cluster-snapshot-when-pager-rings)
  - [8.2 Fast “pod is broken”](#82-fast-pod-is-broken)
  - [8.3 Fast “service is broken”](#83-fast-service-is-broken)
  - [8.4 Fast “node is broken”](#84-fast-node-is-broken)
  - [8.5 Handy kubectl power moves](#85-handy-kubectl-power-moves)
- [9) Interview Prompts (Answer Like SRE)](#9-interview-prompts-answer-like-sre)
- [10) Next-Level Roadmap](#10-next-level-roadmap)
  - [Want a full bundle?](#want-a-full-bundle)



## 🔥 Outcome (what “expert” means)
By the end you should be able to:

- **Build** a Kubernetes cluster (control plane + workers) understanding every major file/flag.
- **Operate** a cluster safely (rollouts, upgrades, capacity, multi‑AZ/HA thinking).
- **Debug** critical incidents quickly using a repeatable triage framework.
- **Explain** internals clearly for interviews: API flow, etcd/quorum, scheduling, CNI, kube-proxy/eBPF, CSI, RBAC/admission.

---

---

# 1) Mindset & Safety

## 1.1 Production rules (do this every time)
```bash
# 0) Verify you are in the right cluster
kubectl config current-context
kubectl config get-contexts

# 1) Start read-only
kubectl get nodes -o wide
kubectl get pods -A -o wide | head
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -30

# 2) When changing: reduce blast radius
kubectl -n <ns> get deploy
kubectl -n <ns> get pods -l app=<name>
```

## 1.2 “High-risk” commands (use with explicit intent)
- `kubectl delete ...`
- `kubectl replace --force ...`
- `kubectl drain --delete-emptydir-data ...`
- `etcdctl snapshot restore ...`
- node-level `iptables -F`, deleting CNI state, restarting control plane services

**Safer alternatives**: `kubectl rollout undo`, scaling down, cordon then drain, applying change to one node first.

---

# 2) Lab Environment

## 2.1 Recommended topology (to practice HA + failures)
- **3 control-plane nodes** (stacked etcd is okay for labs)
- **2 workers**
- optional: LB (HAProxy) in front of API servers

## 2.2 Required tooling (bastion)
```bash
kubectl version --client
crictl --version || true
etcdctl version || true
openssl version
jq --version
```

## 2.3 Node OS baseline (ALL nodes)
```bash
# swap off
swapoff -a
sudo sed -i.bak '/ swap / s/^/#/' /etc/fstab

# kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl
cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

---

# 3) Phase 1 — Build the Cluster (Hard Way)

> **Target**: Understand certificates, kubeconfigs, etcd, API server, scheduler, controller-manager, kubelet, runtime, CNI.
>
> **Success check** at end of Phase 1:
> - `kubectl get nodes` shows all nodes **Ready**
> - `kube-system` pods **Running**
> - CoreDNS resolves service names

## 3.1 Step 1 — PKI (Certificates) by hand

### 3.1.1 Create Cluster CA
```bash
mkdir -p pki && cd pki
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/CN=kubernetes-ca" -out ca.crt
```

### 3.1.2 API server cert (SANs matter!)
Include:
- LB DNS/IP
- each control-plane IP
- service DNS names: `kubernetes.default.svc` etc

```bash
cat <<'EOF' > apiserver.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
# add your LB DNS/IP and CP IPs here
IP.1 = 127.0.0.1
EOF

openssl genrsa -out apiserver.key 4096
openssl req -new -key apiserver.key -subj "/CN=kube-apiserver" -out apiserver.csr
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out apiserver.crt -days 365 -sha256 -extensions v3_req -extfile apiserver.cnf
```

### 3.1.3 Admin client cert
```bash
openssl genrsa -out admin.key 4096
openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out admin.crt -days 365 -sha256
```

> Repeat cert generation for:
> - `kube-controller-manager`
> - `kube-scheduler`
> - `etcd` (server + peer + client)
> - `system:node:<nodeName>` (kubelet) with `O=system:nodes`

---

## 3.2 Step 2 — kubeconfigs (manual auth wiring)
```bash
KUBERNETES_API=https://<LB_OR_CP_IP>:6443

kubectl config set-cluster kubernetes \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=${KUBERNETES_API} \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=admin.crt \
  --client-key=admin.key \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig
```

---

## 3.3 Step 3 — etcd (quorum, backup/restore)

### 3.3.1 Critical etcd checks
```bash
export ETCDCTL_API=3
etcdctl endpoint status --write-out=table
etcdctl endpoint health --write-out=table
etcdctl alarm list
```

### 3.3.2 Snapshot (practice until you can do it in 2 minutes)
```bash
ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd-snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/ca.crt \
  --cert=/etc/kubernetes/pki/etcd-client.crt \
  --key=/etc/kubernetes/pki/etcd-client.key

ETCDCTL_API=3 etcdctl snapshot status /var/backups/etcd-snap.db --write-out=table
```

> **Lab restore drill** (don’t do in production without a plan):
```bash
ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd-snap.db --data-dir /var/lib/etcd-restored
```

---

## 3.4 Step 4 — Control Plane essentials

### 3.4.1 API server health endpoints
```bash
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

### 3.4.2 Leader election (HA signal)
```bash
kubectl -n kube-system get lease | egrep 'kube-controller-manager|kube-scheduler'
```

### 3.4.3 Understand these flags (interview + production)
- `--authorization-mode=Node,RBAC`
- `--enable-admission-plugins=...`
- `--audit-log-path=...`
- `--encryption-provider-config=...`

---

## 3.5 Step 5 — Workers (runtime + kubelet + CNI)

### 3.5.1 Runtime survival
```bash
systemctl status containerd
crictl info
crictl ps -a
```

### 3.5.2 Kubelet survival
```bash
systemctl status kubelet
journalctl -u kubelet -n 200 --no-pager
journalctl -u kubelet -f
```

### 3.5.3 Install CNI then verify
```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
```

---

# 4) Phase 2 — Production Operations

## 4.1 Deployments: safe rollouts & rollback
```bash
kubectl -n <ns> rollout status deploy/<name>
kubectl -n <ns> rollout history deploy/<name>

# rollback
kubectl -n <ns> rollout undo deploy/<name>

# pause/resume
kubectl -n <ns> rollout pause deploy/<name>
kubectl -n <ns> rollout resume deploy/<name>
```

## 4.2 Node maintenance (cordon/drain)
```bash
kubectl cordon <node>

kubectl drain <node> --ignore-daemonsets --grace-period=60 --timeout=10m

kubectl uncordon <node>
```

## 4.3 Verify cluster after change (go/no-go)
```bash
kubectl get nodes
kubectl get pods -A | egrep -i 'CrashLoopBackOff|Error|Pending|ImagePull'
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -30
```

---

# 5) Phase 3 — Expert Debugging / Incident Drills

> **Production debugging = structured.** Use this workflow:
1) Scope: one pod / one node / one namespace / whole cluster
2) Signals: events → logs → metrics
3) Dependencies: DNS, network, storage, API, runtime
4) Recent change: deploy, config, node rotation, certificates, quota

## 5.1 Universal triage commands (90% of incidents)
```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -50

kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --all-containers --tail=200
kubectl -n <ns> logs <pod> --previous --tail=200
```

## 5.2 Debug a node **without SSH** (amazing in production)
> Uses ephemeral debug container on the node and chroots into the host.

```bash
kubectl debug node/<node> -it --image=registry.k8s.io/e2e-test-images/agnhost:2.45 -- \
  chroot /host sh

# inside:
crictl ps -a
journalctl -u kubelet -n 200 --no-pager
ip a
ip route
```

## 5.3 DNS outage runbook
```bash
kubectl -n kube-system get deploy,svc,endpoints kube-dns -o wide
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=200

kubectl run -it --rm dnsutils \
  --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never -- sh -c 'nslookup kubernetes.default && cat /etc/resolv.conf'
```

## 5.4 “Pods Pending” runbook
```bash
kubectl -n <ns> describe pod <pod>
# Look for: Insufficient cpu/memory, taints, affinity, pvc
kubectl describe node <node>
kubectl get quota -A
kubectl get pvc -A
```

## 5.5 “CrashLoopBackOff” runbook
```bash
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --previous --tail=200

# check probes and env
kubectl -n <ns> get pod <pod> -o yaml | sed -n '1,200p'
```

## 5.6 “Node NotReady” runbook
```bash
kubectl describe node <node> | sed -n '/Conditions/,+25p'

# on node (or via kubectl debug node/...)
systemctl status kubelet
journalctl -u kubelet -n 200 --no-pager
systemctl status containerd
journalctl -u containerd -n 200 --no-pager

# pressure
free -m
df -h

dmesg | egrep -i 'oom|killed process' | tail
```

## 5.7 API server slow / erroring
```bash
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/metrics' | head

# check apiserver logs on CP node
journalctl -u kube-apiserver -n 200 --no-pager || true

# etcd health
ETCDCTL_API=3 etcdctl endpoint health --write-out=table
ETCDCTL_API=3 etcdctl endpoint status --write-out=table
```

---

# 6) Phase 4 — Security & Policy Engineering

## 6.1 RBAC: your daily bread
```bash
kubectl auth can-i list pods -A
kubectl auth can-i create pods -n <ns> --as <user>

kubectl get role,rolebinding -n <ns>
kubectl get clusterrole,clusterrolebinding
```

## 6.2 Pod Security Standards
```bash
kubectl label ns <ns> pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label ns <ns> pod-security.kubernetes.io/audit=restricted --overwrite
kubectl label ns <ns> pod-security.kubernetes.io/warn=restricted --overwrite
```

## 6.3 Secrets hygiene
```bash
kubectl get secrets -A
kubectl -n <ns> describe secret <name>
```

## 6.4 Audit mindset
- Who did what? When? Which API?
- Ensure audit logs are shipped off-node.

---

# 7) Phase 5 — Performance / Scale / Reliability

## 7.1 Resource pressure & QoS
```bash
kubectl top nodes
kubectl top pods -A --containers
kubectl describe pod -n <ns> <pod> | egrep -i 'QoS|Requests|Limits'
```

## 7.2 Scheduler controls
- Taints/Tolerations for dedicated nodes
- Affinity/Anti-affinity for HA

```bash
kubectl describe node <node> | sed -n '/Taints/,+5p'

kubectl taint nodes <node> dedicated=infra:NoSchedule
kubectl taint nodes <node> dedicated=infra:NoSchedule-
```

## 7.3 Reliability patterns
- PodDisruptionBudgets
- topologySpreadConstraints
- multi-zone nodes + anti-affinity

---

# 8) Pocket Cheatsheets (Survival Commands)

## 8.1 Fast cluster snapshot (when pager rings)
```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -50
kubectl get --raw='/readyz?verbose'
```

## 8.2 Fast “pod is broken”
```bash
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --all-containers --tail=200
kubectl -n <ns> logs <pod> --previous --tail=200
```

## 8.3 Fast “service is broken”
```bash
kubectl -n <ns> get svc,endpoints,endpointslices -l app=<name> -o wide
kubectl -n <ns> get ingress
```

## 8.4 Fast “node is broken”
```bash
kubectl describe node <node> | sed -n '/Conditions/,+25p'

kubectl debug node/<node> -it --image=registry.k8s.io/e2e-test-images/agnhost:2.45 -- chroot /host sh
```

## 8.5 Handy kubectl power moves
```bash
# watch
kubectl get pods -A -w

# filter by field
kubectl get pods -A --field-selector=status.phase!=Running

# show only failures
kubectl get pods -A | egrep -i 'CrashLoopBackOff|Error|Pending|ImagePull'

# explain any field quickly
kubectl explain deploy.spec.template.spec --recursive | less

# diff before apply
kubectl diff -f <file.yaml>
```

---

# 9) Interview Prompts (Answer Like SRE)
Practice answering these out loud:

1) What happens from `kubectl apply` to a running pod?
2) How does a Service route to a Pod? (iptables/ipvs/eBPF)
3) etcd quorum and why odd members?
4) Debug CrashLoopBackOff (exact commands)
5) Readiness vs liveness vs startup probes
6) Safe node maintenance (cordon/drain/PDB)
7) How to do disaster recovery for Kubernetes
8) How to enforce security (RBAC, admission, pod security)

---

# 10) Next-Level Roadmap
Once this README becomes comfortable:
- Write a controller/operator (CRD + controller-runtime)
- Admission webhooks + policy (Kyverno/Gatekeeper)
- eBPF networking deep dive (Cilium)
- Cluster autoscaling + capacity modeling
- Supply chain security (SBOM, signing)
- Multi-cluster / GitOps / progressive delivery

---

## Want a full bundle?
I can generate a complete repo structure:
- `RUNBOOKS.md` (more detailed incident playbooks)
- `LABS/` with manifests + break/fix steps
- `INTERVIEW_QA.md` (150+ Q/A)
- PDF export

Happy hard-learning. 💪
