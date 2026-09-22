# deploy/argocd/apps

One Argo CD Application per file, created by the `root` Application that `make bootstrap` installs. Argo CD reads
only YAML/JSON here, so this file is ignored by it; it exists so the directory is in Git before stage 2 adds the first
Application.

Waves and the order they enforce: [design §3](../../../docs/eks-sre-llmops-design.md#in-cluster-components-argo-cd-applications-deployargocdapps).
