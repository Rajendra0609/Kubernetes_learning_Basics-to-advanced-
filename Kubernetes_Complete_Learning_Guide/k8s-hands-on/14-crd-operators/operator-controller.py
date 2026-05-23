#!/usr/bin/env python3
"""
WebApp Operator — Kubernetes Controller using kopf
==================================================
This operator watches WebApp CRs and reconciles:
  Deployment, Service, and optionally Ingress.

Install kopf: pip install kopf kubernetes

Run locally:  kopf run operator-controller.py --namespace=production
Run in K8s:   Build as Docker image and deploy as Deployment with RBAC.

Pattern: Reconciliation Loop
  - On CREATE/UPDATE: ensure Deployment + Service match spec
  - On DELETE:        clean up owned resources via ownerReferences
"""
import kopf
import kubernetes
import yaml
import logging

logger = logging.getLogger(__name__)


def make_deployment(name: str, namespace: str, spec: dict, uid: str) -> dict:
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": name,
            "namespace": namespace,
            "ownerReferences": [{   # Garbage-collected when WebApp is deleted
                "apiVersion": "apps.example.com/v1alpha1",
                "kind": "WebApp",
                "name": name,
                "uid": uid,
                "blockOwnerDeletion": True,
                "controller": True,
            }],
            "labels": {"app": name, "managed-by": "webapp-operator"},
        },
        "spec": {
            "replicas": spec.get("replicas", 2),
            "selector": {"matchLabels": {"app": name}},
            "template": {
                "metadata": {"labels": {"app": name}},
                "spec": {
                    "containers": [{
                        "name": "app",
                        "image": spec["image"],
                        "ports": [{"containerPort": spec.get("port", 8080)}],
                        "env": spec.get("env", []),
                        "resources": {
                            "requests": {
                                "cpu": spec.get("resources", {}).get("cpu", "100m"),
                                "memory": spec.get("resources", {}).get("memory", "128Mi"),
                            },
                            "limits": {
                                "cpu": spec.get("resources", {}).get("cpu", "500m"),
                                "memory": spec.get("resources", {}).get("memory", "256Mi"),
                            },
                        },
                        "livenessProbe": {
                            "httpGet": {"path": "/healthz", "port": spec.get("port", 8080)},
                            "initialDelaySeconds": 15, "periodSeconds": 20,
                        },
                        "readinessProbe": {
                            "httpGet": {"path": "/ready", "port": spec.get("port", 8080)},
                            "initialDelaySeconds": 5, "periodSeconds": 10,
                        },
                    }],
                },
            },
        },
    }


def make_service(name: str, namespace: str, spec: dict, uid: str) -> dict:
    return {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {
            "name": name,
            "namespace": namespace,
            "ownerReferences": [{
                "apiVersion": "apps.example.com/v1alpha1",
                "kind": "WebApp",
                "name": name,
                "uid": uid,
                "blockOwnerDeletion": True,
                "controller": True,
            }],
        },
        "spec": {
            "selector": {"app": name},
            "ports": [{"port": 80, "targetPort": spec.get("port", 8080)}],
            "type": "ClusterIP",
        },
    }


@kopf.on.create("apps.example.com", "v1alpha1", "webapps")
@kopf.on.update("apps.example.com", "v1alpha1", "webapps")
def reconcile(spec, name, namespace, uid, status, patch, **kwargs):
    """Main reconciliation handler — called on create and update events."""
    api = kubernetes.client.AppsV1Api()
    core = kubernetes.client.CoreV1Api()

    logger.info(f"Reconciling WebApp {namespace}/{name}")

    # ── Reconcile Deployment ──────────────────────────────────
    desired_deploy = make_deployment(name, namespace, spec, uid)
    try:
        existing = api.read_namespaced_deployment(name, namespace)
        # Update if image or replicas changed
        existing.spec.replicas = spec.get("replicas", 2)
        existing.spec.template.spec.containers[0].image = spec["image"]
        api.patch_namespaced_deployment(name, namespace, desired_deploy)
        logger.info(f"Updated Deployment {name}")
    except kubernetes.client.exceptions.ApiException as e:
        if e.status == 404:
            api.create_namespaced_deployment(namespace, desired_deploy)
            logger.info(f"Created Deployment {name}")
        else:
            raise kopf.TemporaryError(f"Deployment error: {e}", delay=30)

    # ── Reconcile Service ─────────────────────────────────────
    desired_svc = make_service(name, namespace, spec, uid)
    try:
        core.read_namespaced_service(name, namespace)
        core.patch_namespaced_service(name, namespace, desired_svc)
    except kubernetes.client.exceptions.ApiException as e:
        if e.status == 404:
            core.create_namespaced_service(namespace, desired_svc)
        else:
            raise kopf.TemporaryError(f"Service error: {e}", delay=30)

    # ── Update status subresource ─────────────────────────────
    patch.status["conditions"] = [{
        "type": "Reconciled",
        "status": "True",
        "message": f"Deployment and Service for {name} are in sync",
    }]


@kopf.on.field("apps.example.com", "v1alpha1", "webapps", field="spec.replicas")
def on_replicas_change(old, new, name, namespace, **kwargs):
    """React specifically to replica count changes."""
    logger.info(f"Scaling {namespace}/{name}: {old} → {new} replicas")


if __name__ == "__main__":
    kopf.run()
