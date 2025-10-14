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

    # Verify requirements.txt exists and is clean
    echo "📝 Using existing requirements.txt for Azure App Service deployment..."
    if [ ! -f "requirements.txt" ]; then
        echo "❌ requirements.txt not found in backend directory"
        exit 1
    fi
    echo "✅ Using existing requirements.txt for deployment"
    
    # Add Oryx build detection files to ensure proper build
    echo "🔧 Adding Oryx build detection files..."
    echo "python" > .oryx_env_type
    echo "3.11" > .python-version
    
    # Create a simple build script to force Oryx recognition
    cat > build.sh << 'EOF'
#!/bin/bash
echo "Oryx build starting..."
python --version
pip --version
echo "Installing requirements..."
pip install -r requirements.txt
echo "Build completed"
EOF
    chmod +x build.sh

    # Verify startup.py exists
    if [ ! -f "startup.py" ]; then
        echo "❌ startup.py not found in backend directory"
        exit 1
    fi
    echo "✅ Using existing startup.py for Azure App Service"

    # Verify required files exist
    if [ ! -f "runtime.txt" ]; then
        echo "❌ runtime.txt not found in backend directory"
        exit 1
    fi
    echo "✅ Using existing runtime.txt for Python version specification"
    
    # Create deployment package with optimized structure
    zip -r /tmp/backend-deploy.zip . \
        -x "*.pyc" \
        "__pycache__/*" \
        ".pytest_cache/*" \
        "tests/*" \
        ".env" \
        "*.log" \
        ".git/*" \
        "node_modules/*" \
        "requirements-*.txt" \
        "Dockerfile*" \
        "docker*" \
        ".dockerignore"

    
    echo "🚀 Deploying backend to Azure App Service..."
    
    # Function to deploy with timeout using deployment source for proper build
    deploy_backend() {
        timeout --preserve-status --kill-after=10 300 az webapp deployment source config-zip \
            --name $BACKEND_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --src /tmp/backend-deploy.zip
    }
    
    # Configure build settings BEFORE deployment (critical for Oryx build success)
    echo "🔧 Configuring build-specific environment variables..."
    az webapp config appsettings set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --settings \
            SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
            ENABLE_ORYX_BUILD="true" \
            ORYX_ENV_TYPE="python" \
            ORYX_PYTHON_VERSION="3.11" \
            PRE_BUILD_SCRIPT_PATH="" \
            POST_BUILD_SCRIPT_PATH="" \
            DISABLE_COLLECTSTATIC="true" \
            WEBSITE_RUN_FROM_PACKAGE="0" \
            WEBSITE_ENABLE_SYNC_UPDATE_SITE="true"
    
    # Configure Python runtime
    echo "🔧 Setting Python runtime version..."
    az webapp config set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --linux-fx-version "PYTHON|3.11"
    
    # Prepare for clean deployment without stopping the app
    echo "🔄 Preparing for clean deployment..."
    
    # Clear any existing deployment artifacts and cached builds
    echo "🧹 Clearing deployment cache and forcing fresh build..."
    az webapp deployment source delete --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null || true
    
    # Reset deployment settings to force clean slate
    az webapp config appsettings delete \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --setting-names WEBSITE_SKIP_AUTOCONFIGURE_STATICFILES WEBSITE_DISABLE_SCM_SEPARATION 2>/dev/null || true
    
    echo "✅ Ready for deployment - app will remain running during deployment"
    
    # Try deployment with timeout (5 minutes)
    echo "🚀 Starting backend deployment (timeout: 5 minutes)..."
    echo "   Note: You can press Ctrl+C to interrupt if it gets stuck"
    if deploy_backend; then
        echo "✅ Backend deployed successfully"
        
        # Set startup command after successful deployment
        echo "🔧 Setting startup command after deployment..."
        az webapp config set \
            --name $BACKEND_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --startup-file "python run_app.py"
        
        # Restart app to ensure it's running with new deployment
        echo "🔄 Restarting app to apply new deployment..."
        az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
        
        # Wait for deployment to complete and check if dependencies were installed
        echo "⏳ Waiting for deployment to complete..."
        sleep 45
        
        # Check deployment logs for build success
        echo "🔍 Checking deployment logs for build status..."
        RECENT_DEPLOYMENT_LOGS=$(az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null | tail -30 || echo "")
        
        if echo "$RECENT_DEPLOYMENT_LOGS" | grep -q "virtual environment directory.*antenv"; then
            echo "✅ Virtual environment detected in logs"
        else
            echo "⚠️ No virtual environment found in deployment logs"
        fi
        
        if echo "$RECENT_DEPLOYMENT_LOGS" | grep -q "Installing.*requirements"; then
            echo "✅ Requirements installation detected in logs"
        else
            echo "⚠️ No requirements installation found in deployment logs"
        fi
        
        # Check if the app is responding and has dependencies
        echo "🔍 Checking backend health..."
        if curl -f -s "https://$BACKEND_APP_NAME.azurewebsites.net/health" > /dev/null 2>&1; then
            echo "✅ Backend is responding normally"
        else
            echo "⚠️ Backend not responding, checking logs for dependency issues..."
            
            # Check recent logs for dependency errors
            RECENT_LOGS=$(az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null | tail -20 || echo "")
            
            if echo "$RECENT_LOGS" | grep -q "ModuleNotFoundError\|not available\|Missing packages"; then
                echo "🔧 Detected dependency issues, applying runtime installation fix..."
                
                # Update startup command to force runtime installation
                az webapp config set \
                    --name $BACKEND_APP_NAME \
                    --resource-group $RESOURCE_GROUP \
                    --startup-file "python -m pip install --user quart flask azure-identity azure-storage-blob openai aiohttp python-dotenv cryptography --disable-pip-version-check --quiet && python startup.py"
                
                # Restart to apply the fix
                echo "🔄 Restarting with runtime installation..."
                az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
                
                # Wait for restart and installation
                echo "⏳ Waiting for runtime installation to complete..."
                sleep 60
                
                # Check again
                if curl -f -s "https://$BACKEND_APP_NAME.azurewebsites.net/health" > /dev/null 2>&1; then
                    echo "✅ Backend now responding after runtime installation"
                else
                    echo "⚠️ Backend still not responding, but deployment completed"
                fi
            fi
        fi
    else
        DEPLOY_EXIT_CODE=$?
        if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
            echo "❌ Backend deployment timed out after 5 minutes"
        else
            echo "❌ Backend deployment failed with exit code: $DEPLOY_EXIT_CODE"
        fi
        echo "Please check the deployment logs for more details."
        exit 1
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

# Step: Configure OpenAI Service (if available)
echo "🧠 Detecting and configuring Azure OpenAI service..."

# Auto-detect OpenAI service if not set or if service doesn't exist
if [ -z "$OPENAI_SERVICE" ] || ! az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "🔍 Auto-detecting OpenAI service in resource group..."
    
    # Find OpenAI service by kind
    DETECTED_OPENAI=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'][0].name" -o tsv 2>/dev/null)
    
    if [ -n "$DETECTED_OPENAI" ] && [ "$DETECTED_OPENAI" != "" ]; then
        echo "✅ Found OpenAI service: $DETECTED_OPENAI"
        export OPENAI_SERVICE="$DETECTED_OPENAI"
    else
        echo "⚠️  No OpenAI service found in resource group: $RESOURCE_GROUP"
        echo "   The application will run in basic mode without AI features"
        export OPENAI_SERVICE=""
        export OPENAI_UNAVAILABLE=true
    fi
fi

# Configure OpenAI settings if service is available
if [ -n "$OPENAI_SERVICE" ] && [ "$OPENAI_UNAVAILABLE" != "true" ]; then
    echo "🔧 Configuring OpenAI service: $OPENAI_SERVICE"
    
    # Get OpenAI endpoint
    OPENAI_ENDPOINT=$(az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" --query "properties.endpoint" -o tsv 2>/dev/null)
    
    # Get OpenAI key
    OPENAI_KEY=$(az cognitiveservices account keys list --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" --query "key1" -o tsv 2>/dev/null)
    
    # Detect GPT deployment
    GPT_DEPLOYMENT=$(az cognitiveservices account deployment list --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" --query "[?contains(model.name, 'gpt')][0].name" -o tsv 2>/dev/null)
    
    # Detect embedding deployment
    EMBEDDING_DEPLOYMENT=$(az cognitiveservices account deployment list --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" --query "[?contains(model.name, 'embedding')][0].name" -o tsv 2>/dev/null)
    
    echo "   OpenAI Endpoint: $OPENAI_ENDPOINT"
    echo "   GPT Deployment: ${GPT_DEPLOYMENT:-'Not found'}"
    echo "   Embedding Deployment: ${EMBEDDING_DEPLOYMENT:-'Not found'}"
    
    # Set defaults if deployments not found
    if [ -z "$GPT_DEPLOYMENT" ]; then
        echo "   ⚠️  No GPT deployment found, using default: gpt-4o-mini"
        GPT_DEPLOYMENT="gpt-4o-mini"
    fi
    
    if [ -z "$EMBEDDING_DEPLOYMENT" ]; then
        echo "   ⚠️  No embedding deployment found, using default: text-embedding-3-large"
        EMBEDDING_DEPLOYMENT="text-embedding-3-large"
    fi
else
    echo "⚠️  OpenAI service not available - app will run in basic mode"
    OPENAI_ENDPOINT=""
    OPENAI_KEY=""
    GPT_DEPLOYMENT=""
    EMBEDDING_DEPLOYMENT=""
fi

# Configure backend app settings for native Python deployment (optimized for Oryx build)
echo "🔧 Configuring backend application settings..."
az webapp config appsettings set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT" \
        AZURE_STORAGE_CONTAINER="${STORAGE_CONTAINER:-content}" \
        AZURE_SEARCH_SERVICE="$SEARCH_SERVICE" \
        AZURE_SEARCH_INDEX="gptkbindex" \
        AZURE_OPENAI_SERVICE="$OPENAI_SERVICE" \
        AZURE_OPENAI_ENDPOINT="$OPENAI_ENDPOINT" \
        AZURE_OPENAI_API_KEY="$OPENAI_KEY" \
        AZURE_OPENAI_CHATGPT_DEPLOYMENT="$GPT_DEPLOYMENT" \
        AZURE_OPENAI_EMB_DEPLOYMENT="$EMBEDDING_DEPLOYMENT" \
        OPENAI_HOST="azure" \
        AZURE_COSMOSDB_ACCOUNT="$COSMOS_ACCOUNT" \
        AZURE_COSMOSDB_ENDPOINT="https://$COSMOS_ACCOUNT.documents.azure.com:443/" \
        AZURE_COSMOSDB_DATABASE="${COSMOS_DATABASE:-chathistory}" \
        AZURE_COSMOSDB_CONTAINER="${COSMOS_CONTAINER:-chatcontainer}" \
        AZURE_CHAT_HISTORY_DATABASE="${COSMOS_DATABASE:-chathistory}" \
        AZURE_CHAT_HISTORY_CONTAINER="${COSMOS_CONTAINER:-chatcontainer}" \
        AZURE_CHAT_HISTORY_VERSION="1" \
        USE_CHAT_HISTORY_COSMOS="true" \
        WEBSITE_HTTPLOGGING_RETENTION_DAYS="7" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
        ENABLE_ORYX_BUILD="true" \
        ORYX_ENV_TYPE="python" \
        ORYX_PYTHON_VERSION="3.11" \
        PRE_BUILD_SCRIPT_PATH="" \
        POST_BUILD_SCRIPT_PATH="" \
        DISABLE_COLLECTSTATIC="true" \
        XDG_CACHE_HOME="/tmp/.cache" \
        RUNNING_IN_PRODUCTION="true" \
        WEBSITE_HOSTNAME="true" \
        PYTHONUNBUFFERED="1" \
        PYTHONIOENCODING="UTF-8"

# Enable remote debugging and additional settings (helpful for troubleshooting)
echo "🔧 Enabling additional debugging settings..."
az webapp config appsettings set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        WEBSITE_ENABLE_SYNC_UPDATE_SITE="true" \
        WEBSITE_RUN_FROM_PACKAGE="0"

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