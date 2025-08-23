minikube addons enable ingress
echo "⏳ Waiting for ingress controller..."
kubectl -n ingress-nginx wait --for=condition=available deployment/ingress-nginx-controller --timeout=180s