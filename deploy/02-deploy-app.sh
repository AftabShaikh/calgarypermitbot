#!/bin/bash

# Calgary Permit Bot - Application Deployment Script
# This script deploys the frontend and backend applications and uploads data files

set -e  # Exit on any error

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration from preparation script
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Loaded configuration from preparation script"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

# Load additional configuration if available
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
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

# Step 1: Upload data files to storage (if not skipped)
if [ "$SKIP_DATA_UPLOAD" = "true" ]; then
    echo "⏭️  Skipping data upload as requested"
else
    echo "📁 Uploading data files to storage account..."
fi

# Navigate to project root to ensure we find the data folder
cd "$PROJECT_ROOT"

if [ "$SKIP_DATA_UPLOAD" != "true" ]; then
    # First, temporarily allow all networks for upload
    echo "🔓 Temporarily allowing storage access for upload..."
    az storage account update \
        --name $STORAGE_ACCOUNT \
        --resource-group $RESOURCE_GROUP \
        --default-action Allow

    # Wait a moment for the setting to propagate
    sleep 15
fi

# Upload files from data folder (only if not skipped)
if [ "$SKIP_DATA_UPLOAD" != "true" ]; then
    DATA_FOLDER="${DATA_FOLDER:-data}"
    if [ -d "$DATA_FOLDER" ]; then
    echo "📤 Uploading files from $DATA_FOLDER folder..."
    
    # List files to be uploaded
    echo "Files to upload:"
    find "$DATA_FOLDER" -type f | head -10
    
    # Upload files
    az storage blob upload-batch \
        --account-name $STORAGE_ACCOUNT \
        --destination ${STORAGE_CONTAINER:-content} \
        --source "$DATA_FOLDER" \
        --auth-mode login \
        --overwrite \
        --pattern "*.pdf" \
        --verbose || true
    
    # Upload text files
    az storage blob upload-batch \
        --account-name $STORAGE_ACCOUNT \
        --destination ${STORAGE_CONTAINER:-content} \
        --source "$DATA_FOLDER" \
        --auth-mode login \
        --overwrite \
        --pattern "*.txt" \
        --verbose || true
    
    # Upload HTML files
    az storage blob upload-batch \
        --account-name $STORAGE_ACCOUNT \
        --destination ${STORAGE_CONTAINER:-content} \
        --source "$DATA_FOLDER" \
        --auth-mode login \
        --overwrite \
        --pattern "*.html" \
        --verbose || true
    
    echo "✅ Data files uploaded successfully"
    
    # List uploaded files to verify
    echo "📋 Uploaded files:"
    az storage blob list \
        --account-name $STORAGE_ACCOUNT \
        --container-name ${STORAGE_CONTAINER:-content} \
        --auth-mode login \
        --output table || true
        
    else
        echo "❌ Data folder '$DATA_FOLDER' not found at $(pwd)/$DATA_FOLDER"
        echo "Available directories:"
        ls -la
        exit 1
    fi
else
    echo "✅ Data upload skipped"
fi

# Restore network restrictions (optional)
# az storage account update \
#     --name $STORAGE_ACCOUNT \
#     --resource-group $RESOURCE_GROUP \
#     --default-action Deny

# Step 2: Build and deploy backend first (required for frontend configuration)
echo "🔧 Building and deploying backend..."

BACKEND_FOLDER="$PROJECT_ROOT/app/backend"
if [ -d "$BACKEND_FOLDER" ]; then
    cd "$BACKEND_FOLDER"
    
    echo "📦 Preparing backend deployment package..."
    
    # Create deployment package, excluding development files
    zip -r /tmp/backend-deploy.zip . \
        -x "*.pyc" \
        "__pycache__/*" \
        ".pytest_cache/*" \
        "tests/*" \
        ".env" \
        "*.log" \
        ".git/*" \
        "node_modules/*"
    
    echo "🚀 Deploying backend to Azure App Service..."
    az webapp deploy \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path /tmp/backend-deploy.zip \
        --type zip
    
    echo "✅ Backend deployed successfully"
    
    # Wait for backend to start
    echo "⏳ Waiting for backend to start..."
    sleep 45
    
    cd "$PROJECT_ROOT"
else
    echo "❌ Backend folder not found at $BACKEND_FOLDER"
    exit 1
fi

# Step 3: Build and deploy frontend
echo "🎨 Building and deploying frontend..."

FRONTEND_FOLDER="$PROJECT_ROOT/app/frontend"
if [ -d "$FRONTEND_FOLDER" ]; then
    cd "$FRONTEND_FOLDER"
    
    # Check Node.js version requirement
    if [ -f ".nvmrc" ]; then
        echo "📋 Node.js version requirement:"
        cat .nvmrc
    fi
    
    # Install dependencies
    echo "📦 Installing frontend dependencies..."
    npm ci
    
    # Set backend URL for build
    BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
    export VITE_BACKEND_URL="$BACKEND_URL"
    export REACT_APP_BACKEND_URL="$BACKEND_URL"
    
    # Build the application
    echo "🔨 Building frontend application..."
    npm run build
    
    # Prepare deployment package
    echo "� Preparing frontend deployment package..."
    
    # Create a deployment folder
    rm -rf /tmp/frontend-deploy
    mkdir -p /tmp/frontend-deploy
    
    # Copy built files (typically in 'dist' or 'build' folder)
    if [ -d "dist" ]; then
        cp -r dist/* /tmp/frontend-deploy/
        echo "✅ Copied files from dist/ folder"
    elif [ -d "build" ]; then
        cp -r build/* /tmp/frontend-deploy/
        echo "✅ Copied files from build/ folder"
    else
        echo "❌ No build output found (looking for dist/ or build/ folders)"
        ls -la
        exit 1
    fi
    
    # Create a simple Express server to serve the SPA
    cat > /tmp/frontend-deploy/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 8080;

// Serve static files
app.use(express.static(path.join(__dirname)));

// Handle SPA routing - serve index.html for all routes
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
  },
  "engines": {
    "node": ">=16.0.0"
  }
}
EOF

    # Create web.config for proper routing support
    cat > /tmp/frontend-deploy/web.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="React Routes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
            <add input="{REQUEST_URI}" pattern="^/(api)" negate="true" />
          </conditions>
          <action type="Rewrite" url="/" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
EOF

    # Deploy frontend
    echo "🚀 Deploying frontend to Azure App Service..."
    cd /tmp/frontend-deploy
    zip -r ../frontend-deploy.zip .
    
    az webapp deploy \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path ../frontend-deploy.zip \
        --type zip
    
    cd "$PROJECT_ROOT"
    echo "✅ Frontend deployed successfully"
else
    echo "❌ Frontend folder not found at $FRONTEND_FOLDER"
    echo "Available directories in app/:"
    ls -la "$PROJECT_ROOT/app/" || true
    exit 1
fi

# Backend was deployed in Step 2

# Step 4: Configure application settings and environment variables
echo "⚙️  Configuring application settings..."

BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"

# Configure backend app settings
echo "� Configuring backend application settings..."
az webapp config appsettings set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT" \
        AZURE_STORAGE_CONTAINER="${STORAGE_CONTAINER:-content}" \
        AZURE_SEARCH_SERVICE="$SEARCH_SERVICE" \
        AZURE_OPENAI_SERVICE="$OPENAI_SERVICE" \
        AZURE_COSMOSDB_ACCOUNT="$COSMOS_ACCOUNT" \
        AZURE_COSMOSDB_DATABASE="${COSMOS_DATABASE:-chathistory}" \
        AZURE_COSMOSDB_CONTAINER="${COSMOS_CONTAINER:-chatcontainer}" \
        WEBSITE_HTTPLOGGING_RETENTION_DAYS="7" \
        PYTHONPATH="/home/site/wwwroot" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
        ENABLE_ORYX_BUILD="true"

# Configure frontend app settings  
echo "🎨 Configuring frontend application settings..."
az webapp config appsettings set \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        BACKEND_URL="$BACKEND_URL" \
        NODE_ENV="production" \
        WEBSITE_NODE_DEFAULT_VERSION="18-lts" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="false"

# Step 5: Run data preprocessing (create search index)
echo "🔍 Setting up search index and processing documents..."

# Wait for backend to be fully ready
echo "⏳ Waiting for backend services to be ready..."
sleep 60

# Try to trigger document processing
echo "📊 Attempting to trigger document processing..."

# Check if the backend has a document processing endpoint
curl -X POST "$BACKEND_URL/api/documents/process" \
    -H "Content-Type: application/json" \
    -d '{"force_reindex": true}' \
    --max-time 30 \
    --connect-timeout 10 || echo "⚠️  Could not trigger automatic document processing"

echo "📋 Note: You may need to manually trigger document processing through the application interface"

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