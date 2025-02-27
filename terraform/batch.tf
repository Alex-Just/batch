# =========================================
# AWS Batch Configuration
# =========================================
# This file contains all AWS Batch related resources:
# - IAM roles and policies
# - Batch compute environment
# - Job queue configuration
# - Job definition
#
# The resources defined here create the core
# AWS Batch infrastructure needed to run jobs.
# =========================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Check if roles already exist
data "aws_iam_role" "existing_batch_service_role" {
  name = "aws_batch_service_role"
}

data "aws_iam_role" "existing_ecs_task_execution_role" {
  name = "ecs_task_execution_role"
}

# Check if compute environment already exists
data "aws_batch_compute_environment" "existing" {
  compute_environment_name = "batch-compute-environment"
}

# Check if job queue already exists
data "aws_batch_job_queue" "existing" {
  name = var.batch_job_queue_name
}

# AWS Batch Service Role
resource "aws_iam_role" "aws_batch_service_role" {
  count = data.aws_iam_role.existing_batch_service_role == null ? 1 : 0
  name = "aws_batch_service_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_batch_service_role" {
  role       = try(aws_iam_role.aws_batch_service_role[0].name, data.aws_iam_role.existing_batch_service_role.name)
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  count = data.aws_iam_role.existing_ecs_task_execution_role == null ? 1 : 0
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = try(aws_iam_role.ecs_task_execution_role[0].name, data.aws_iam_role.existing_ecs_task_execution_role.name)
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach CloudWatch Logs Policy
resource "aws_iam_role_policy_attachment" "ecs_task_cloudwatch_policy" {
  role       = try(aws_iam_role.ecs_task_execution_role[0].name, data.aws_iam_role.existing_ecs_task_execution_role.name)
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# AWS Batch Compute Environment
resource "aws_batch_compute_environment" "batch_compute_env" {
  count = data.aws_batch_compute_environment.existing == null ? 1 : 0
  compute_environment_name = "batch-compute-environment"

  compute_resources {
    max_vcpus = 16
    min_vcpus = 0
    security_group_ids = [
      aws_security_group.batch_sg.id
    ]
    subnets = [
      aws_subnet.batch_subnet.id
    ]
    type = "FARGATE"
  }

  service_role = try(aws_iam_role.aws_batch_service_role[0].arn, data.aws_iam_role.existing_batch_service_role.arn)
  type         = "MANAGED"
  state        = "ENABLED"

  depends_on = [
    aws_iam_role_policy_attachment.aws_batch_service_role
  ]
}

# AWS Batch Job Queue
resource "aws_batch_job_queue" "job_queue" {
  count    = data.aws_batch_job_queue.existing == null ? 1 : 0
  name     = var.batch_job_queue_name
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order = 0
    compute_environment = try(aws_batch_compute_environment.batch_compute_env[0].arn, data.aws_batch_compute_environment.existing.arn)
  }
}

# AWS Batch Job Definition
resource "aws_batch_job_definition" "job_definition" {
  name = var.batch_job_definition_name
  type = "container"

  platform_capabilities = [
    "FARGATE"
  ]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_worker.repository_url}:latest"
    
    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }
    
    resourceRequirements = [
      {
        type  = "VCPU"
        value = "1"
      },
      {
        type  = "MEMORY"
        value = "2048"
      }
    ]
    
    executionRoleArn = try(aws_iam_role.ecs_task_execution_role[0].arn, data.aws_iam_role.existing_ecs_task_execution_role.arn)
    jobRoleArn       = try(aws_iam_role.ecs_task_execution_role[0].arn, data.aws_iam_role.existing_ecs_task_execution_role.arn)
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/job"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "batch-job"
      }
    }

    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }
  })

  tags = {
    Name = var.batch_job_definition_name
  }
}

# Output the full job definition name with revision
output "job_definition_arn" {
  value = aws_batch_job_definition.job_definition.arn
} 