#!/bin/bash

# Deployment validation script
set -e

CLUSTER_NAME=${1:-"cicd-cluster"}
SERVICE_NAME=${2:-"cicd-service"}
EXPECTED_COUNT=${3:-2}
TIMEOUT=${4:-600}  # 10 minutes

echo "🔍 Validating ECS deployment..."
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Expected task count: $EXPECTED_COUNT"

# Function to check service status
check_service_status() {
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0].[runningCount,pendingCount,desiredCount,deployments[0].status]' \
        --output text
}

# Function to get task health
check_task_health() {
    aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --query 'taskArns' \
        --output text | while read task_arn; do
        if [ "$task_arn" != "None" ] && [ "$task_arn" != "" ]; then
            aws ecs describe-tasks \
                --cluster "$CLUSTER_NAME" \
                --tasks "$task_arn" \
                --query 'tasks[0].[lastStatus,healthStatus]' \
                --output text
        fi
    done
}

# Wait for deployment to stabilize
echo "⏳ Waiting for deployment to stabilize..."
start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $TIMEOUT ]; then
        echo "❌ Deployment validation timed out after ${TIMEOUT}s"
        exit 1
    fi
    
    # Get service status
    status_info=$(check_service_status)
    running_count=$(echo "$status_info" | cut -f1)
    pending_count=$(echo "$status_info" | cut -f2)
    desired_count=$(echo "$status_info" | cut -f3)
    deployment_status=$(echo "$status_info" | cut -f4)
    
    echo "Status: Running=$running_count, Pending=$pending_count, Desired=$desired_count, Deployment=$deployment_status"
    
    # Check if deployment is complete
    if [ "$running_count" -eq "$EXPECTED_COUNT" ] && [ "$pending_count" -eq "0" ] && [ "$deployment_status" = "PRIMARY" ]; then
        echo "✅ Deployment completed successfully"
        break
    fi
    
    sleep 30
done

# Validate task health
echo "🏥 Checking task health..."
healthy_tasks=0
total_tasks=0

while IFS=$'\t' read -r status health; do
    if [ "$status" != "" ]; then
        total_tasks=$((total_tasks + 1))
        echo "Task status: $status, health: $health"
        
        if [ "$status" = "RUNNING" ] && ([ "$health" = "HEALTHY" ] || [ "$health" = "UNKNOWN" ]); then
            healthy_tasks=$((healthy_tasks + 1))
        fi
    fi
done < <(check_task_health)

echo "Healthy tasks: $healthy_tasks/$total_tasks"

if [ "$healthy_tasks" -eq "$EXPECTED_COUNT" ]; then
    echo "✅ All tasks are healthy"
else
    echo "❌ Not all tasks are healthy ($healthy_tasks/$EXPECTED_COUNT)"
    exit 1
fi

# Test application endpoint (if ALB is configured)
if [ ! -z "$ALB_DNS_NAME" ]; then
    echo "🌐 Testing application endpoint..."
    
    for i in {1..5}; do
        if curl -f -s "http://$ALB_DNS_NAME/health" > /dev/null; then
            echo "✅ Application health check passed"
            break
        else
            echo "⏳ Attempt $i/5 - waiting for application to be ready..."
            sleep 10
        fi
        
        if [ $i -eq 5 ]; then
            echo "❌ Application health check failed"
            exit 1
        fi
    done
fi

echo "🎉 Deployment validation completed successfully!"