I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Install docker / minikube / kubectl / helm / prometheus / ingress by running scripts in bash folder.
Ensure minikube start before install prometheus and ingress.
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

```bash
minikube start
eval $(minikube docker-env)
docker build -t anime-recommender-app:latest .
```