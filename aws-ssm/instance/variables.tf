variable "env" {
  type = string
}
variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "auto_scaling_group_subnets" {
  type = list(string)
}

variable "tags" {
  description = "A mapping of tags to assign"
  default     = {}
  type        = map(string)
}

variable "session_kms_arn" {
  type = string
}

variable "log_bucket_arn" {
  type = string
}
