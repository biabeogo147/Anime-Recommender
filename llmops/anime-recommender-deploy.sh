#!/bin/bash
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

kubectl describe ingress llmops-ingress -n default
kubectl describe ingress grafana-ingress -n monitoring

