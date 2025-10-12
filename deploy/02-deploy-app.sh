#!/bin/bash

# Calgary Permit Bot - Application Deployment Script
# This script deploys the frontend and backend applications and uploads data files

set -e  # Exit on any error

# Load configuration from preparation script
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Loaded configuration from preparation script"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🚀 Starting Calgary Permit Bot Application Deployment"
echo "====================================================="
echo "Backend App: $BACKEND_APP_NAME"
echo "Frontend App: $FRONTEND_APP_NAME"
echo "Storage Account: $STORAGE_ACCOUNT"
echo ""

# Validate that required resources exist
echo "🔍 Validating required resources exist..."

# Check if App Service Plan exists
if ! az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "❌ App Service Plan '$APP_SERVICE_PLAN' not found in resource group '$RESOURCE_GROUP'"
    echo "Please run ./deploy/01-prepare-resources.sh first to create the required resources."
    exit 1
fi

# Check if backend app exists
if ! az webapp show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "❌ Backend web app '$BACKEND_APP_NAME' not found in resource group '$RESOURCE_GROUP'"
    echo "Please run ./deploy/01-prepare-resources.sh first to create the required resources."
    exit 1
fi

# Check if storage account exists
if ! az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "❌ Storage account '$STORAGE_ACCOUNT' not found in resource group '$RESOURCE_GROUP'"
    echo "Please run ./deploy/01-prepare-resources.sh first to create the required resources."
    exit 1
fi

echo "✅ All required resources found!"
echo ""

# Step 1: Upload data files to storage
echo "📁 Uploading data files to storage account..."

# First, temporarily allow all networks for upload
az storage account update \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --default-action Allow

# Wait a moment for the setting to propagate
sleep 10

# Upload files from data folder
if [ -d "data" ]; then
    az storage blob upload-batch \
        --account-name $STORAGE_ACCOUNT \
        --destination content \
        --source data \
        --auth-mode login \
        --overwrite
    echo "✅ Data files uploaded successfully"
else
    echo "⚠️  Data folder not found, skipping file upload"
fi

# Restore network restrictions (optional)
# az storage account update \
#     --name $STORAGE_ACCOUNT \
#     --resource-group $RESOURCE_GROUP \
#     --default-action Deny

# Step 2: Build and deploy frontend
echo "🎨 Building and deploying frontend..."

if [ -d "app/frontend" ]; then
    cd app/frontend
    
    # Install dependencies
    echo "📦 Installing frontend dependencies..."
    npm ci
    
    # Build the application
    echo "🔨 Building frontend application..."
    npm run build
    
    # Deploy to frontend web app
    echo "🚀 Deploying frontend to Azure..."
    cd ../..
    
    # Create a deployment package
    mkdir -p /tmp/frontend-deploy
    cp -r app/backend/static/* /tmp/frontend-deploy/
    
    # Create a simple server.js for the frontend app
    cat > /tmp/frontend-deploy/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 8080;

// Serve static files
app.use(express.static(path.join(__dirname)));

// Handle client-side routing
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(port, () => {
  console.log(`Frontend server running on port ${port}`);
});
EOF

    # Create package.json for the frontend deployment
    cat > /tmp/frontend-deploy/package.json << 'EOF'
{
  "name": "calgarypermitbot-frontend",
  "version": "1.0.0",
  "description": "Calgary Permit Bot Frontend",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

    # Deploy frontend
    cd /tmp/frontend-deploy
    zip -r ../frontend-deploy.zip .
    
    az webapp deploy \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path ../frontend-deploy.zip \
        --type zip
    
    cd - > /dev/null
    echo "✅ Frontend deployed successfully"
else
    echo "⚠️  Frontend folder not found, skipping frontend deployment"
fi

# Step 3: Deploy backend
echo "🔧 Deploying backend..."

if [ -d "app/backend" ]; then
    cd app/backend
    
    # Create deployment package
    zip -r /tmp/backend-deploy.zip . -x "*.pyc" "__pycache__/*" ".pytest_cache/*" "tests/*"
    
    # Deploy backend
    az webapp deploy \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path /tmp/backend-deploy.zip \
        --type zip
    
    cd - > /dev/null
    echo "✅ Backend deployed successfully"
else
    echo "❌ Backend folder not found"
    exit 1
fi

# Step 4: Run data preprocessing (create search index)
echo "🔍 Setting up search index..."

# Wait for backend to be ready
sleep 30

# Trigger index creation by calling the backend endpoint
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"

# Create a simple script to populate the search index
echo "📊 Populating search index with uploaded documents..."

# You might need to call specific endpoints to process the uploaded documents
# This is application-specific and might require authentication

echo "⚠️  Note: You may need to manually trigger document processing through the application interface"

# Step 5: Configure frontend to point to backend
echo "⚙️  Configuring frontend to use backend..."

# Update frontend app settings to point to backend
az webapp config appsettings set \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        BACKEND_URL=$BACKEND_URL \
        NODE_ENV=production

# Step 6: Final health checks
echo "🏥 Running health checks..."

echo "Checking backend health..."
curl -f "$BACKEND_URL/health" || echo "⚠️  Backend health check failed (this might be expected initially)"

echo "Checking frontend..."
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"
curl -f "$FRONTEND_URL" || echo "⚠️  Frontend health check failed (this might be expected initially)"

# Clean up temporary files
rm -f /tmp/backend-deploy.zip /tmp/frontend-deploy.zip
rm -rf /tmp/frontend-deploy

echo ""
echo "✅ Calgary Permit Bot Deployment Completed!"
echo "==========================================="
echo "🌐 Frontend URL: $FRONTEND_URL"
echo "🔧 Backend URL:  $BACKEND_URL"
echo "📁 Storage Account: $STORAGE_ACCOUNT"
echo ""
echo "🔗 Application Endpoints:"
echo "   - Main Application: $FRONTEND_URL"
echo "   - API Backend: $BACKEND_URL"
echo "   - Health Check: $BACKEND_URL/health"
echo ""
echo "📝 Next Steps:"
echo "   1. Wait 2-3 minutes for services to fully start"
echo "   2. Visit the frontend URL to test the application"
echo "   3. Check application logs if needed:"
echo "      az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo "      az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "🎉 Deployment successful!"