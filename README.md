I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Install Docker and give permissions to your user.
```bash
cd MLops-Common
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
bash ingress-install.sh
```

If you forget certs, run:
```bash
kubeadm init phase upload-certs --upload-certs
````

Upload the certificates and run the script on other master nodes:
```bash
bash on_other_master.sh
```

Check if ready:
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Install Helm and Prometheus:
```bash
bash helm-install.sh
bash prometheus-install.sh
```

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

Rancher setup (optional):
```bash
sudo mkfs.ext4 -m 0 /dev/sdb
mkdir /data
echo "/dev/sdb  /data  ext4  defaults  0  0" | sudo tee -a /etc/fstab
mount -a
sudo df -h

mkdir /data/rancher
cd /data/rancher
nano docker-compose.yml
```

Docker-compose file for Rancher:
```yaml
version: '3'
services:
  rancher-server:
    image: rancher/rancher:v2.9.2
    container_name: rancher-server
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /data/rancher/data:/var/lib/rancher
    privileged: true
```

Run Rancher and get the bootstrap password:
```bash
docker-compose up -d
docker logs rancher-server 2>&1 | grep "Bootstrap Password:"
```