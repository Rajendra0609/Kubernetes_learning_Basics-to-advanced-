# Advanced Kubernetes — The Hard Way (Step‑by‑Step, Real‑World Survival + Interview)

> **Goal:** Build a *strong* Kubernetes foundation by doing advanced things manually (the “hard way”), then practice **production-grade troubleshooting** and **incident survival commands**.
>
> **Who this is for:** DevOps/SRE/Platform engineers who already know basics (Pods/Deployments/Services) and want **deep control-plane understanding + real cluster debugging**.

---


# Table of Contents

  - [✅ What you will be able to do after this](#what-you-will-be-able-to-do-after-this)
  - [🧰 Prerequisites](#prerequisites)
    - [Skills](#skills)
    - [Recommended lab environment (choose one)](#recommended-lab-environment-choose-one)
    - [Tools you should have](#tools-you-should-have)
- [🧭 Learning Path (Modules)](#learning-path-modules)
  - [Module 0 — Baseline: Observe Like an SRE (Must Know)](#module-0-baseline-observe-like-an-sre-must-know)
    - [0.1 Context, namespaces, and quick health checks](#01-context-namespaces-and-quick-health-checks)
    - [0.2 The 5 most used real-time triage commands](#02-the-5-most-used-real-time-triage-commands)
    - [0.3 JSONPath / filtering (interview + real work)](#03-jsonpath-filtering-interview-real-work)
  - [Module 1 — Build / Understand the Control Plane (Hard Way Concepts)](#module-1-build-understand-the-control-plane-hard-way-concepts)
    - [1.1 Map components and their ports](#11-map-components-and-their-ports)
    - [1.2 Certificates — inspect and debug expiry](#12-certificates-inspect-and-debug-expiry)
    - [1.3 etcd health + snapshot (CRITICAL)](#13-etcd-health-snapshot-critical)
    - [Exercises](#exercises)
  - [Module 2 — Scheduler & Controller Behavior (Advanced Scheduling)](#module-2-scheduler-controller-behavior-advanced-scheduling)
    - [2.1 Read scheduling decisions](#21-read-scheduling-decisions)
    - [2.2 Pod placement controls](#22-pod-placement-controls)
    - [2.3 PriorityClasses (preemption)](#23-priorityclasses-preemption)
  - [Module 3 — Networking: CNI, kube-proxy, DNS (Where most outages happen)](#module-3-networking-cni-kube-proxy-dns-where-most-outages-happen)
    - [3.1 Understand the packet path](#31-understand-the-packet-path)
    - [3.2 Service debugging checklist](#32-service-debugging-checklist)
    - [3.3 DNS debugging (CoreDNS)](#33-dns-debugging-coredns)
    - [3.4 Node-level networking survival commands](#34-node-level-networking-survival-commands)
  - [Module 4 — Storage: Stateful survival](#module-4-storage-stateful-survival)
    - [4.1 PVC stuck Pending](#41-pvc-stuck-pending)
    - [4.2 StatefulSet pod stuck Terminating](#42-statefulset-pod-stuck-terminating)
  - [Module 5 — Runtime & Kubelet: CRI, logs, and node failures](#module-5-runtime-kubelet-cri-logs-and-node-failures)
    - [5.1 Kubelet and container runtime logs](#51-kubelet-and-container-runtime-logs)
    - [5.2 Common pod failures (fast fixes)](#52-common-pod-failures-fast-fixes)
  - [Module 6 — Security Hardening: RBAC, Pod Security, Secrets](#module-6-security-hardening-rbac-pod-security-secrets)
    - [6.1 RBAC: debug “Forbidden” like a pro](#61-rbac-debug-forbidden-like-a-pro)
    - [6.2 Pod Security (baseline/restricted)](#62-pod-security-baselinerestricted)
    - [6.3 Secrets quick checks](#63-secrets-quick-checks)
  - [Module 7 — Admission & Policies (Advanced “Platform Engineering”)](#module-7-admission-policies-advanced-platform-engineering)
    - [7.1 Understand admission flow](#71-understand-admission-flow)
    - [7.2 Quick policy testing pattern](#72-quick-policy-testing-pattern)
  - [Module 8 — Upgrades, Rollbacks, and Safe Change Management](#module-8-upgrades-rollbacks-and-safe-change-management)
    - [8.1 Safe rollout patterns](#81-safe-rollout-patterns)
    - [8.2 Node maintenance](#82-node-maintenance)
- [🚑 Production Incident Playbooks (Your Survival Kit)](#production-incident-playbooks-your-survival-kit)
  - [Playbook A — “Service is DOWN” (fastest path)](#playbook-a-service-is-down-fastest-path)
  - [Playbook B — “Node NotReady / Pressure”](#playbook-b-node-notready-pressure)
  - [Playbook C — “Stuck Terminating” (pods/namespaces)](#playbook-c-stuck-terminating-podsnamespaces)
  - [Playbook D — “Control plane down”](#playbook-d-control-plane-down)
- [🧪 Capstone Labs (Do these to become “Real-World Ready”)](#capstone-labs-do-these-to-become-real-world-ready)
    - [Lab 1 — etcd Disaster Recovery (Snapshot + Restore)](#lab-1-etcd-disaster-recovery-snapshot-restore)
    - [Lab 2 — DNS Outage Simulation](#lab-2-dns-outage-simulation)
    - [Lab 3 — NetworkPolicy Lockdown](#lab-3-networkpolicy-lockdown)
    - [Lab 4 — Scheduler Constraints](#lab-4-scheduler-constraints)
    - [Lab 5 — Production Rollout](#lab-5-production-rollout)
    - [Lab 6 — Node Failure](#lab-6-node-failure)
- [🎯 Interview Drill (High-Value Questions)](#interview-drill-high-value-questions)
- [🧷 Command Cheat Sheet (Copy/Paste)](#command-cheat-sheet-copypaste)
    - [Find what changed recently](#find-what-changed-recently)
    - [Find high restart pods](#find-high-restart-pods)
    - [Quick debug pod (network tools)](#quick-debug-pod-network-tools)
    - [Ephemeral debug container (when allowed)](#ephemeral-debug-container-when-allowed)
    - [Watch resources live](#watch-resources-live)
- [✅ Next Steps (If you want me to generate more files)](#next-steps-if-you-want-me-to-generate-more-files)
  - [License / Notes](#license-notes)



## ✅ What you will be able to do after this

- Explain and troubleshoot **control plane** components (apiserver / scheduler / controller-manager / etcd)
- Debug **kubelet**, **container runtime**, **CNI**, **CoreDNS**, **kube-proxy**, **Ingress** problems
- Perform **etcd snapshot/restore**, node drain/cordon, emergency isolation, and safe rollbacks
- Write/understand **RBAC**, **Pod Security**, **NetworkPolicy**, and admission controls
- Survive common incidents: **CrashLoopBackOff**, **OOMKilled**, **ImagePullBackOff**, DNS outage, node pressure, stuck terminating pods, broken routes, etc.

---

## 🧰 Prerequisites

### Skills
- Comfortable with Linux shell, networking basics (ports, routes), and YAML
- Kubernetes fundamentals (kubectl, manifests)

### Recommended lab environment (choose one)

**Option A (Best for “Hard Way”):** 3–4 Linux VMs (Ubuntu 22.04 recommended)
- 1× control plane node, 2× worker nodes (add 2nd control plane later for HA)

**Option B (Quick local):** kind (for most labs) + one VM for node-level debugging

### Tools you should have
- `kubectl`, `etcdctl`, `crictl`, `jq`, `curl`, `openssl`
- `tcpdump`, `iproute2`, `conntrack`, `iptables`/`nft`

---

# 🧭 Learning Path (Modules)

> **How to use this README:**
> - Do modules in order
> - After each module, finish the **Checkpoint** and **Exercises**
> - Keep a notes file: "symptom → checks → root cause → fix"

---

## Module 0 — Baseline: Observe Like an SRE (Must Know)

### 0.1 Context, namespaces, and quick health checks
```bash
kubectl config get-contexts
kubectl config use-context <ctx>

kubectl get nodes -owide
kubectl get pods -A -owide
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 50
```

### 0.2 The 5 most used real-time triage commands
```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --all-containers --tail=200
kubectl logs <pod> -n <ns> -c <container> --previous
kubectl get endpoints -n <ns> <svc> -o wide
kubectl top nodes && kubectl top pods -A --containers
```

### 0.3 JSONPath / filtering (interview + real work)
```bash
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.nodeName}{"\n"}'
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.phase}{"\n"}{end}'

# who is restarting?
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses!=null) | .metadata.namespace+"/"+.metadata.name+" " + ( [.status.containerStatuses[].restartCount] | max | tostring )'
```

✅ **Checkpoint:** You can quickly locate failing components and extract exact fields with JSONPath/JQ.

---

## Module 1 — Build / Understand the Control Plane (Hard Way Concepts)

> You can do this on a kubeadm cluster too, but the “hard way” mindset is: **certs, kubeconfigs, static pods, systemd, etcd**.

### 1.1 Map components and their ports
- **kube-apiserver:** 6443
- **etcd:** 2379/2380
- **kube-scheduler:** 10259
- **kube-controller-manager:** 10257
- **kubelet:** 10250

```bash
# where are control plane manifests? (kubeadm)
ls -l /etc/kubernetes/manifests

# check health endpoints (control plane)
kubectl get --raw '/readyz?verbose'
kubectl get --raw '/livez?verbose'
kubectl get --raw '/healthz'
```

### 1.2 Certificates — inspect and debug expiry
```bash
# list certs (kubeadm default)
ls -l /etc/kubernetes/pki

# check expiry
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates -subject
openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -subject -issuer
```

### 1.3 etcd health + snapshot (CRITICAL)
> **Always test restore in a safe environment.**

```bash
# kubeadm typically runs etcd as a static pod; etcdctl needs TLS flags.
# Replace paths if your cluster differs.
export ETCDCTL_API=3

etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table

etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/backups/etcd-$(date +%F-%H%M).db
```

✅ **Checkpoint:** You can explain each control plane component and validate etcd is healthy.

### Exercises
- Break DNS by scaling CoreDNS to 0 and restore
- Expire a non-critical cert in a test env and recover (or rotate with kubeadm)

---

## Module 2 — Scheduler & Controller Behavior (Advanced Scheduling)

### 2.1 Read scheduling decisions
```bash
kubectl describe pod <pod> -n <ns> | sed -n '/Events/,$p'
kubectl get events -n <ns> --field-selector involvedObject.name=<pod> --sort-by=.metadata.creationTimestamp
```

### 2.2 Pod placement controls
- NodeSelector, NodeAffinity, Taints/Tolerations, TopologySpreadConstraints

```bash
kubectl get nodes --show-labels
kubectl taint nodes <node> dedicated=prod:NoSchedule
kubectl describe node <node> | sed -n '/Taints/,$p'
```

### 2.3 PriorityClasses (preemption)
```bash
kubectl get priorityclass
```

✅ **Checkpoint:** You can force/avoid scheduling and interpret why scheduling failed.

---

## Module 3 — Networking: CNI, kube-proxy, DNS (Where most outages happen)

### 3.1 Understand the packet path
- Pod → veth → bridge (or eBPF) → node routing → service VIP (kube-proxy/eBPF) → destination

### 3.2 Service debugging checklist
```bash
# 1) endpoints exist?
kubectl get ep -n <ns> <svc> -o wide

# 2) service ports?
kubectl describe svc -n <ns> <svc>

# 3) can we reach from inside?
kubectl run -it --rm netshoot --image=nicolaka/netshoot --restart=Never -- bash
# inside:
# curl -sv http://<svc>.<ns>.svc.cluster.local:<port>
```

### 3.3 DNS debugging (CoreDNS)
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -owide
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=200
kubectl exec -it -n kube-system deploy/coredns -- sh

# from any pod
kubectl exec -it <pod> -n <ns> -- nslookup kubernetes.default
kubectl exec -it <pod> -n <ns> -- cat /etc/resolv.conf
```

### 3.4 Node-level networking survival commands
```bash
# routes, interfaces
ip a
ip r

# conntrack saturation
conntrack -S | head

# traffic capture
tcpdump -i any port 53 -nn

# iptables/nft rules (kube-proxy)
iptables -t nat -S | head -n 50
nft list ruleset | head -n 80
```

✅ **Checkpoint:** You can prove if failure is DNS, Service endpoints, NetworkPolicy, or node routing.

---

## Module 4 — Storage: Stateful survival

### 4.1 PVC stuck Pending
```bash
kubectl get pvc -A
kubectl describe pvc -n <ns> <pvc>
kubectl get sc -o wide
kubectl get pv -o wide
```

### 4.2 StatefulSet pod stuck Terminating
```bash
kubectl get pod -n <ns> <pod> -o yaml | sed -n '/finalizers/,+10p'

# emergency (use carefully):
kubectl delete pod -n <ns> <pod> --grace-period=0 --force
```

✅ **Checkpoint:** You can find whether it’s storage class, provisioner, attach/detach, or filesystem.

---

## Module 5 — Runtime & Kubelet: CRI, logs, and node failures

### 5.1 Kubelet and container runtime logs
```bash
# kubelet logs
journalctl -u kubelet -f

# container runtime (containerd example)
journalctl -u containerd -f

# CRI view
crictl info
crictl ps -a
crictl logs <container-id>
crictl inspect <container-id> | head
```

### 5.2 Common pod failures (fast fixes)

**CrashLoopBackOff**
```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous --tail=200
```

**ImagePullBackOff**
```bash
kubectl describe pod <pod> -n <ns> | sed -n '/Events/,$p'
crictl pull <image>
```

**OOMKilled**
```bash
kubectl describe pod <pod> -n <ns> | grep -i -E 'oom|killed' -n
kubectl top pod -n <ns> <pod> --containers

dmesg | tail -n 200 | grep -i -E 'killed process|oom'
```

✅ **Checkpoint:** You can distinguish app issues vs node/runtime issues quickly.

---

## Module 6 — Security Hardening: RBAC, Pod Security, Secrets

### 6.1 RBAC: debug “Forbidden” like a pro
```bash
kubectl auth can-i get pods -n <ns> --as <user>
kubectl auth can-i '*' '*' -n <ns> --as <user>

kubectl get role,rolebinding -n <ns>
kubectl get clusterrole,clusterrolebinding | head
```

### 6.2 Pod Security (baseline/restricted)
- Run as non-root
- Drop capabilities
- Read-only root filesystem

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

### 6.3 Secrets quick checks
```bash
kubectl get secrets -n <ns>
# show keys only (avoid printing values in shared terminals)
kubectl get secret -n <ns> <name> -o jsonpath='{.data}' | jq 'keys'
```

✅ **Checkpoint:** You can resolve RBAC errors and enforce safer pod defaults.

---

## Module 7 — Admission & Policies (Advanced “Platform Engineering”)

### 7.1 Understand admission flow
- ValidatingAdmissionPolicy / webhooks
- Mutating webhooks (inject sidecars, defaults)

```bash
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

kubectl get --raw /api/v1 | head
```

### 7.2 Quick policy testing pattern
- Make a minimal manifest
- Apply
- Read rejection message
- Locate webhook/policy and fix

✅ **Checkpoint:** You can identify which admission controller blocked a request.

---

## Module 8 — Upgrades, Rollbacks, and Safe Change Management

### 8.1 Safe rollout patterns
```bash
kubectl rollout status deploy/<name> -n <ns>
kubectl rollout history deploy/<name> -n <ns>

# quick rollback
kubectl rollout undo deploy/<name> -n <ns>

# pause/resume for controlled changes
kubectl rollout pause deploy/<name> -n <ns>
kubectl rollout resume deploy/<name> -n <ns>
```

### 8.2 Node maintenance
```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-local-data --force
kubectl uncordon <node>
```

✅ **Checkpoint:** You can perform maintenance without causing cascading outages.

---

# 🚑 Production Incident Playbooks (Your Survival Kit)

## Playbook A — “Service is DOWN” (fastest path)

1) **Is the API healthy?**
```bash
kubectl get --raw '/readyz?verbose'
```

2) **Which namespace/app?**
```bash
kubectl get pods -A -owide | egrep -i 'crash|error|pending|backoff|init'
```

3) **Service endpoints** (most common root cause)
```bash
kubectl get svc -n <ns>
kubectl get ep -n <ns> <svc> -o wide
```

4) **Pod logs + events**
```bash
kubectl describe pod <pod> -n <ns> | sed -n '/Events/,$p'
kubectl logs <pod> -n <ns> --all-containers --tail=200
```

5) **DNS check**
```bash
kubectl exec -it <pod> -n <ns> -- nslookup <svc>.<ns>.svc.cluster.local
```

6) **NetworkPolicy check**
```bash
kubectl get netpol -n <ns>
```

---

## Playbook B — “Node NotReady / Pressure”

```bash
kubectl describe node <node> | sed -n '/Conditions/,+30p'

# quick node resource usage
kubectl top node <node>

# kubelet + runtime logs
journalctl -u kubelet -n 200 --no-pager
journalctl -u containerd -n 200 --no-pager

# disk pressure
df -h
sudo du -sh /var/lib/containerd/* 2>/dev/null | sort -h | tail
```

Fix patterns:
- DiskPressure → clean images/logs, increase disk, tune eviction
- MemoryPressure → lower limits/requests, scale, fix leak

---

## Playbook C — “Stuck Terminating” (pods/namespaces)

```bash
kubectl get pod -n <ns> <pod> -o yaml | sed -n '/finalizers/,+15p'

# emergency only
kubectl delete pod -n <ns> <pod> --grace-period=0 --force
```

---

## Playbook D — “Control plane down”

On control-plane node:
```bash
# kubeadm static pods
ls -l /etc/kubernetes/manifests

# check kubelet
systemctl status kubelet
journalctl -u kubelet -n 200 --no-pager

# container runtime
systemctl status containerd
journalctl -u containerd -n 200 --no-pager

# etcd health (TLS flags)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

---

# 🧪 Capstone Labs (Do these to become “Real-World Ready”)

### Lab 1 — etcd Disaster Recovery (Snapshot + Restore)
- Take snapshot
- Stop apiserver, restore etcd, verify cluster state

### Lab 2 — DNS Outage Simulation
- Break CoreDNS
- Identify impact and recovery steps

### Lab 3 — NetworkPolicy Lockdown
- Default deny
- Allow only required paths

### Lab 4 — Scheduler Constraints
- Taints/tolerations, affinity, topology spread

### Lab 5 — Production Rollout
- Canary deployment, quick rollback, pause/resume

### Lab 6 — Node Failure
- Drain node, reschedule workloads, validate stateful recovery

---

# 🎯 Interview Drill (High-Value Questions)

Practice answering these with diagrams + commands:

1) Explain the request flow: **kubectl → apiserver → etcd → controllers → scheduler → kubelet**
2) What happens when you create a Service? Where is it programmed?
3) DNS resolution path inside a pod
4) Why pods can talk across nodes (CNI) and how it can fail
5) CrashLoopBackOff vs ImagePullBackOff vs Pending — root causes and commands
6) RBAC: Role vs ClusterRole; RoleBinding vs ClusterRoleBinding
7) etcd failure modes and recovery
8) RollingUpdate strategies, readiness gates, and safe rollouts

---

# 🧷 Command Cheat Sheet (Copy/Paste)

### Find what changed recently
```bash
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 80
kubectl rollout history deploy/<name> -n <ns>
```

### Find high restart pods
```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses!=null) | (.metadata.namespace+"/"+.metadata.name) as $p | [.status.containerStatuses[].restartCount] | max as $r | select($r>0) | $p+" restarts="+($r|tostring)'
```

### Quick debug pod (network tools)
```bash
kubectl run -it --rm netshoot --image=nicolaka/netshoot --restart=Never -- bash
```

### Ephemeral debug container (when allowed)
```bash
kubectl debug -it pod/<pod> -n <ns> --image=nicolaka/netshoot --target=<container>
```

### Watch resources live
```bash
watch -n 1 'kubectl get pods -A -owide'
watch -n 1 'kubectl top pods -A --containers | head -n 30'
```

---

# ✅ Next Steps (If you want me to generate more files)

I can generate:
- **30‑Day Advanced Kubernetes Plan (labs + tasks per day)**
- **K8s Incident Runbooks (PDF)**
- **Interview Q&A workbook**
- **Cheat sheet** (kubectl / Linux / networking)

---

## License / Notes
Use this in your own lab environment first. Avoid printing secret values in shared terminals.
