I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Install Docker and give permissions to your user.
```bash
cd llmops
bash docker-íntall.sh
sudo groupadd docker
sudo usermod -aG docker $USER
```

Setup Docker to start on boot:
```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

If you use Minikube, run the following commands:
```bash
cd minikube-setup
bash minikube-install.sh
bash kubectl-install.sh
bash ingress-install.sh
minikube start
eval $(minikube docker-env)
```

If you use k8s, run the following commands:
```bash
cd k8s-setup
bash setup-k8s-env.sh
bash on_first_master.sh
bash on_other_master.sh
bash ingress-install.sh
```

Install Helm and Prometheus:
```bash
bash helm-install.sh
bash prometheus-install.sh
```

Create the secret:
```bash
bash create-secret.sh
```

Build the Docker image and deploy the application.
```bash
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