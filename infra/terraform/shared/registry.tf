# The two image repositories. They are here, not in the cluster stack, so the nightly teardown keeps every image
# and every signature: a morning rebuild pulls yesterday's digests instead of waiting for CI.
resource "aws_ecr_repository" "app" {
  for_each = toset(["api", "ui"])

  name = "${var.project}-${each.key}" # anime-api, anime-ui

  # CI pushes by digest and Git records the digest, so tags carry no meaning here. MUTABLE lets cosign write
  # its tag-style artefacts if a client version falls back to them.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # a free basic scan on every push, independent of CI's Trivy gate
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  # Keep the last 20 images (design §3). A rollback reverts the digest in Git, so it can only reach back as far
  # as this number. Whether cosign's signatures and SBOM attestations count against it depends on how the
  # client stores them — to be checked after the first signed push (CI/CD A2.3).
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
