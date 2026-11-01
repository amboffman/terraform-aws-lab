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
  description = "Named AWS CLI profile to use"
  type        = string
  default     = "tf-lab"
}
