#!/bin/bash

kubectl create secret generic anime-recommender-secrets \
  --from-literal=GOOGLE_API_KEY="" \
  --from-literal=HUGGINGFACEHUB_API_TOKEN="" \
  --dry-run=client -o yaml | kubectl apply -f -