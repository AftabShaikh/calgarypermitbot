#!/bin/bash

# Manual Backend Deployment Script for Calgary Permit Bot
# Use this script if the automated deployment times out or fails

set -e  # Exit on any error

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Loaded configuration from preparation script"
elif [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    echo "📋 Loaded configuration from config.sh"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🔧 Manual Backend Deployment"
echo "============================="
echo "Backend App: $BACKEND_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Navigate to backend folder
BACKEND_FOLDER="$PROJECT_ROOT/app/backend"
if [ ! -d "$BACKEND_FOLDER" ]; then
    echo "❌ Backend folder not found at $BACKEND_FOLDER"
    exit 1
fi

cd "$BACKEND_FOLDER"

echo "📦 Creating deployment package..."

# Create deployment package
DEPLOY_ZIP="/tmp/backend-manual-deploy.zip"
zip -r "$DEPLOY_ZIP" . \
    -x "*.pyc" \
    "__pycache__/*" \
    ".pytest_cache/*" \
    "tests/*" \
    ".env" \
    "*.log" \
    ".git/*" \
    "node_modules/*"

# Also create minimal deployment with core dependencies
DEPLOY_ZIP_MINIMAL="/tmp/backend-manual-deploy-minimal.zip"
echo "📦 Creating minimal deployment package (core dependencies only)..."
zip -r "$DEPLOY_ZIP_MINIMAL" . \
    -x "*.pyc" \
    "__pycache__/*" \
    ".pytest_cache/*" \
    "tests/*" \
    ".env" \
    "*.log" \
    ".git/*" \
    "node_modules/*" \
    "requirements.txt"

# Add core requirements as main requirements.txt
cd /tmp
mkdir -p backend-manual-minimal-extract
cd backend-manual-minimal-extract
unzip -q ../backend-manual-deploy-minimal.zip
cp requirements-core.txt requirements.txt 2>/dev/null || echo "⚠️ Core requirements file not found, using original"
zip -r ../backend-manual-deploy-minimal.zip .
cd "$BACKEND_FOLDER"

echo "✅ Deployment packages created:"
echo "   Full: $DEPLOY_ZIP ($(ls -lh "$DEPLOY_ZIP" | awk '{print $5}'))"
echo "   Minimal: $DEPLOY_ZIP_MINIMAL ($(ls -lh "$DEPLOY_ZIP_MINIMAL" | awk '{print $5}'))"
echo "📁 Package contents: $(zipinfo -1 "$DEPLOY_ZIP" | wc -l) files"
echo ""

echo "🚀 Deploying to Azure App Service..."
echo "⚠️  This may take 10-20 minutes. Please be patient..."

# Try different deployment methods
echo "Method 1: Standard deployment with extended timeout..."
if timeout 1800 az webapp deploy \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --src-path "$DEPLOY_ZIP" \
    --type zip; then
    echo "✅ Backend deployed successfully!"
else
    DEPLOY_EXIT_CODE=$?
    echo "❌ Standard deployment failed (exit code: $DEPLOY_EXIT_CODE)"
    
    echo ""
    echo "Method 2: Trying deployment with restart..."
    az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
    sleep 30
    
    if timeout 1800 az webapp deploy \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path "$DEPLOY_ZIP" \
        --type zip; then
        echo "✅ Backend deployed successfully after restart!"
    else
        echo "❌ Full deployment failed again, trying minimal deployment..."
        
        if timeout 1800 az webapp deploy \
            --name $BACKEND_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --src-path "$DEPLOY_ZIP_MINIMAL" \
            --type zip; then
            echo "✅ Minimal backend deployment successful!"
            echo "⚠️  Note: Using core dependencies only. You may need to install additional packages later."
        else
            echo "❌ Both deployments failed"
            echo ""
            echo "🔧 ALTERNATIVE DEPLOYMENT METHODS"
            echo "=================================="
            echo ""
            echo "1. Azure Portal Upload:"
            echo "   - Go to: https://portal.azure.com"
            echo "   - Navigate to: $BACKEND_APP_NAME (App Service)"
            echo "   - Go to: Deployment Center → Manual deployment"
            echo "   - Upload: $DEPLOY_ZIP (full) or $DEPLOY_ZIP_MINIMAL (minimal)"
            echo ""
            echo "2. Try minimal deployment manually:"
            echo "   az webapp deploy \\"
            echo "       --name $BACKEND_APP_NAME \\"
            echo "       --resource-group $RESOURCE_GROUP \\"
            echo "       --src-path $DEPLOY_ZIP_MINIMAL \\"
            echo "       --type zip"
            echo ""
            echo "3. Configure App Service settings:"
            echo "   az webapp config appsettings set \\"
            echo "       --name $BACKEND_APP_NAME \\"
            echo "       --resource-group $RESOURCE_GROUP \\"
            echo "       --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true ENABLE_ORYX_BUILD=true"
            echo ""
            echo "4. Set startup command:"
            echo "   az webapp config set \\"
            echo "       --name $BACKEND_APP_NAME \\"
            echo "       --resource-group $RESOURCE_GROUP \\"
            echo "       --startup-file startup.sh"
            echo ""
            exit 1
        fi
    fi
fi

echo ""
echo "🏥 Running health check..."
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
echo "Backend URL: $BACKEND_URL"

# Wait for service to start
echo "⏳ Waiting for service to start..."
sleep 60

# Health check
if curl -f "$BACKEND_URL/health" -m 30; then
    echo "✅ Backend health check passed!"
else
    echo "⚠️  Health check failed (service may still be starting)"
fi

echo ""
echo "🎉 Manual backend deployment completed!"
echo "Backend URL: $BACKEND_URL"
echo ""
echo "📝 Next steps:"
echo "1. Wait 2-3 minutes for the service to fully start"
echo "2. Test the health endpoint: $BACKEND_URL/health"
echo "3. Check logs if needed:"
echo "   az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"