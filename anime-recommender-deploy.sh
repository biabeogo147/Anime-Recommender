#!/usr/bin/env bash

# Kubectl (CLI for Kubernetes clusters)
# Helm (Package manager for Kubernetes)

eval $(minikube docker-env)
docker build -t anime-recommender-app:latest .

# Create secretRef for anime-recommender
kubectl create secret generic anime-recommender-secrets \
  --from-literal=GROQ_API_KEY="" \
  --from-literal=HUGGINGFACEHUB_API_TOKEN=""


# Install helm
#sudo apt-get update && sudo apt-get upgrade -y
#curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack in the "monitoring" namespace
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# List all CRD in the cluster, if Prometheus Operator is installed, it should show "servicemonitors.monitoring.coreos.com"
kubectl get crd | grep servicemonitors

# Deploy the LLMOps application
kubectl apply -f llmops-k8s.yaml

# List all pods in the default namespace to check if the LLMOps application is running
kubectl get pods

# Expose the LLMOps service
minikube tunnel
kubectl get svc llmops-service