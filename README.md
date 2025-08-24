I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Running scripts in llmops folder.
```bash
cd llmops
bash docker-íntall.sh
bash minikube-install.sh
bash kubectl-install.sh
bash helm-install.sh
```

Create the secret:
```bash
bash create-secret.sh
```

Remember to give Docker permissions to your user.
```bash
sudo groupadd docker
sudo usermod -aG docker $USER
```

Setup Docker to start on boot:
```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

After give Docker permissions, start Minikube and install Prometheus and Ingress.
```bash
minikube start
bash prometheus-install.sh
bash ingress-install.sh
```

Build the Docker image and deploy the application.
```bash
eval $(minikube docker-env)
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