# Kubernetes Services (L4) & Ingress (L7) — Beginner Practical Lab (K8s v1.27.2)

This README gives you a **hands-on**, **beginner-friendly** workflow to understand and practice:

- **Service (L4)** load-balancing inside the cluster
- **Ingress (L7)** HTTP/HTTPS routing from outside to services

It is designed for a **local / bare-metal / kubeadm-style** Kubernetes cluster.



## ✅ Goal (What you will learn practically)

### 1) Service (L4)

- Exposes Pods using **IP:PORT**
- Load-balances traffic to Pods (typically round-robin)
- Types you’ll practice:
  - `ClusterIP` (internal)
  - `NodePort` (reachable from outside via `NodeIP:NodePort`)

### 2) Ingress (L7)

- Routes **HTTP/HTTPS** traffic using:
  - Hostnames (example: `demo.local`)
  - Paths (example: `/app1`, `/app2`)
- Needs an **Ingress Controller** (nginx/traefik/etc.) to actually work



# LAB 0 — Pre-checks (your cluster)

Run:


kubectl get nodes -o wide


Note down:

- Node IPs (especially `INTERNAL-IP` for node1/node2/node3)



# LAB 1 — Deploy 2 sample apps (so you can route to them)

We’ll deploy two tiny HTTP apps:

- `app1` → shows “APP1”
- `app2` → shows “APP2”

Create a file **`apps.yaml`**:


apiVersion: v1
kind: Namespace
metadata:
  name: demo

apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - name: app1
        image: hashicorp/http-echo:0.2.3
        args: ["-text=Hello from APP1"]
        ports:
        - containerPort: 5678

apiVersion: v1
kind: Service
metadata:
  name: app1-svc
  namespace: demo
spec:
  selector:
    app: app1
  ports:
  - port: 80
    targetPort: 5678
  type: ClusterIP

apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
      - name: app2
        image: hashicorp/http-echo:0.2.3
        args: ["-text=Hello from APP2"]
        ports:
        - containerPort: 5678

apiVersion: v1
kind: Service
metadata:
  name: app2-svc
  namespace: demo
spec:
  selector:
    app: app2
  ports:
  - port: 80
    targetPort: 5678
  type: ClusterIP


Apply it:


kubectl apply -f apps.yaml
kubectl -n demo get pods,svc -o wide




# LAB 2 — Understand Service (L4) practically

## ✅ 2.1 ClusterIP is internal only

Try to access the service **from inside the cluster**:


kubectl -n demo run tmp --image=curlimages/curl:8.5.0 -it --rm -- sh


Inside that shell:

sh
curl http://service/jenkins
curl http://service/jenkins-jnlp
exit


✅ This proves **Service works as an L4 load-balancer inside the cluster**.



## ✅ 2.2 Make it reachable from outside using NodePort

Patch app1 service to NodePort:


kubectl -n demo patch svc app1-svc -p '{"spec":{"type":"NodePort"}}'
kubectl -n demo get svc app1-svc


You’ll see output like:

- `80:3xxxx/TCP` → that `3xxxx` is the **NodePort*curl*

Now from your machine (or node1), curl:


curl http://<ANY_NODE_IP>:<NODEPORT>


Example:


curl http://192.168.1.10:30789


✅ This is **Service L4 exposure (NodePort)** — no hostname/path logic, only **IP:PORT**.



# LAB 3 — Install Ingress Controller (nginx)

Ingress **will not work** until an Ingress Controller exists.

## Option A (Most common & simple): install ingress-nginx

Run:


kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml


Wait:


kubectl -n ingress-nginx get pods


You want all pods `Running`.



## ✅ 3.1 Check ingress-nginx service type

Run:


kubectl -n ingress-nginx get svc


On bare metal, it often creates a Service (commonly `NodePort`).

If it’s `LoadBalancer` and your cluster doesn’t have MetalLB, it will stay `<pending>`.
In that case, patch it to NodePort:


kubectl -n ingress-nginx patch svc ingress-nginx-controller -p '{"spec":{"type":"NodePort"}}'
kubectl -n ingress-nginx get svc ingress-nginx-controller


Note the NodePorts (80 and/or 443).



# LAB 4 — Create Ingress (L7 routing: host + path)

Create **`ingress.yaml`**:

yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: demo
spec:
  ingressClassName: nginx
  rules:
  - host: demo.local
    http:
      paths:
      - path: /app1
        pathType: Prefix
        backend:
          service:
            name: app1-svc
            port:
              number: 80
      - path: /app2
        pathType: Prefix
        backend:
          service:
            name: app2-svc
            port:
              number: 80


Apply it:


kubectl apply -f ingress.yaml
kubectl -n demo get ingress
kubectl -n demo describe ingress demo-ingress




# LAB 5 — Test Ingress from outside (the real practical part)

## Method 1 (No DNS needed): use curl with Host header

Find ingress controller NodePort:


kubectl -n ingress-nginx get svc ingress-nginx-controller


Assume:

- Node IP: `192.168.1.10`
- HTTP NodePort: `32080`

Test:


curl -H "Host: demo.local" http://192.168.1.10:32080/app1
curl -H "Host: demo.local" http://192.168.1.10:32080/app2


✅ You’ll get:

- `Hello from APP1`
- `Hello from APP2`

That is **L7 routing** in action.



## Method 2 (User-friendly): map host to IP using /etc/hosts

On your laptop/VM where you are running curl:

Edit `/etc/hosts`:


sudo nano /etc/hosts


Add:


192.168.1.10   demo.local


Now you can do:


curl http://demo.local:32080/app1
curl http://demo.local:32080/app2




# ✅ What you just proved (very important)

## Service (L4)

- Works with **IP:PORT**
- Doesn’t understand HTTP paths/hosts
- Example:
  - `NodeIP:NodePort → app`

## Ingress (L7)

- Understands **HTTP**
- Uses:
  - Hostname-based routing (`demo.local`)
  - Path-based routing (`/app1`, `/app2`)
- Needs a controller (nginx) to function



# Troubleshooting (beginner checklist)

## 1) Ingress not working?

Check controller pods:


kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50


## 2) Ingress exists but routes not working?

Check if it picked class `nginx`:


kubectl -n demo describe ingress demo-ingress
kubectl get ingressclass


## 3) Service endpoints missing?

Means Pods not matching selector:


kubectl -n demo get endpoints app1-svc app2-svc
kubectl -n demo get pods --show-labels




# Common pitfall: HTTP vs HTTPS NodePort (your exact case)

If your ingress-nginx service shows something like:


80:32071/TCP, 443:30341/TCP


Then:

- ✅ Use **HTTP** with port **32071**:


curl -i -H "Host: demo.local" http://192.168.0.21:32071/app1


- ✅ Use **HTTPS** with port **30341** (often needs `-k` for self-signed cert):


curl -k -i -H "Host: demo.local" https://192.168.0.21:30341/app1


- ❌ If you do `http://...:30341` you will get:

> `400 The plain HTTP request was sent to HTTPS port`



# Next step (to make it more “real world”)

Once you are comfortable:

- ✅ Add TLS (HTTPS) using a self-signed cert or **cert-manager**
- ✅ Try multiple hostnames: `app1.local`, `app2.local`
- ✅ Install **MetalLB** to get real `LoadBalancer` IP (better than NodePort)



## Quick question (for better guidance)

Your cluster looks like kubeadm on VMs/servers.

👉 Are you running Kubernetes on **VMs**, or using **kind / minikube**?

If you share that + your node IP range (e.g., `192.168.x.x`), you’ll get the best exposure method guidance (NodePort vs MetalLB) for your environment.

sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 32429
sudo iptables -t nat -A PREROUTING -p tcp --dport 80  -j REDIRECT --to-ports 31707

kubectl -n jenkins annotate ingress jenkins-ingress \
  nginx.ingress.kubernetes.io/ssl-redirect="false" --overwrite

cd ~/K8-s-Deployment-/jenkins

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout privkey.pem \
  -out fullchain.pem \
  -subj "/CN=jenkins.raja.com" \
  -addext "subjectAltName=DNS:jenkins.raja.com"

kubectl -n jenkins create secret tls jenkins-tls \
  --cert=fullchain.pem \
  --key=privkey.pem

kubectl apply -f ingress.yaml

kubectl -n jenkins get ingress
curl -vk https://jenkins.raja.com/

kubectl -n jenkins get secret jenkins-tls
kubectl -n jenkins describe secret jenkins-tls
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide

kubectl -n ingress-nginx patch svc ingress-nginx-controller \
  -p '{"spec":{"type":"LoadBalancer"}}'
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
