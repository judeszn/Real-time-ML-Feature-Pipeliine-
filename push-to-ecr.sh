#!/bin/bash
# AWS ECR Push Script
# Run this once your user has ECR permissions

set -e

AWS_ACCOUNT_ID="255638996405"
AWS_REGION="us-east-1"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

echo "🔐 AWS ECR Push Script"
echo "===================="
echo ""

# Check AWS credentials
echo "✓ Checking AWS credentials..."
aws sts get-caller-identity --region $AWS_REGION > /dev/null || {
    echo "✗ AWS credentials not configured"
    exit 1
}

echo "✓ AWS credentials valid"
echo ""

# Login to ECR
echo "🔓 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

echo "✓ Logged into ECR"
echo ""

# Build images
SERVICES=("event-simulator" "ingestion-service" "feature-processor")

for SERVICE in "${SERVICES[@]}"; do
    echo "🔨 Building $SERVICE..."
    
    if [ "$SERVICE" = "event-simulator" ]; then
        DOCKERFILE_PATH="./event-simulator/Dockerfile"
        BUILD_CONTEXT="./event-simulator"
    elif [ "$SERVICE" = "ingestion-service" ]; then
        DOCKERFILE_PATH="./ingestion-service/Dockerfile"
        BUILD_CONTEXT="./ingestion-service"
    elif [ "$SERVICE" = "feature-processor" ]; then
        DOCKERFILE_PATH="./feature-processor/Dockerfile"
        BUILD_CONTEXT="./feature-processor"
    fi
    
    docker build -t $ECR_REGISTRY/$SERVICE:latest -f $DOCKERFILE_PATH $BUILD_CONTEXT
    echo "✓ Built $SERVICE"
done

echo ""
echo "📤 Pushing images to ECR..."
echo ""

for SERVICE in "${SERVICES[@]}"; do
    echo "Pushing $SERVICE..."
    docker push $ECR_REGISTRY/$SERVICE:latest
    echo "✓ Pushed $SERVICE"
done

echo ""
echo "✅ All images pushed to ECR!"
echo ""
echo "Images:"
for SERVICE in "${SERVICES[@]}"; do
    echo "  - $ECR_REGISTRY/$SERVICE:latest"
done
echo ""
echo "Next steps:"
echo "1. Update k8s manifests with image URIs"
echo "2. Run: terraform apply -var-file=environments/dev.tfvars"
echo "3. Deploy: kubectl apply -f k8s/"
