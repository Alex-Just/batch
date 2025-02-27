import os
import time
import logging
import sys

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)

logger = logging.getLogger(__name__)

def process_job():
    """
    Simulate a batch processing job.
    In a real application, this would do actual work like data processing,
    ML training, etc.
    """
    job_id = os.environ.get('AWS_BATCH_JOB_ID', 'local-job')
    logger.info(f"Starting job processing for job ID: {job_id}")
    
    # Simulate some work
    total_steps = 5
    for step in range(total_steps):
        logger.info(f"Processing step {step + 1}/{total_steps}")
        time.sleep(2)  # Simulate work being done
        
    logger.info(f"Job {job_id} completed successfully")

if __name__ == "__main__":
    try:
        process_job()
    except Exception as e:
        logger.error(f"Error processing job: {str(e)}")
        sys.exit(1)
    
    sys.exit(0) 
