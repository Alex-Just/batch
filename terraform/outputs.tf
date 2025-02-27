# =========================================
# Terraform Outputs Configuration
# =========================================
# This file defines all output values that are
# displayed after Terraform applies the configuration.
#
# Outputs include:
# - AWS Batch resource names
# - VPC and subnet IDs
#
# These values are used by the deployment script
# to submit test jobs to AWS Batch.
# =========================================

output "batch_job_queue_name" {
  description = "The name of the AWS Batch job queue"
  value       = aws_batch_job_queue.job_queue.name
}

output "batch_job_definition_name" {
  description = "The name of the AWS Batch job definition"
  value       = aws_batch_job_definition.job_definition.name
}

output "batch_compute_environment_name" {
  description = "The name of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.compute_environment.compute_environment_name
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.batch_vpc.id
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = aws_subnet.batch_subnet.id
} 