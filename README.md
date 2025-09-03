I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Create the secret, build the Docker image and deploy the application.
```bash
bash create-secret.sh
docker build -t anime-recommender-app:latest .
kubectl apply -f llmops-k8s.yaml
```

If you need to delete the deployment, use:
```bash
kubectl delete -f llmops-k8s.yaml
```

Check the created secret:
```bash
kubectl get secrets
```

Check the status of your pods, services, and ingress resources:
```bash
echo "=== Pods in default namespace ==="
kubectl get pods

echo "=== Services in default namespace ==="
kubectl get svc

echo "=== Ingress resources ==="
kubectl get ingress -A
```