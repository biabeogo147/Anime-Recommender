# One ACM certificate for anime.recruitai.io.vn and *.anime.recruitai.io.vn, served by both load balancers.
#
# It is in this stack on purpose. Created in the cluster stack it would be RE-ISSUED on every rebuild instead of
# renewed, and "AWS renews it for us" would silently never happen (Terraform A2.3). Here it is issued once.
resource "aws_acm_certificate" "wildcard" {
  domain_name               = local.domain
  subject_alternative_names = ["*.${local.domain}"]
  validation_method         = "DNS" # ACM checks a CNAME it asks us to create; it never looks at the A record

  lifecycle {
    create_before_destroy = true # a replacement exists before the old one is detached
  }
}

# The validation CNAMEs. The apex and the wildcard ask for the SAME record, so the map is keyed by the domain with any
# "*." removed and grouped with `...`: two entries collapse into one. The key must be known at plan time — the record
# name itself is only known after the certificate exists, and for_each cannot use it.
# Renewal needs this record to STILL be here months from now — deleting it breaks next year, not today.
resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.wildcard.domain_validation_options : trimprefix(o.domain_name, "*.") => o...
  }

  zone_id         = data.aws_route53_zone.parent.zone_id
  name            = each.value[0].resource_record_name
  type            = each.value[0].resource_record_type
  ttl             = 300
  records         = [each.value[0].resource_record_value]
  allow_overwrite = true # a record left by an earlier, destroyed certificate for the same names is taken over
}

# Makes `apply` wait until ACM says ISSUED, so a stuck PENDING_VALIDATION fails here — loudly — instead of
# surfacing later as an ALB with no HTTPS listener and an Ingress that looks fine (GitOps A3.10).
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# Every Ingress names the certificate by this ARN. Left unnamed, the load balancer controller would pick one by
# host match among all certificates in the account (GitOps A3.7).
output "certificate_arn" {
  value = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "domain" {
  value = local.domain
}
