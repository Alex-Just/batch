#!/bin/bash

# Check if job ID is provided
if [ -z "$1" ]; then
    echo "Please provide a job ID"
    echo "Usage: ./monitor.sh <job-id> [aws-region]"
    exit 1
fi

JOB_ID=$1
NEXT_TOKEN=""
AWS_REGION="${2:-$(aws configure get region)}"  # Use provided region or fall back to configured region

# Function to get job status
get_job_status() {
    aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].status' --output text --region $AWS_REGION
}

# Function to get log stream name
get_log_stream() {
    aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].container.logStreamName' --output text --region $AWS_REGION
}

# Function to get new logs
get_new_logs() {
    local log_stream=$1
    local token_arg=""
    if [ -n "$NEXT_TOKEN" ]; then
        token_arg="--next-token $NEXT_TOKEN"
    fi
    
    # Get logs and next token
    local result=$(aws logs get-log-events \
        --log-group-name "/aws/batch/job" \
        --log-stream-name "$log_stream" \
        --region $AWS_REGION \
        $token_arg \
        --output json)
    
    # Update next token for next iteration
    NEXT_TOKEN=$(echo "$result" | jq -r '.nextForwardToken')
    
    # Output events
    echo "$result" | jq -r '.events[] | "\(.timestamp) \(.message)"' | while read -r timestamp message; do
        date_str=$(date -r $(( timestamp / 1000 )) "+%Y-%m-%d %H:%M:%S")
        echo "[$date_str] $message"
    done
}

echo "→ Monitoring job: $JOB_ID"
echo "-------------------"

# Create CloudWatch log group if it doesn't exist
aws logs create-log-group --log-group-name "/aws/batch/job" --region $AWS_REGION 2>/dev/null || true

# Monitor job status until completion or failure
while true; do
    STATUS=$(get_job_status)
    echo "→ Current status: $STATUS"
    
    if [ "$STATUS" == "FAILED" ]; then
        echo -e "\n→ Job failed! Getting failure reason..."
        aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].container.reason' --output text --region $AWS_REGION
        aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].statusReason' --output text --region $AWS_REGION
        break
    elif [ "$STATUS" == "SUCCEEDED" ]; then
        echo -e "\n→ Job completed successfully!"
        break
    elif [ "$STATUS" == "RUNNING" ]; then
        # If job is running, stream new logs
        LOG_STREAM=$(get_log_stream)
        if [ -n "$LOG_STREAM" ] && [ "$LOG_STREAM" != "None" ]; then
            get_new_logs "$LOG_STREAM"
        fi
    fi
    
    sleep 10
done

# Final status check and log dump if failed
if [ "$STATUS" == "FAILED" ]; then
    LOG_STREAM=$(get_log_stream)
    if [ -n "$LOG_STREAM" ] && [ "$LOG_STREAM" != "None" ]; then
        echo -e "\n→ Complete job logs:"
        echo "-------------------"
        # Reset token to get all logs for the final dump
        NEXT_TOKEN=""
        get_new_logs "$LOG_STREAM"
    fi
fi

# Exit with appropriate status code
if [ "$STATUS" == "SUCCEEDED" ]; then
    exit 0
else
    exit 1
fi 