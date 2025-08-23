I used source code from https://github.com/data-guru0/ANIME-RECOMMENDER-SYSTEM-LLMOPS and modified it based on my needs.

Install docker and minikube by running scripts in bash folder.
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
