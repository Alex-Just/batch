# =========================================
# Variables Configuration
# =========================================
# This file defines all variables used across
# the Terraform configuration files.
#
# Includes:
# - AWS region configuration
# - Network CIDR ranges
# - AWS Batch resource naming
# =========================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "batch_job_definition_name" {
  description = "Name for the AWS Batch Job Definition"
  type        = string
  default     = "batch-job-definition"
}

variable "batch_job_queue_name" {
  description = "Name for the AWS Batch Job Queue"
  type        = string
  default     = "batch-job-queue"
}

variable "batch_compute_environment_name" {
  description = "Name for the AWS Batch Compute Environment"
  type        = string
  default     = "batch-compute-environment"
}

output "aws_region" {
  description = "The AWS region being used"
  value       = var.aws_region
} 