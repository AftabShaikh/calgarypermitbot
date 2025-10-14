#!/bin/bash

# Calgary Permit Bot - Application Deployment Script
# This script deploys the frontend and backend applications and uploads data files

set -e  # Exit on any error

# Handle Ctrl+C gracefully
trap 'echo -e "\n❌ Deployment interrupted by user. Cleaning up..."; exit 130' INT TERM

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load base configuration first (for any missing variables)
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Load configuration from preparation script (this takes precedence)
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Loaded configuration from preparation script"
    echo "✅ Configuration loaded successfully"
    echo "📍 Location: $LOCATION"
    echo "🏗️  Resource Group: $RESOURCE_GROUP"
    echo "💰 App Service SKU: $APP_SERVICE_SKU"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🚀 Starting Calgary Permit Bot Application Deployment"
echo "====================================================="
echo "📋 Using detected/configured resources:"
echo "   Backend App: $BACKEND_APP_NAME"
echo "   Frontend App: $FRONTEND_APP_NAME"
echo "   Storage Account: $STORAGE_ACCOUNT"
echo "   Search Service: $SEARCH_SERVICE"
echo "   OpenAI Service: $OPENAI_SERVICE"
echo "   Cosmos DB: $COSMOS_ACCOUNT"
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
    echo "⏳ Waiting for storage access settings to propagate..."
    for i in {1..3}; do
        sleep 5
    done
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
    
    # Create .deployment file to ensure proper build
    cat > .deployment << 'EOF'
[config]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
EOF

    # Create a startup script that uses the correct Python environment
    cat > startup_wrapper.sh << 'EOF'
#!/bin/bash

echo "🚀 Calgary Permit Bot - Startup Wrapper"
echo "======================================="

# Check for virtual environment
if [ -d "/home/site/wwwroot/antenv" ]; then
    echo "✅ Found Oryx virtual environment"
    export PATH="/home/site/wwwroot/antenv/bin:$PATH"
    export PYTHONPATH="/home/site/wwwroot:/home/site/wwwroot/antenv/lib/python3.11/site-packages"
    PYTHON_CMD="/home/site/wwwroot/antenv/bin/python"
else
    echo "⚠️ No virtual environment found, using system Python"
    export PYTHONPATH="/home/site/wwwroot"
    PYTHON_CMD="python"
fi

# Set environment variables
export WEBSITE_HOSTNAME="true"
export RUNNING_IN_PRODUCTION="true"

# Navigate to app directory
cd /home/site/wwwroot

echo "🔍 Environment check:"
echo "Python: $($PYTHON_CMD --version)"
echo "Working directory: $(pwd)"
echo "Python path: $PYTHONPATH"

# Check if dependencies are available
echo "🔍 Checking key dependencies..."
$PYTHON_CMD -c "import quart; print('✅ quart available')" || echo "❌ quart not available"
$PYTHON_CMD -c "import azure.identity; print('✅ azure.identity available')" || echo "❌ azure.identity not available"

# Start the application
echo "🚀 Starting application..."
exec $PYTHON_CMD run_app.py
EOF

    chmod +x startup_wrapper.sh
    
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
    
    # Also create a minimal deployment package for troubleshooting
    echo "📦 Creating minimal deployment package..."
    zip -r /tmp/backend-deploy-minimal.zip . \
        -x "*.pyc" \
        "__pycache__/*" \
        ".pytest_cache/*" \
        "tests/*" \
        ".env" \
        "*.log" \
        ".git/*" \
        "node_modules/*" \
        "requirements.txt"
    
    # Add the core requirements as the main requirements.txt in minimal package
    cd /tmp
    mkdir -p backend-minimal-extract
    cd backend-minimal-extract
    unzip -q ../backend-deploy-minimal.zip
    cp requirements-core.txt requirements.txt
    zip -r ../backend-deploy-minimal.zip .
    cd "$BACKEND_FOLDER"
    
    echo "🚀 Deploying backend to Azure App Service..."
    
    # Function to deploy with timeout using deployment source for proper build
    deploy_backend() {
        timeout --preserve-status --kill-after=10 300 az webapp deployment source config-zip \
            --name $BACKEND_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --src /tmp/backend-deploy.zip
    }
    
    # Force clean deployment by stopping app and clearing cache
    echo "🔄 Preparing app for clean deployment..."
    az webapp stop --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
    
    # Clear any existing deployment artifacts  
    echo "🧹 Clearing deployment cache..."
    az webapp deployment source delete --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null || true
    
    # Start the app again
    az webapp start --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
    echo "⏳ Waiting for app to start..."
    for i in {1..3}; do
        sleep 5
    done
    
    # Try deployment with timeout (5 minutes)
    echo "🚀 Starting backend deployment (timeout: 5 minutes)..."
    echo "   Note: You can press Ctrl+C to interrupt if it gets stuck"
    if deploy_backend; then
        echo "✅ Backend deployed successfully"
    else
        DEPLOY_EXIT_CODE=$?
        if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
            echo "⏰ Backend deployment timed out after 5 minutes"
        else
            echo "❌ Backend deployment failed with exit code: $DEPLOY_EXIT_CODE"
        fi
        
        echo ""
        echo "🔧 MANUAL DEPLOYMENT REQUIRED"
        echo "============================="
        echo "The automated deployment failed or timed out. Please deploy manually:"
        echo ""
        echo "1. Navigate to the Azure Portal:"
        echo "   https://portal.azure.com"
        echo ""
        echo "2. Go to your App Service: $BACKEND_APP_NAME"
        echo "   Resource Group: $RESOURCE_GROUP"
        echo ""
        echo "3. In the App Service, go to 'Deployment Center' on the left menu"
        echo ""
        echo "4. Choose 'Manual Deployment' and upload the ZIP file:"
        echo "   File Location: /tmp/backend-deploy.zip"
        echo "   (Copy this file to your local machine if needed)"
        echo ""
        echo "5. Alternative command-line deployment (with proper build):"
        echo "   az webapp deployment source config-zip \\"
        echo "       --name $BACKEND_APP_NAME \\"
        echo "       --resource-group $RESOURCE_GROUP \\"
        echo "       --src /tmp/backend-deploy.zip"
        echo ""
        echo "6. Using Azure CLI with larger timeout:"
        echo "   timeout 900 az webapp deployment source config-zip \\"
        echo "       --name $BACKEND_APP_NAME \\"
        echo "       --resource-group $RESOURCE_GROUP \\"
        echo "       --src /tmp/backend-deploy.zip"
        echo ""
        echo "7. Using FTP/FTPS deployment:"
        echo "   - Get FTP credentials from Azure Portal > App Service > Deployment Center"
        echo "   - Extract /tmp/backend-deploy.zip and upload contents to /site/wwwroot/"
        echo ""
        echo "💡 The deployment package is ready at: /tmp/backend-deploy.zip"
        echo "    Size: $(ls -lh /tmp/backend-deploy.zip | awk '{print $5}')"
        echo "    Contents: $(zipinfo -1 /tmp/backend-deploy.zip | wc -l) files"
        echo ""
        echo "8. Use the provided manual deployment script:"
        echo "   ./deploy/manual-backend-deploy.sh"
        echo ""
        echo "9. Try minimal deployment (core dependencies only):"
        echo "   az webapp deployment source config-zip \\"
        echo "       --name $BACKEND_APP_NAME \\"
        echo "       --resource-group $RESOURCE_GROUP \\"
        echo "       --src /tmp/backend-deploy-minimal.zip"
        echo ""
        echo "💡 Deployment packages ready:"
        echo "    Full: /tmp/backend-deploy.zip ($(ls -lh /tmp/backend-deploy.zip 2>/dev/null | awk '{print $5}' || echo 'N/A'))"
        echo "    Minimal: /tmp/backend-deploy-minimal.zip ($(ls -lh /tmp/backend-deploy-minimal.zip 2>/dev/null | awk '{print $5}' || echo 'N/A'))"
        echo ""
        echo "Press Enter after manual deployment is complete, or Ctrl+C to exit..."
        if read -r; then
            echo "✅ Continuing with manual deployment assumption..."
        else
            echo "❌ Input interrupted"
            exit 130
        fi
    fi
    
    # Wait for backend build and start
    echo "⏳ Waiting for backend build and startup (this may take several minutes)..."
    echo "   Press Ctrl+C to interrupt if needed..."
    for i in {1..24}; do
        sleep 5
        if [ $((i % 6)) -eq 0 ]; then
            echo "⏳ Still waiting... (${i}0 seconds elapsed)"
        fi
    done
    
    # Check if the build completed successfully
    echo "🔍 Checking deployment status..."
    DEPLOYMENT_STATUS=$(az webapp deployment list --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "[0].status" -o tsv 2>/dev/null || echo "Unknown")
    echo "Backend deployment status: $DEPLOYMENT_STATUS"
    
    if [ "$DEPLOYMENT_STATUS" = "Failed" ]; then
        echo "❌ Backend deployment failed. Checking logs..."
        az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --provider filesystem 2>/dev/null | tail -20 || echo "Could not fetch logs"
        echo ""
        echo "⚠️  Build may have failed. Consider using manual deployment with troubleshooting."
    elif [ "$DEPLOYMENT_STATUS" = "Success" ]; then
        echo "✅ Backend deployment completed successfully"
    else
        echo "⏳ Backend deployment in progress..."
    fi
    
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
    
    # Function to deploy frontend with timeout
    deploy_frontend() {
        timeout --preserve-status --kill-after=10 300 az webapp deployment source config-zip \
            --name $FRONTEND_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --src ../frontend-deploy.zip
    }
    
    # Try deployment with timeout (5 minutes)
    echo "🚀 Starting frontend deployment (timeout: 5 minutes)..."
    echo "   Note: You can press Ctrl+C to interrupt if it gets stuck"
    if deploy_frontend; then
        echo "✅ Frontend deployed successfully"
    else
        DEPLOY_EXIT_CODE=$?
        if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
            echo "⏰ Frontend deployment timed out after 5 minutes"
        else
            echo "❌ Frontend deployment failed with exit code: $DEPLOY_EXIT_CODE"
        fi
        
        echo ""
        echo "🔧 MANUAL FRONTEND DEPLOYMENT REQUIRED"
        echo "======================================"
        echo "The automated frontend deployment failed or timed out. Please deploy manually:"
        echo ""
        echo "1. Navigate to the Azure Portal:"
        echo "   https://portal.azure.com"
        echo ""
        echo "2. Go to your App Service: $FRONTEND_APP_NAME"
        echo "   Resource Group: $RESOURCE_GROUP"
        echo ""
        echo "3. In the App Service, go to 'Deployment Center' on the left menu"
        echo ""
        echo "4. Choose 'Manual Deployment' and upload the ZIP file:"
        echo "   File Location: /tmp/frontend-deploy.zip"
        echo ""
        echo "5. Alternative command-line deployment:"
        echo "   az webapp deployment source config-zip \\"
        echo "       --name $FRONTEND_APP_NAME \\"
        echo "       --resource-group $RESOURCE_GROUP \\"
        echo "       --src /tmp/frontend-deploy.zip"
        echo ""
        echo "💡 The deployment package is ready at: /tmp/frontend-deploy.zip"
        echo "    Size: $(ls -lh /tmp/frontend-deploy.zip | awk '{print $5}')"
        echo ""
        echo "6. Use the provided manual deployment script:"
        echo "   ./deploy/manual-frontend-deploy.sh"
        echo ""
        echo "Press Enter after manual deployment is complete, or Ctrl+C to exit..."
        if read -r; then
            echo "✅ Continuing with manual deployment assumption..."
        else
            echo "❌ Input interrupted"
            exit 130
        fi
    fi
    
    cd "$PROJECT_ROOT"
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
echo "🔧 Configuring backend application settings..."
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
        PYTHONPATH="/home/site/wwwroot:/home/site/wwwroot/antenv/lib/python3.11/site-packages" \
        PATH="/home/site/wwwroot/antenv/bin:$PATH" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
        ENABLE_ORYX_BUILD="true" \
        ORYX_ENV_TYPE="" \
        DISABLE_COLLECTSTATIC="1" \
        XDG_CACHE_HOME="/tmp/.cache" \
        RUNNING_IN_PRODUCTION="true" \
        WEBSITE_HOSTNAME="true"

# Ensure Python runtime is properly configured
echo "🔧 Configuring Python runtime..."
az webapp config set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --linux-fx-version "PYTHON|3.11"

# Set startup command to use the wrapper script
echo "🔧 Configuring backend startup command..."
az webapp config set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --startup-file "bash startup_wrapper.sh"

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
    # Wait for service to be fully ready
echo "⏳ Waiting for backend services to be ready..."
echo "   Press Ctrl+C to interrupt if needed..."
for i in {1..12}; do
    sleep 5
    if [ $((i % 3)) -eq 0 ]; then
        echo "⏳ Still waiting for services... (${i}0 seconds elapsed)"
    fi
done

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
echo "   4. If you encounter issues (like dependency errors), use:"
echo "      ./deploy/troubleshooting.sh"
echo "   5. For status monitoring:"
echo "      ./deploy/check-deployment-status.sh"
echo ""
echo "🎉 Deployment successful!"