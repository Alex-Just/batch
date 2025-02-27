# Get AWS account and region information
AWS_ACCOUNT := $(shell aws sts get-caller-identity --query 'Account' --output text)
AWS_REGION := $(shell aws configure get region)
ECR_REPO := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com/batch-worker

.PHONY: help deploy monitor clean clean-all verify-cleanup logs

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

verify-cleanup: ## Verify that cleanup was successful
	@echo "→ Verifying cleanup..."
	@if aws ecr describe-repositories --repository-names batch-worker --region $(AWS_REGION) 2>/dev/null; then \
		echo "→ Found existing ECR repository. Forcing deletion..."; \
		aws ecr delete-repository --repository-name batch-worker --force --region $(AWS_REGION) || true; \
		sleep 5; \
	fi
	@echo "→ Cleanup verification complete"

deploy: verify-cleanup ## Deploy the infrastructure and submit a test job
	@echo "→ Building and deploying AWS Batch infrastructure..."
	cd app/worker && docker build --platform linux/amd64 -t batch-worker .
	(cd terraform && terraform init && terraform apply -auto-approve)
	@echo "→ Logging into ECR in $(AWS_REGION)..."
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REPO)
	@echo "→ Tagging and pushing image to $(ECR_REPO)..."
	docker tag batch-worker:latest $(ECR_REPO):latest
	docker push $(ECR_REPO):latest

submit-job: ## Submit a new batch job
	@echo "→ Submitting test job..."
	@JOB_ID=$$(aws batch submit-job \
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
	aws logs delete-log-group --log-group-name "/aws/batch/job" --region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Running Terraform destroy..."
	cd terraform && \
		terraform init && \
		terraform destroy -auto-approve
	rm -rf terraform/.terraform* terraform/terraform.tfstate*

clean-all: ## Remove all resources including Docker images and ECR repository
	@echo "→ Cleaning up Docker images..."
	docker rmi batch-worker:latest 2>/dev/null || true
	docker rmi $(ECR_REPO):latest 2>/dev/null || true
	@echo "→ Removing ECR repository..."
	aws ecr delete-repository --repository-name batch-worker --force --region $(AWS_REGION) 2>/dev/null || true
	@echo "→ Waiting for ECR repository deletion..."
	sleep 5
	@echo "→ Running Terraform cleanup..."
	$(MAKE) clean

logs: ## View CloudWatch logs for a specific job (Usage: make logs JOB_ID=xxx)
	@if [ -z "$(JOB_ID)" ]; then \
		echo "→ Error: JOB_ID is required. Usage: make logs JOB_ID=xxx"; \
		exit 1; \
	fi
	@LOG_STREAM=$$(aws batch describe-jobs --jobs $(JOB_ID) --region $(AWS_REGION) --query 'jobs[0].container.logStreamName' --output text); \
	if [ "$$LOG_STREAM" != "None" ]; then \
		aws logs get-log-events \
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