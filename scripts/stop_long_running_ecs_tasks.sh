#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-assurance-testing}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-12}"
AWS_REGION="${AWS_REGION:-eu-west-2}"
DRY_RUN="${DRY_RUN:-false}"

now=$(date -u +%s)
max_age_seconds=$((MAX_AGE_HOURS * 3600))

echo "Checking for tasks in cluster '${CLUSTER_NAME}' running longer than ${MAX_AGE_HOURS} hours..."

task_arns=$(aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --desired-status RUNNING \
  --query "taskArns[]" \
  --output text)

if [ -z "$task_arns" ]; then
  echo "No running tasks found."
  exit 0
fi

stopped_count=0

for task_arn in $task_arns; do
  started_at=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --tasks "$task_arn" \
    --query "tasks[0].startedAt" \
    --output text)

  if [ "$started_at" = "None" ] || [ -z "$started_at" ]; then
    echo "Task ${task_arn} has no startedAt timestamp, skipping."
    continue
  fi

  started_epoch=$(date -u -d "$started_at" +%s)
  age_seconds=$((now - started_epoch))
  age_hours=$(echo "scale=1; $age_seconds / 3600" | bc)

  if [ "$age_seconds" -gt "$max_age_seconds" ]; then
    echo "Task ${task_arn} has been running for ${age_hours}h (started ${started_at})."

    if [ "$DRY_RUN" = "true" ]; then
      echo "  [DRY RUN] Would stop task."
    else
      aws ecs stop-task \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --task "$task_arn" \
        --reason "Automatically stopped: running longer than ${MAX_AGE_HOURS} hours" \
        --output text > /dev/null
      echo "  Stopped."
    fi

    stopped_count=$((stopped_count + 1))
  else
    echo "Task ${task_arn} has been running for ${age_hours}h: No action."
  fi
done

echo "Done. ${stopped_count} task(s) stopped."
