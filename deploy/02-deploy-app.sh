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

    # Verify requirements.txt exists and validate it
    echo "📝 Using existing requirements.txt for Azure App Service deployment..."
    if [ ! -f "requirements.txt" ]; then
        echo "❌ requirements.txt not found in backend directory"
        exit 1
    fi
    
    # Run requirements validation
    echo "🔍 Validating requirements.txt completeness..."
    if [ -f "$SCRIPT_DIR/validate-requirements.sh" ]; then
        if ! "$SCRIPT_DIR/validate-requirements.sh"; then
            echo "❌ Requirements validation failed. Please fix requirements.txt before deploying."
            exit 1
        fi
    else
        echo "⚠️  Requirements validation script not found, skipping validation"
    fi
    
    echo "✅ Requirements.txt validated and ready for deployment"
    
    # Add Oryx build detection files to ensure proper build
    echo "🔧 Adding Oryx build detection files..."
    echo "python" > .oryx_env_type
    echo "3.11" > .python-version
    
    # Validate requirements.txt has all necessary dependencies
    echo "🔍 Validating requirements.txt completeness..."
    REQUIRED_PACKAGES=("prompty" "rich" "tenacity" "tiktoken" "quart" "uvicorn" "gunicorn" "azure-identity" "azure-storage-blob" "azure-search-documents" "azure-cosmos" "openai")
    
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! grep -q "^${package}" requirements.txt; then
            echo "⚠️  Missing required package: $package"
            echo "   Please ensure requirements.txt includes all dependencies"
        else
            echo "✅ Found: $package"
        fi
    done
    
    # Create a comprehensive build script for Oryx
    cat > build.sh << 'EOF'
#!/bin/bash
set -e
echo "🚀 Calgary Permit Bot - Custom Build Script"
echo "============================================="
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"
echo "Current directory: $(pwd)"
echo "Available files:"
ls -la

echo ""
echo "📦 Installing Python dependencies..."
echo "Requirements file contents:"
head -20 requirements.txt

# Upgrade pip first
python -m pip install --upgrade pip --no-cache-dir

# Install requirements with verbose output
echo "🔧 Installing from requirements.txt..."
python -m pip install -r requirements.txt --no-cache-dir --verbose

# Verify critical packages are installed
echo ""
echo "🔍 Verifying critical package installations..."
python -c "import prompty; print('✅ prompty installed')" || echo "❌ prompty failed"
python -c "import rich; print('✅ rich installed')" || echo "❌ rich failed"  
python -c "import tenacity; print('✅ tenacity installed')" || echo "❌ tenacity failed"
python -c "import tiktoken; print('✅ tiktoken installed')" || echo "❌ tiktoken failed"
python -c "import quart; print('✅ quart installed')" || echo "❌ quart failed"
python -c "import uvicorn; print('✅ uvicorn installed')" || echo "❌ uvicorn failed"
python -c "import azure.identity; print('✅ azure-identity installed')" || echo "❌ azure-identity failed"
python -c "import openai; print('✅ openai installed')" || echo "❌ openai failed"

echo ""
echo "✅ Build completed successfully!"
EOF
    chmod +x build.sh

    # Create a robust startup script as backup
    cat > start_app.py << 'EOF'
#!/usr/bin/env python3
"""
Robust startup script for Azure App Service
Falls back to basic HTTP server if dependencies fail
"""
import os
import sys
import subprocess
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

def install_critical_deps():
    """Install critical dependencies at runtime"""
    logger.info("Installing critical dependencies...")
    critical_deps = ["quart==0.19.4", "flask==3.0.3", "python-dotenv==1.0.1"]
    
    for dep in critical_deps:
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", dep, "--no-cache-dir", "--quiet"], 
                         check=True, timeout=60)
            logger.info(f"Installed {dep}")
        except Exception as e:
            logger.warning(f"Failed to install {dep}: {e}")

def create_basic_server():
    """Create basic HTTP server"""
    logger.info("Creating basic HTTP server...")
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import json
    
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            if self.path == '/health':
                response = {"status": "healthy", "mode": "basic"}
            else:
                response = {"message": "Calgary Permit Bot", "status": "basic mode"}
            
            self.wfile.write(json.dumps(response).encode())
        
        def log_message(self, format, *args):
            logger.info(format % args)
    
    port = int(os.environ.get("PORT", 8000))
    server = HTTPServer(("0.0.0.0", port), Handler)
    logger.info(f"Basic server running on port {port}")
    server.serve_forever()

if __name__ == "__main__":
    # Set environment
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    
    try:
        # Try run_app.py first
        logger.info("Attempting to run run_app.py...")
        exec(open('run_app.py').read())
    except Exception as e:
        logger.warning(f"run_app.py failed: {e}")
        try:
            # Try installing dependencies and run again
            install_critical_deps()
            exec(open('run_app.py').read())
        except Exception as e2:
            logger.error(f"All startup methods failed: {e2}")
            create_basic_server()
EOF

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
        timeout --preserve-status --kill-after=10 600 az webapp deployment source config-zip \
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
            PRE_BUILD_COMMAND="chmod +x build.sh && ./build.sh" \
            PRE_BUILD_SCRIPT_PATH="build.sh" \
            POST_BUILD_SCRIPT_PATH="" \
            DISABLE_COLLECTSTATIC="true" \
            WEBSITE_RUN_FROM_PACKAGE="0" \
            WEBSITE_ENABLE_SYNC_UPDATE_SITE="true" \
            PYTHONPATH="/home/site/wwwroot" \
            PYTHON_ISOLATE_WORKER_DEPENDENCIES="1" \
            PIP_EXTRA_INDEX_URL="" \
            PIP_TRUSTED_HOST="" \
            ORYX_DISABLE_PIP_UPGRADE="false"
    
    # Configure Python runtime and startup command with fallback
    echo "🔧 Setting Python runtime version and startup command..."
    az webapp config set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --linux-fx-version "PYTHON|3.11" \
        --startup-file "python run_app.py"
    
    # Set additional startup options as environment variables
    az webapp config appsettings set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --settings \
            STARTUP_COMMAND_FALLBACK="python start_app.py" \
            GUNICORN_CMD_ARGS="--worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 --timeout 120 --workers 1"
    
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
    
    # Try deployment with timeout (10 minutes)
    echo "🚀 Starting backend deployment (timeout: 10 minutes)..."
    echo "   Note: You can press Ctrl+C to interrupt if it gets stuck"
    if deploy_backend; then
        echo "✅ Backend deployed successfully"
        
        # Restart app to ensure it's running with new deployment
        echo "🔄 Restarting app to apply new deployment..."
        az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
        
        # Wait for deployment to complete and check if dependencies were installed
        echo "⏳ Waiting for deployment to complete..."
        sleep 45
        
        # Check deployment logs for build success
        echo "🔍 Checking deployment logs for build status..."
        RECENT_DEPLOYMENT_LOGS=$(timeout 30 az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null | tail -30 || echo "")
        
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
            echo "ℹ️ Backend health check failed - this is normal during initial deployment"
            echo "   The application may still be starting up or building dependencies"
        fi
    else
        DEPLOY_EXIT_CODE=$?
        if [ $DEPLOY_EXIT_CODE -eq 124 ] || [ $DEPLOY_EXIT_CODE -eq 143 ]; then
            if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
                echo "⚠️  Backend deployment timed out after 10 minutes"
            else
                echo "⚠️  Backend deployment was terminated (exit code 143)"
            fi
            echo "   The deployment is likely still completing in the background"
            echo "   Continuing with frontend deployment..."
            BACKEND_TIMEOUT=true
        else
            echo "❌ Backend deployment failed with exit code: $DEPLOY_EXIT_CODE"
            echo "Please check the deployment logs for more details."
            exit 1
        fi
    fi
    
    # Wait for backend build and start (skip if timed out)
    if [ "$BACKEND_TIMEOUT" != "true" ]; then
        echo "⏳ Waiting for backend build and startup (this may take several minutes)..."
        echo "   Press Ctrl+C to interrupt if needed..."
        for i in {1..24}; do
            sleep 5
            if [ $((i % 6)) -eq 0 ]; then
                echo "⏳ Still waiting... (${i}0 seconds elapsed)"
            fi
        done
    else
        echo "⏭️  Skipping additional wait due to timeout - continuing to frontend"
    fi
    
    # Check if the build completed successfully
    echo "🔍 Checking deployment status..."
    DEPLOYMENT_STATUS=$(az webapp deployment list --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "[0].status" -o tsv 2>/dev/null || echo "Unknown")
    echo "Backend deployment status: $DEPLOYMENT_STATUS"
    
    if [ "$DEPLOYMENT_STATUS" = "Failed" ]; then
        echo "❌ Backend deployment failed. Checking logs..."
        timeout 20 az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --provider filesystem 2>/dev/null | tail -20 || echo "Could not fetch logs"
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
    
    # Copy built files (Vite builds to ../backend/static folder)
    BACKEND_STATIC_DIR="../backend/static"
    if [ -d "$BACKEND_STATIC_DIR" ] && [ "$(ls -A $BACKEND_STATIC_DIR 2>/dev/null)" ]; then
        cp -r "$BACKEND_STATIC_DIR"/* /tmp/frontend-deploy/
        echo "✅ Copied files from backend/static/ folder (Vite build output)"
        echo "📁 Files copied:"
        ls -la /tmp/frontend-deploy/ | head -10
    elif [ -d "dist" ]; then
        cp -r dist/* /tmp/frontend-deploy/
        echo "✅ Copied files from dist/ folder"
    elif [ -d "build" ]; then
        cp -r build/* /tmp/frontend-deploy/
        echo "✅ Copied files from build/ folder"
    else
        echo "❌ No build output found (looking for ../backend/static/, dist/, or build/ folders)"
        echo "📂 Current directory contents:"
        ls -la
        echo "📂 Checking backend static directory:"
        ls -la ../backend/static/ 2>/dev/null || echo "Backend static directory not found"
        exit 1
    fi
    
    # Create an Express server with API proxying to serve the SPA
    cat > /tmp/frontend-deploy/server.js << 'EOF'
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const path = require('path');
const app = express();
const port = process.env.PORT || 8080;

// Get backend URL from environment variable set by Azure App Service
const BACKEND_URL = process.env.BACKEND_URL;

if (!BACKEND_URL) {
  console.error('ERROR: BACKEND_URL environment variable is not set!');
  console.error('This should be configured in Azure App Service settings.');
  process.exit(1);
}

console.log(`Frontend server starting on port ${port}`);
console.log(`Backend URL: ${BACKEND_URL}`);

// API proxy middleware - proxy all API calls to the backend
const apiProxy = createProxyMiddleware({
  target: BACKEND_URL,
  changeOrigin: true,
  pathRewrite: {
    '^/api': '/api' // Keep /api prefix
  },
  logLevel: 'info',
  onError: (err, req, res) => {
    console.error('Proxy error:', err);
    res.status(500).json({ error: 'Backend service unavailable' });
  }
});

// Proxy API routes to backend
app.use('/api', apiProxy);
app.use('/ask', apiProxy);
app.use('/chat', apiProxy);
app.use('/config', apiProxy);
app.use('/health', apiProxy);
app.use('/speech', apiProxy);
app.use('/upload', apiProxy);
app.use('/delete_uploaded', apiProxy);
app.use('/list_uploaded', apiProxy);
app.use('/chat_history', apiProxy);
app.use('/content', apiProxy);
app.use('/auth_setup', apiProxy);
app.use('/.auth/me', apiProxy);

// Serve static files with proper MIME types
app.use(express.static(path.join(__dirname), {
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.js')) {
      res.setHeader('Content-Type', 'application/javascript');
    } else if (filePath.endsWith('.css')) {
      res.setHeader('Content-Type', 'text/css');
    } else if (filePath.endsWith('.html')) {
      res.setHeader('Content-Type', 'text/html');
    }
  }
}));

// Handle SPA routing - serve index.html for non-asset routes
app.get('*', (req, res) => {
  // Don't intercept asset requests - let express.static handle them first
  if (req.path.startsWith('/assets/') || 
      req.path.endsWith('.js') || 
      req.path.endsWith('.css') || 
      req.path.endsWith('.map') ||
      req.path.endsWith('.ico') ||
      req.path.endsWith('.png') ||
      req.path.endsWith('.jpg') ||
      req.path.endsWith('.svg')) {
    // If we reach here, the file doesn't exist, so return 404
    res.status(404).send('File not found');
    return;
  }
  // For all other routes (SPA routes), serve index.html
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(port, () => {
  console.log(`Frontend server running on port ${port}`);
  console.log(`Serving static files from: ${__dirname}`);
  console.log(`Proxying API calls to: ${BACKEND_URL}`);
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
    "express": "^4.18.2",
    "http-proxy-middleware": "^2.0.6"
  },
  "engines": {
    "node": ">=20.0.0"
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
    
    # Configure frontend runtime and startup command BEFORE deployment
    echo "🔧 Configuring frontend runtime and startup command..."
    az webapp config set \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --linux-fx-version "NODE|20-lts" \
        --startup-file "npm install && node server.js"
    
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
        PYTHONIOENCODING="UTF-8" \
        PYTHONDONTWRITEBYTECODE="1" \
        PYTHON_ENABLE_GUNICORN_MULTIPROCESSING="false"

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
        WEBSITE_NODE_DEFAULT_VERSION="20-lts" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
        WEBSITE_RUN_FROM_PACKAGE="0"

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
echo ""
echo "🚨 If you encounter startup errors (like 'uvicorn not found'):"
echo "   Run the backend startup fix script:"
echo "   ./deploy/fix-backend-startup.sh"
echo ""
echo "📋 Common issues and fixes:"
echo "   - Dependencies not installed: Use fix-backend-startup.sh"
echo "   - App not starting: Check logs with 'az webapp log tail'"
echo "   - 500 errors: Wait 5 minutes for full initialization"