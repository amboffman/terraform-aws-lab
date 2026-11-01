output "site_url" {
  description = "Open this in a browser after apply (CloudFront can take a few minutes to deploy)"
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "site_bucket" {
  value = aws_s3_bucket.site.bucket
}

output "cloudfront_distribution_id" {
  description = "Needed to invalidate the cache after changing site files"
  value       = aws_cloudfront_distribution.site.id
}
