# AWS Batch Example with Terraform

This project demonstrates how to set up AWS Batch using Terraform and ECS for running batch processing jobs.

## Project Structure

```
.
├── terraform/          # Terraform configuration files
├── app/                # Application code
│   └── worker/         # Worker application code
├── Makefile            # Commands for deployment and management
├── monitor.sh          # Job monitoring script
└── README.md           # This file
```

## Prerequisites

### 1. AWS CLI
```bash
# Install AWS CLI on macOS using Homebrew
brew install awscli

# Configure AWS credentials
aws configure
```

### 2. Terraform
```bash
# Install Terraform on macOS using Homebrew
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify installation
terraform --version  # Should show version >= 1.0.0
```

### 3. Docker
```bash
# Install Docker Desktop for macOS
# Download from: https://www.docker.com/products/docker-desktop
# Or install via Homebrew
brew install --cask docker

# Start Docker Desktop and verify installation
docker --version
```

### 4. Python
```bash
# Install Python on macOS using Homebrew
brew install python@3.9

# Verify installation
python3 --version
```

### 5. jq
```bash
# Install jq on macOS using Homebrew
brew install jq

# Verify installation
jq --version
```

## Components

1. **AWS Batch Environment**
   - Compute Environment using ECS
   - Job Queue
   - Job Definition
   - IAM roles and policies

2. **Worker Application**
   - Simple Python application
   - Dockerized for ECS

## Setup and Deployment

1. Make the monitoring script executable:
   ```bash
   chmod +x monitor.sh
   ```

2. Deploy the infrastructure:
   ```bash
   make deploy
   ```

## Running Jobs

All operations are managed through the Makefile. Available commands:

```bash
# Show all available commands and their descriptions
make help

# Deploy infrastructure
make deploy

# Submit a new job
make submit-job

# Monitor a specific job
make monitor JOB_ID=xxx

# View logs for a specific job
make logs JOB_ID=xxx
```

## Monitoring Options

1. **Using Makefile commands:**
   ```bash
   # Monitor a job in real-time
   make monitor JOB_ID=xxx

   # View logs for a specific job
   make logs JOB_ID=xxx
   ```

2. **AWS Management Console:**
   - Go to AWS Batch console
   - Click on "Jobs" in the left navigation
   - Find your job in the list
   - Click on the job to see details and logs

3. **CloudWatch Logs:**
   - Log group: `/aws/batch/job`
   - Log streams are named using the format: `batch-job/your-job-name/ecs-task-id`

## Architecture

The application uses AWS Batch to manage and execute batch processing jobs:

1. Jobs are submitted to an AWS Batch Job Queue
2. AWS Batch schedules jobs on ECS containers
3. Worker containers process the jobs
4. Results are stored in CloudWatch Logs

## Security

- IAM roles are configured with least privilege access
- VPC security groups control network access
- Sensitive information is managed through AWS Secrets Manager

## Troubleshooting

1. **Job stuck in RUNNABLE state:**
   - Check VPC/subnet configuration
   - Verify security group settings
   - Ensure Fargate has internet access

2. **Job fails immediately:**
   - Check CloudWatch logs for errors
   - Verify container image exists
   - Check IAM roles and permissions

3. **No logs appearing:**
   - Verify CloudWatch log group exists
   - Check task execution role permissions
   - Wait a few minutes for logs to propagate

## Usage

The project includes a Makefile with common commands:

```bash
# Show available commands
make help

# Deploy infrastructure and submit a test job
make deploy

# Submit a new job
make submit-job

# Monitor a specific job
make monitor JOB_ID=xxx

# View logs for a specific job
make logs JOB_ID=xxx

# Clean up Terraform-managed resources
make clean

# Clean up everything (including Docker images and ECR repository)
make clean-all
```

### Sample Job Execution Flow

Here's what you'll see when submitting and monitoring a job:

```
→ make submit-job
→ Submitting test job...
→ Job submitted with ID: 0f9c821a-68d9-48b4-9637-39407b3141ff
→ Monitoring job: 0f9c821a-68d9-48b4-9637-39407b3141ff
-------------------
→ Current status: RUNNABLE
→ Current status: STARTING
→ Current status: STARTING
→ Current status: RUNNING
[2025-02-27 14:39:03] 2025-02-27 13:39:03,617 - __main__ - INFO - Starting job processing for job ID: 0f9c821a-68d9-48b4-9637-39407b3141ff
[2025-02-27 14:39:03] 2025-02-27 13:39:03,617 - __main__ - INFO - Processing step 1/5
[2025-02-27 14:39:05] 2025-02-27 13:39:05,619 - __main__ - INFO - Processing step 2/5
[2025-02-27 14:39:07] 2025-02-27 13:39:07,621 - __main__ - INFO - Processing step 3/5
[2025-02-27 14:39:09] 2025-02-27 13:39:09,623 - __main__ - INFO - Processing step 4/5
[2025-02-27 14:39:11] 2025-02-27 13:39:11,626 - __main__ - INFO - Processing step 5/5
→ Current status: RUNNING
[2025-02-27 14:39:13] 2025-02-27 13:39:13,628 - __main__ - INFO - Job 0f9c821a-68d9-48b4-9637-39407b3141ff completed successfully
→ Current status: SUCCEEDED

→ Job completed successfully!
```

The job goes through several states:
1. `RUNNABLE` - Job is queued and waiting for resources
2. `STARTING` - Container is being launched
3. `RUNNING` - Job is executing
4. `SUCCEEDED` - Job completed successfully (or `FAILED` if there was an error)

Live logs are streamed as they become available, showing the progress of your job.

## Cleanup

You can clean up resources using the Makefile:

```bash
# Remove Terraform-managed resources
make clean

# Remove everything including Docker images and ECR repository
make clean-all
```

The cleanup process will:
- Delete all AWS Batch resources (compute environment, job queue, job definitions)
- Remove the VPC and associated networking components
- Delete IAM roles and policies
- Remove CloudWatch log groups
- Delete the ECR repository and all container images
- Clean up local Docker images and Terraform state

Make sure you don't have any running jobs before cleanup, as they will be terminated. 