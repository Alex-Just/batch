#!/bin/bash

# Exit on error
set -e

echo "Building Docker image..."
cd app/worker
docker build -t batch-worker .
cd ../..

echo "Initializing Terraform..."
cd terraform
terraform init

echo "Applying Terraform configuration..."
terraform apply -auto-approve

# Get the ECR repository URL
REPO_URL=$(terraform output -raw repository_url)
AWS_REGION=$(terraform output -raw aws_region)

echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPO_URL

echo "Tagging and pushing Docker image..."
docker tag batch-worker:latest $REPO_URL:latest
docker push $REPO_URL:latest

echo "Getting job queue and job definition ARNs..."
JOB_QUEUE=$(terraform output -raw batch_job_queue_name)
JOB_DEFINITION_ARN=$(terraform output -raw job_definition_arn)

echo "Submitting test job..."
JOB_ID=$(aws batch submit-job \
    --job-name "test-job-$(date +%s)" \
    --job-queue "$JOB_QUEUE" \
    --job-definition "$JOB_DEFINITION_ARN" \
    --query 'jobId' \
    --output text)

echo "Job submitted with ID: $JOB_ID"
echo "Monitoring job..."
./monitor.sh "$JOB_ID"

echo "Deployment complete! Check AWS Batch console for job status." 