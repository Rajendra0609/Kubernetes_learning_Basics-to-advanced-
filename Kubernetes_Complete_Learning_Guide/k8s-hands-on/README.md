# Kubernetes Hands-On: Complete Learning Guide
> Basics → Production-Ready | Updated & Augmented Edition

---

## 📁 Folder Structure

```
k8s-hands-on/
├── 00-MISSING-ADDITIONS/        # Probes, lifecycle hooks, init containers
├── 01-cluster-setup/            # ★ NEW: Namespaces, quotas, LimitRanges, health scripts
├── 02-core-objects/             # Pods, Deployments (multi-container, probes)
├── 03-workload-management/      # StatefulSets, DaemonSets, Jobs, CronJobs, Blue-Green, Canary
├── 04-services-networking/      # Services, NetworkPolicies, Ingress ★ ENHANCED
├── 05-config-secrets/           # ConfigMaps, Secrets ★ NEW: Sealed Secrets, External Secrets, Vault
├── 06-storage/                  # ★ NEW: StorageClasses, PVs, PVCs, VolumeSnapshots
├── 07-rbac-security/            # RBAC ★ NEW: Pod Security Standards, OPA Gatekeeper
├── 08-helm/                     # ★ NEW: Full Helm chart with templates, env-specific values
├── 09-autoscaling/              # HPA, VPA ★ NEW: KEDA event-driven autoscaling
├── 10-monitoring/               # Prometheus rules ★ NEW: kube-prometheus-stack, Alertmanager
├── 11-logging/                  # ★ NEW: EFK stack, Loki + Promtail
├── 12-production-scenarios/     # Full-stack app, deployment scripts
├── 13-scheduling/               # Affinity, taints, PDBs, priorities, topology spread
├── 14-crd-operators/            # ★ NEW: CRDs, Operator pattern (kopf), RBAC
├── 15-gitops-cicd/              # ★ NEW: ArgoCD, GitHub Actions pipeline with Trivy scanning
├── 16-service-mesh/             # ★ NEW: Istio VirtualService, mTLS, circuit breakers
├── 17-multitenancy/             # ★ NEW: Namespace isolation, team RBAC, NetworkPolicies
├── 18-disaster-recovery/        # ★ NEW: Velero backup/restore, etcd snapshot scripts
└── 19-capstone-solutions/       # ★ NEW: Full solutions to all capstone projects
    ├── cluster-health/          # Production-grade cluster health checker
    └── ecommerce-app/           # Full e-commerce stack (DB + API + Frontend + Ingress)
```

---

## 🗺️ Learning Path

### Phase 1 — Core Concepts (Days 1–3)
| Section | Key Files | Concepts |
|---------|-----------|----------|
| 01 | `namespaces.yaml` | Namespaces, ResourceQuota, LimitRange |
| 02 | `webapp-deployment.yaml` | Deployment, ReplicaSet, rolling updates |
| 02 | `multi-container-pod.yaml` | Sidecar, ambassador, adapter patterns |
| 00 | `probes-complete.yaml` | Liveness, Readiness, Startup, Exec, gRPC probes |
| 00 | `lifecycle-hooks.yaml` | postStart, preStop, graceful shutdown |
| 05 | `configmap.yaml`, `secret.yaml` | Config injection, secret volumes |

### Phase 2 — Workloads & Networking (Days 4–6)
| Section | Key Files | Concepts |
|---------|-----------|----------|
| 03 | `mongodb-statefulset.yaml` | StatefulSets, headless services, ordered startup |
| 03 | `node-exporter-daemonset.yaml` | DaemonSets, node-level agents |
| 03 | `db-backup-cronjob.yaml` | CronJobs, Jobs, parallelism |
| 03 | `blue-green.yaml`, `canary.yaml` | Deployment strategies |
| 04 | `all-services.yaml` | ClusterIP, NodePort, LoadBalancer, ExternalName |
| 04 | `ingress-advanced.yaml` | TLS, cert-manager, rate limiting, CORS |
| 04 | `default-deny-all.yaml` | NetworkPolicy zero-trust baseline |
| 06 | `storage-classes.yaml` | Dynamic provisioning, RWX, snapshots |

### Phase 3 — Security & RBAC (Day 7)
| Section | Key Files | Concepts |
|---------|-----------|----------|
| 07 | `rbac.yaml` | Role, RoleBinding, ClusterRole, ClusterRoleBinding |
| 07 | `secure-pod.yaml` | SecurityContext, non-root, read-only fs |
| 07 | `pod-security-standards.yaml` | PSS restricted profile, OPA Gatekeeper |
| 05 | `sealed-secret-example.yaml` | Sealed Secrets, External Secrets Operator, Vault |

### Phase 4 — Advanced Operations (Days 8–10)
| Section | Key Files | Concepts |
|---------|-----------|----------|
| 08 | `myapp/` (full Helm chart) | Chart.yaml, values, templates, _helpers, multi-env |
| 09 | `hpa.yaml`, `vpa.yaml`, `keda-scaledobject.yaml` | HPA, VPA, KEDA (SQS/Kafka/Prometheus/Cron) |
| 10 | `kube-prometheus-stack.yaml` | ServiceMonitor, PodMonitor, Alertmanager routes |
| 11 | `efk-stack.yaml`, `loki-promtail.yaml` | EFK, Loki, log parsing, LogQL queries |
| 13 | `node-affinity.yaml`, `topology-spread.yaml` | Scheduling deep-dive |
| 13 | `pdb-examples.yaml` | PodDisruptionBudgets for HA |

### Phase 5 — Platform Engineering (Days 11–14)
| Section | Key Files | Concepts |
|---------|-----------|----------|
| 14 | `crd-example.yaml`, `operator-controller.py` | CRDs, Operator pattern, kopf framework |
| 15 | `argocd-app.yaml` | GitOps, ArgoCD App + AppProject, Image Updater |
| 15 | `github-actions-pipeline.yaml` | CI/CD: test → build → scan → deploy |
| 16 | `istio-basics.yaml` | Traffic splitting, mTLS, circuit breaker, chaos |
| 17 | `namespace-isolation.yaml` | Multi-tenancy patterns |
| 18 | `backup-velero.yaml`, `etcd-backup.sh` | Backup, DR, etcd snapshots |

---

## ⚡ Quick Reference Commands

### Cluster Inspection
```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl get pods -A --field-selector=status.phase!=Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
kubectl api-resources --verbs=list --namespaced -o name
```

### Debugging
```bash
# Why is pod not starting?
kubectl describe pod <pod-name> -n <ns>
kubectl logs <pod-name> -n <ns> --previous   # logs from crashed container
kubectl logs <pod-name> -n <ns> -c <container-name>

# Exec into running pod
kubectl exec -it <pod-name> -n <ns> -- /bin/sh

# Run temporary debug pod (netshoot has all network tools)
kubectl run tmp-debug --image=nicolaka/netshoot -it --rm -n <ns>

# Check RBAC permissions
kubectl auth can-i list pods --as=system:serviceaccount:production:webapp-sa
kubectl auth can-i --list --as=developer-alice

# Decode a secret
kubectl get secret <name> -n <ns> -o jsonpath='{.data.password}' | base64 -d
```

### Helm
```bash
helm install myapp ./08-helm/myapp -n production -f 08-helm/values-prod.yaml
helm upgrade myapp ./08-helm/myapp -n production -f 08-helm/values-prod.yaml --atomic
helm rollback myapp 1 -n production        # rollback to revision 1
helm history myapp -n production
helm template myapp ./08-helm/myapp -f 08-helm/values-prod.yaml  # dry-run render
```

### ArgoCD
```bash
argocd app sync myapp-production
argocd app history myapp-production
argocd app rollback myapp-production 3
argocd app diff myapp-production           # what would change?
```

### Velero Backup/Restore
```bash
velero backup create manual-backup --include-namespaces production
velero backup describe manual-backup --details
velero restore create --from-backup manual-backup
velero restore describe <restore-name>
```

---

## 🔐 Security Checklist (Production Readiness)

- [ ] All pods run as non-root (`runAsNonRoot: true`)
- [ ] All pods have `readOnlyRootFilesystem: true`
- [ ] All pods have `allowPrivilegeEscalation: false`
- [ ] All pods have `capabilities.drop: [ALL]`
- [ ] Pod Security Standards enforced (`restricted` profile) on production namespace
- [ ] No hardcoded secrets — use Sealed Secrets or External Secrets Operator
- [ ] ServiceAccounts use IRSA/Workload Identity (no static AWS/GCP keys)
- [ ] NetworkPolicy default-deny applied to all production namespaces
- [ ] RBAC: least-privilege — no `cluster-admin` for regular workloads
- [ ] Resource requests/limits set on ALL containers (prevents noisy neighbour)
- [ ] ImagePullPolicy: Always in production (ensure latest digest)
- [ ] Container images scanned (Trivy in CI pipeline)
- [ ] PodDisruptionBudgets defined for all critical services
- [ ] HPA with `minReplicas >= 2` for zero-downtime deployments
- [ ] Liveness + Readiness + Startup probes on all containers
- [ ] `terminationGracePeriodSeconds` tuned to match app shutdown time
- [ ] etcd encrypted at rest
- [ ] Audit logging enabled on API server
- [ ] Velero scheduled backups running and tested

---

## 🏆 Capstone Projects Quick Index

| # | Project | Solution File | Skills |
|---|---------|--------------|--------|
| 1 | Cluster Health Dashboard | `19-capstone-solutions/cluster-health/` | bash, kubectl, debugging |
| 2 | Multi-Tier Pod Design | `02-core-objects/multi-container-pod.yaml` | Init containers, sidecars, probes |
| 3 | Canary Release Pipeline | `03-workload-management/blue-green.yaml` + `canary.yaml` | Deployment strategies |
| 4 | Stateful DB with Backups | `03-workload-management/mongodb-statefulset.yaml` | StatefulSets, PVCs, CronJobs |
| 5 | Production RBAC Setup | `07-rbac-security/rbac.yaml` | Roles, ClusterRoles, ServiceAccounts |
| 6 | Helm Chart Authoring | `08-helm/myapp/` | Helm, Sprig templating, multi-env |
| 7 | Event-Driven Autoscaling | `09-autoscaling/keda-scaledobject.yaml` | KEDA, SQS, Kafka, Prometheus |
| 8 | Full Monitoring Stack | `10-monitoring/` | Prometheus, Grafana, Alertmanager |
| 9 | Log Aggregation | `11-logging/` | EFK, Loki, Promtail, LogQL |
| 10 | GitOps Pipeline | `15-gitops-cicd/` | ArgoCD, GitHub Actions, Trivy |
| 11 | Service Mesh | `16-service-mesh/istio-basics.yaml` | Istio, mTLS, circuit breaker |
| 12 | Full E-Commerce Stack | `19-capstone-solutions/ecommerce-app/` | All concepts combined |

---

## 📚 Further Reading

- [Kubernetes Official Docs](https://kubernetes.io/docs/)
- [CNCF Landscape](https://landscape.cncf.io/)
- [Kubernetes Failure Stories](https://k8s.af/) — learn from real outages
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Istio Docs](https://istio.io/latest/docs/)
- [KEDA Docs](https://keda.sh/docs/)
- [Velero Docs](https://velero.io/docs/)
