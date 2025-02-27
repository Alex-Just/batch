# =========================================
# ECR Repository Configuration
# =========================================
# This file contains the ECR repository
# configuration for storing Docker images
# =========================================

# Data source to check if repository exists
data "aws_ecr_repository" "existing" {
  name = "batch-worker"

  # Ignore errors if the repository doesn't exist
  depends_on = [aws_ecr_repository.batch_worker]
}

# Create the repository if it doesn't exist
resource "aws_ecr_repository" "batch_worker" {
  name                 = "batch-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Output the repository URL
output "repository_url" {
  value = aws_ecr_repository.batch_worker.repository_url
} 