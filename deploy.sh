#!/bin/bash

# Gatto API Deployment Script for Fly.io
# This script provides two deployment options to avoid MANIFEST_UNKNOWN errors

set -e

APP_NAME="gatto-api"
REGION="cdg"

echo "🚀 Gatto API Fly.io Deployment Script"
echo "======================================"

# Check if flyctl is installed
if ! command -v flyctl &> /dev/null; then
    echo "❌ flyctl is not installed. Please install it first:"
    echo "   curl -L https://fly.io/install.sh | sh"
    exit 1
fi

# Check if user is logged in
if ! flyctl auth whoami &> /dev/null; then
    echo "❌ You are not logged in to Fly.io"
    echo "   Run: flyctl auth login"
    exit 1
fi

echo "🔍 Current directory: $(pwd)"
echo "📋 App: $APP_NAME"
echo "🌍 Region: $REGION"
echo ""

# Option selection
echo "Choose deployment method:"
echo "1) Auto build & deploy (recommended - avoids MANIFEST_UNKNOWN)"
echo "2) Manual build & push, then deploy"
echo "3) Just deploy (if app already exists)"
echo ""
read -p "Enter your choice (1-3): " choice

case $choice in
    1)
        echo "🔨 Option 1: Auto build & deploy"
        echo "This method lets Fly.io handle building and pushing the image."
        echo ""
        
        # Create app if it doesn't exist
        if ! flyctl apps list | grep -q "$APP_NAME"; then
            echo "📱 Creating new app..."
            flyctl launch --name "$APP_NAME" --region "$REGION" --no-deploy
        fi
        
        echo "🚀 Deploying with auto build..."
        flyctl deploy
        ;;
        
    2)
        echo "🔨 Option 2: Manual build & push"
        echo "This method builds locally and pushes to Fly registry."
        echo ""
        
        # Authenticate Docker with Fly registry
        echo "🔐 Authenticating Docker with Fly registry..."
        flyctl auth docker
        
        # Get Git commit hash for tagging
        TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
        IMAGE_NAME="registry.fly.io/$APP_NAME:$TAG"
        
        echo "🏗️  Building image: $IMAGE_NAME"
        docker buildx build -t "$IMAGE_NAME" --push .
        
        echo "🚀 Deploying with specific image..."
        flyctl deploy -i "$IMAGE_NAME"
        ;;
        
    3)
        echo "🚀 Option 3: Simple deploy"
        flyctl deploy
        ;;
        
    *)
        echo "❌ Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "✅ Deployment completed!"
echo ""
echo "🔍 Checking deployment status..."
flyctl status

echo ""
echo "📊 Recent logs:"
flyctl logs --limit 20

echo ""
echo "🌐 Your app should be available at: https://$APP_NAME.fly.dev"
echo "🏥 Health check: https://$APP_NAME.fly.dev/health"
echo "🔍 API endpoints: https://$APP_NAME.fly.dev/v1/poi?limit=1"