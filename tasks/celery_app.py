"""
Celery Configuration for A2A Cyber
Background task processing with Redis
"""
import os
from celery import Celery

# Redis connection
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Create Celery app
celery_app = Celery(
    "a2a_cyber",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["tasks.security_tasks"]
)

# Celery configuration
celery_app.conf.update(
    # Task settings
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    
    # Result backend settings - store for 7 days
    result_expires=3600 * 24 * 7,  # Results expire after 7 days
    result_extended=True,
    
    # Task execution settings - allow long-running tasks
    task_track_started=True,
    task_time_limit=7200,  # 2 hour max per task
    task_soft_time_limit=6600,  # Soft limit 110 minutes
    
    # Worker settings
    worker_prefetch_multiplier=1,  # One task at a time per worker
    worker_concurrency=4,  # 4 concurrent workers
    
    # Use default queue for all tasks (simplifies worker setup)
    task_default_queue="default",
    task_create_missing_queues=True,
)

# Task states
class TaskStatus:
    PENDING = "PENDING"
    STARTED = "STARTED"
    RUNNING = "RUNNING"
    SUCCESS = "SUCCESS"
    FAILURE = "FAILURE"
    REVOKED = "REVOKED"
