#!/usr/bin/env bash

# ===============================
# 1) Build Docker image in Minikube
# ===============================
minikube start
eval $(minikube docker-env)
docker build -t anime-recommender-app:latest .

# ===============================
# 2) Create Secret for Anime Recommender
# ===============================
kubectl create secret generic anime-recommender-secrets \
  --from-literal=GROQ_API_KEY="" \
  --from-literal=HUGGINGFACEHUB_API_TOKEN="" \
  --dry-run=client -o yaml | kubectl apply -f -

# ===============================
# 3) Install kube-prometheus-stack (Grafana + Prometheus)
# ===============================
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Wait until CRDs are available
kubectl get crd | grep servicemonitors

# ===============================
# 4) Enable Ingress Controller in Minikube
# ===============================
minikube addons enable ingress

# Wait until ingress controller is running
echo "⏳ Waiting for ingress controller..."
kubectl -n ingress-nginx wait --for=condition=available deployment/ingress-nginx-controller --timeout=180s

# ===============================
# 5) Deploy LLMOps App + Services + ServiceMonitor + Ingress
# ===============================
kubectl apply -f llmops-k8s.yaml

# ===============================
# 6) Check status
# ===============================
echo "=== Pods in default namespace ==="
kubectl get pods

echo "=== Services in default namespace ==="
kubectl get svc

echo "=== Ingress resources ==="
kubectl get ingress -A

# ===============================
# 7) Minikube IP (use in /etc/hosts for grafana.local, llmops.local, etc.)
# ===============================
echo "Cluster IP:"
minikube ip
