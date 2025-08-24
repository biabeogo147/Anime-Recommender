#!/bin/bash

# ===============================
# 1) Build Docker image in Minikube
# ===============================
minikube start
eval $(minikube docker-env)
docker build -t anime-recommender-app:latest .

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
