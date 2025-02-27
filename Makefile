# Get AWS account and region information
AWS_ACCOUNT := $(shell aws sts get-caller-identity --query 'Account' --output text --no-cli-pager)
AWS_REGION := $(shell aws configure get region)
ECR_REPO := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com/batch-worker

.PHONY: help deploy monitor clean clean-all verify-cleanup logs list-resources

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

verify-cleanup: ## Verify that cleanup was successful
	@echo "→ Verifying cleanup..."
	@if aws ecr describe-repositories --no-cli-pager --repository-names batch-worker --region $(AWS_REGION) 2>/dev/null; then \
		echo "→ Found existing ECR repository. Forcing deletion..."; \
		aws ecr delete-repository --no-cli-pager --repository-name batch-worker --force --region $(AWS_REGION) || true; \
		sleep 5; \
	fi
	@echo "→ Cleanup verification complete"

deploy: verify-cleanup ## Deploy the infrastructure and submit a test job
	@echo "→ Building and deploying AWS Batch infrastructure..."
	cd app/worker && docker build --platform linux/amd64 -t batch-worker .
	(cd terraform && terraform init && terraform apply -auto-approve)
	@echo "→ Logging into ECR in $(AWS_REGION)..."
	aws ecr get-login-password --no-cli-pager --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REPO)
	@echo "→ Tagging and pushing image to $(ECR_REPO)..."
	docker tag batch-worker:latest $(ECR_REPO):latest
	docker push $(ECR_REPO):latest

submit-job: ## Submit a new batch job
	@echo "→ Submitting test job..."
	@JOB_ID=$$(aws batch submit-job \
		--no-cli-pager \
		--job-name "test-job-$$(date +%s)" \
		--job-queue "$$(cd terraform && terraform output -raw batch_job_queue_name)" \
		--job-definition "$$(cd terraform && terraform output -raw job_definition_arn)" \
		--query 'jobId' \
		--output text); \
	echo "→ Job submitted with ID: $$JOB_ID"; \
	$(MAKE) monitor JOB_ID=$$JOB_ID

monitor: ## Monitor a specific job (Usage: make monitor JOB_ID=xxx)
	@if [ -z "$(JOB_ID)" ]; then \
		echo "→ Error: JOB_ID is required. Usage: make monitor JOB_ID=xxx"; \
		exit 1; \
	fi
	@./monitor.sh "$(JOB_ID)" "$(AWS_REGION)"

clean: ## Remove all Terraform-managed resources
	@echo "→ Cleaning up AWS resources..."
	@echo "→ Removing CloudWatch log group..."
	aws logs delete-log-group --no-cli-pager --log-group-name "/aws/batch/job" --region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Removing AWS Batch resources..."
	@JOB_QUEUE=$$(cd terraform && terraform output -raw batch_job_queue_name 2>/dev/null) || true; \
	if [ "$$JOB_QUEUE" != "" ]; then \
		echo "→ Disabling job queue: $$JOB_QUEUE"; \
		aws batch update-job-queue --no-cli-pager --job-queue "$$JOB_QUEUE" --state DISABLED --region $(AWS_REGION) 2>/dev/null || true; \
		sleep 10; \
		echo "→ Deleting job queue: $$JOB_QUEUE"; \
		aws batch delete-job-queue --no-cli-pager --job-queue "$$JOB_QUEUE" --region $(AWS_REGION) 2>/dev/null || true; \
		sleep 10; \
	fi
	@echo "→ Disabling compute environment..."
	aws batch update-compute-environment \
		--no-cli-pager \
		--compute-environment batch-compute-environment \
		--state DISABLED \
		--region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Waiting for compute environment to be disabled..."
	while [ "$$(aws batch describe-compute-environments --no-cli-pager --compute-environments batch-compute-environment --query 'computeEnvironments[0].state' --output text --region $(AWS_REGION) 2>/dev/null)" != "DISABLED" ]; do \
		echo "→ Still waiting for compute environment to be disabled..."; \
		sleep 10; \
	done
	@echo "→ Compute environment is now disabled"
	@echo "→ Deleting compute environment..."
	aws batch delete-compute-environment \
		--no-cli-pager \
		--compute-environment batch-compute-environment \
		--region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Waiting for compute environment to be deleted..."
	while aws batch describe-compute-environments --no-cli-pager --compute-environments batch-compute-environment --query 'computeEnvironments[0].state' --output text --region $(AWS_REGION) 2>/dev/null; do \
		echo "→ Still waiting for compute environment to be deleted..."; \
		sleep 10; \
	done
	@echo "→ Compute environment has been deleted"
	@echo "→ Running Terraform destroy..."
	cd terraform && \
		terraform init && \
		terraform destroy -auto-approve || true
	@echo "→ Cleaning up IAM roles..."
	aws iam detach-role-policy --no-cli-pager --role-name aws_batch_service_role --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole 2>/dev/null || true
	aws iam detach-role-policy --no-cli-pager --role-name ecs_task_execution_role --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
	aws iam delete-role --no-cli-pager --role-name aws_batch_service_role 2>/dev/null || true
	aws iam delete-role --no-cli-pager --role-name ecs_task_execution_role 2>/dev/null || true
	@echo "→ Cleaning up Terraform files..."
	rm -rf terraform/.terraform* terraform/terraform.tfstate*
	@echo "→ Cleanup complete"

clean-all: ## Remove all resources including Docker images and ECR repository
	@echo "→ Starting full cleanup..."
	@echo "→ Cleaning up Docker images..."
	-docker rmi batch-worker:latest 2>/dev/null || true
	-docker rmi $(ECR_REPO):latest 2>/dev/null || true
	@echo "→ Removing ECR repository..."
	-aws ecr delete-repository --no-cli-pager --repository-name batch-worker --force --region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Waiting for ECR repository deletion..."
	sleep 5
	@echo "→ Running Terraform cleanup..."
	$(MAKE) clean
	@echo "→ Full cleanup complete"

logs: ## View CloudWatch logs for a specific job (Usage: make logs JOB_ID=xxx)
	@if [ -z "$(JOB_ID)" ]; then \
		echo "→ Error: JOB_ID is required. Usage: make logs JOB_ID=xxx"; \
		exit 1; \
	fi
	@LOG_STREAM=$$(aws batch describe-jobs --no-cli-pager --jobs $(JOB_ID) --region $(AWS_REGION) --query 'jobs[0].container.logStreamName' --output text); \
	if [ "$$LOG_STREAM" != "None" ]; then \
		aws logs get-log-events \
			--no-cli-pager \
			--log-group-name "/aws/batch/job" \
			--log-stream-name "$$LOG_STREAM" \
			--region $(AWS_REGION) \
			--query 'events[*].[timestamp,message]' \
			--output text | while read -r timestamp message; do \
				date_str=$$(date -r $$((timestamp / 1000)) "+%Y-%m-%d %H:%M:%S"); \
				echo "[$$date_str] $$message"; \
			done; \
	else \
		echo "→ No logs available yet for job $(JOB_ID)"; \
	fi

list-resources: ## List all potentially billable AWS resources
	@echo "→ Checking AWS Batch Compute Environments..."
	@aws batch describe-compute-environments \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'computeEnvironments[].{Name:computeEnvironmentName,State:state,Type:computeResources.type}' \
		--output table

	@echo "\n→ Checking ECR Repositories..."
	@aws ecr describe-repositories \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'repositories[].{Name:repositoryName,Images:imageTagMutability,URI:repositoryUri}' \
		--output table

	@echo "\n→ Checking ECR Images..."
	@aws ecr describe-images \
		--no-cli-pager \
		--repository-name batch-worker \
		--region $(AWS_REGION) \
		--query 'imageDetails[].{Tags:imageTags,Size:imageSizeInBytes,PushedAt:imagePushedAt}' \
		--output table 2>/dev/null || echo "No images found"

	@echo "\n→ Checking CloudWatch Log Groups..."
	@aws logs describe-log-groups \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'logGroups[].{Name:logGroupName,StoredBytes:storedBytes,RetentionDays:retentionInDays}' \
		--output table

	@echo "\n→ Checking Network Resources..."
	@echo "VPCs:"
	@aws ec2 describe-vpcs \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,CidrBlock:CidrBlock,State:State}' \
		--output table

	@echo "\nSubnets:"
	@aws ec2 describe-subnets \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'Subnets[].{Name:Tags[?Key==`Name`].Value|[0],SubnetId:SubnetId,VpcId:VpcId,CidrBlock:CidrBlock,AvailabilityZone:AvailabilityZone}' \
		--output table

	@echo "\nInternet Gateways:"
	@aws ec2 describe-internet-gateways \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'InternetGateways[].{Name:Tags[?Key==`Name`].Value|[0],IgwId:InternetGatewayId,VpcId:Attachments[0].VpcId}' \
		--output table

	@echo "\nSecurity Groups:"
	@aws ec2 describe-security-groups \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'SecurityGroups[].{Name:GroupName,Id:GroupId,VpcId:VpcId,Description:Description}' \
		--output table

	@echo "\n→ Checking Running ECS Tasks..."
	@aws ecs list-tasks \
		--no-cli-pager \
		--region $(AWS_REGION) \
		--query 'taskArns[]' \
		--output table 2>/dev/null || echo "No running tasks" 