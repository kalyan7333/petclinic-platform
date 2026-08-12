output "zone_id" {
  description = "Route 53 hosted zone ID (looked up from existing zone; empty when enable_dns = false)"
  value       = try(data.aws_route53_zone.this[0].zone_id, "")
}

output "name_servers" {
  description = "Name servers for the hosted zone (empty when enable_dns = false)"
  value       = try(data.aws_route53_zone.this[0].name_servers, [])
}

output "certificate_arn" {
  description = "ACM certificate ARN after DNS validation completes (empty when enable_dns = false)"
  value       = try(aws_acm_certificate_validation.this[0].certificate_arn, "")
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (used in install-lb-controller.sh)"
  value       = aws_iam_role.lb_controller.arn
}

output "alb_fqdn" {
  description = "Fully qualified domain name for the ALB alias record (empty if enable_dns = false or alb_dns_name is not set)"
  value       = var.enable_dns && var.alb_dns_name != "" ? "${var.subdomain}.${var.domain_name}" : ""
}
