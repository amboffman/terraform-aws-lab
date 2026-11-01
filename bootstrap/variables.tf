variable "project" {
  description = "Short name used as a prefix on every resource"
  type        = string
  default     = "tf-lab"
}

variable "region" {
  description = "AWS region for everything in this project"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use (set up with aws configure --profile)"
  type        = string
  default     = "tf-lab"
}

variable "budget_limit_usd" {
  description = "Monthly spend that triggers the alert emails"
  type        = string
  default     = "10"
}

variable "alert_email" {
  description = "Where budget alerts go. Put this in terraform.tfvars, not in code."
  type        = string
}
