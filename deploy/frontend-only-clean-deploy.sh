#!/bin/bash

# Calgary Permit Bot - Clean Frontend-Only Deployment Script
# This script performs a complete clean frontend deployment with cache clearing

set -e  # Exit on any error

# Handle Ctrl+C gracefully
trap 'echo -e "\n❌ Deployment interrupted by user. Cleaning up..."; exit 130' INT TERM

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Loaded configuration from preparation script"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🚀 Starting Clean Frontend-Only Deployment"
echo "=========================================="
echo "🎨 Frontend App: $FRONTEND_APP_NAME"
echo ""

# Navigate to frontend directory
FRONTEND_FOLDER="$PROJECT_ROOT/app/frontend"
if [ ! -d "$FRONTEND_FOLDER" ]; then
    echo "❌ Frontend folder not found at $FRONTEND_FOLDER"
    exit 1
fi

cd "$FRONTEND_FOLDER"

echo "🧹 Step 1: Clean Build - Removing old build artifacts..."
rm -rf ../backend/static
rm -rf dist
rm -rf build
rm -rf node_modules/.vite
echo "✅ Old build artifacts cleaned"

echo "📦 Step 2: Installing fresh dependencies..."
npm ci

echo "🔨 Step 3: Building frontend application..."
# Set backend URL for build
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
export VITE_BACKEND_URL="$BACKEND_URL"
export REACT_APP_BACKEND_URL="$BACKEND_URL"

npm run build

echo "📋 Step 4: Verifying build output..."
BACKEND_STATIC_DIR="../backend/static"
if [ ! -d "$BACKEND_STATIC_DIR" ] || [ ! "$(ls -A $BACKEND_STATIC_DIR 2>/dev/null)" ]; then
    echo "❌ Build failed - no output found at $BACKEND_STATIC_DIR"
    exit 1
fi

echo "✅ Build successful. Files created:"
ls -la "$BACKEND_STATIC_DIR"
echo "📄 HTML content check:"
head -10 "$BACKEND_STATIC_DIR/index.html"

echo "📦 Step 5: Preparing clean deployment package..."
# Clean up any existing deployment
rm -rf /tmp/frontend-deploy
rm -f /tmp/frontend-deploy.zip
mkdir -p /tmp/frontend-deploy

# Copy fresh build files
cp -r "$BACKEND_STATIC_DIR"/* /tmp/frontend-deploy/
echo "✅ Files copied to deployment directory"

# Create the Express server (fixed version)
echo "🔧 Step 6: Creating optimized Express server..."
cat > /tmp/frontend-deploy/server.js << 'EOF'
const express = require('express');
const path = require('path');
const fs = require('fs');
const app = express();
const port = process.env.PORT || 8080;

console.log('🚀 Frontend server starting...');
console.log('📁 Serving files from:', __dirname);

// Log all files in the directory for debugging
try {
    const files = fs.readdirSync(__dirname);
    console.log('📋 Available files:', files);
    
    const assetsPath = path.join(__dirname, 'assets');
    if (fs.existsSync(assetsPath)) {
        const assetFiles = fs.readdirSync(assetsPath);
        console.log('📦 Asset files:', assetFiles);
    }
} catch (error) {
    console.error('❌ Error reading directory:', error);
}

// Serve static files with explicit MIME types and proper headers
app.use(express.static(path.join(__dirname), {
    maxAge: '1d', // Cache for 1 day
    etag: true,
    setHeaders: (res, filePath) => {
        console.log('📡 Serving file:', filePath);
        
        if (filePath.endsWith('.js')) {
            res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
        } else if (filePath.endsWith('.css')) {
            res.setHeader('Content-Type', 'text/css; charset=utf-8');
        } else if (filePath.endsWith('.html')) {
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
        } else if (filePath.endsWith('.json')) {
            res.setHeader('Content-Type', 'application/json; charset=utf-8');
        } else if (filePath.endsWith('.ico')) {
            res.setHeader('Content-Type', 'image/x-icon');
        }
        
        // Disable caching for development
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
    }
}));

// SPA catch-all route - ONLY for non-file requests
app.get('*', (req, res) => {
    console.log('🔍 Handling request for:', req.path);
    
    // Check if this looks like a file request
    if (req.path.includes('.')) {
        console.log('❌ File not found:', req.path);
        res.status(404).type('text/plain').send('File not found: ' + req.path);
        return;
    }
    
    // This is a SPA route - serve index.html
    console.log('📄 Serving index.html for SPA route:', req.path);
    res.sendFile(path.join(__dirname, 'index.html'));
});

// Error handling
app.use((error, req, res, next) => {
    console.error('❌ Server error:', error);
    res.status(500).send('Internal server error');
});

app.listen(port, () => {
    console.log(`✅ Frontend server running on port ${port}`);
    console.log(`🌐 Access at: http://localhost:${port}`);
});
EOF

# Create package.json
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
    "node": ">=20.0.0"
  }
}
EOF

echo "🗜️  Step 7: Creating deployment package..."
cd /tmp/frontend-deploy
zip -r ../frontend-deploy.zip .
PACKAGE_SIZE=$(ls -lh ../frontend-deploy.zip | awk '{print $5}')
echo "✅ Deployment package created: $PACKAGE_SIZE"

echo "🔧 Step 8: Configuring Azure App Service..."
# Stop the app to clear any caches
echo "⏸️  Stopping app to clear caches..."
az webapp stop --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP

# Clear any existing deployments
echo "🧹 Clearing existing deployments..."
az webapp deployment source delete --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null || true

# Configure runtime settings
echo "⚙️  Configuring runtime settings..."
az webapp config set \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --linux-fx-version "NODE|20-lts" \
    --startup-file "npm install && node server.js"

# Configure app settings to disable caching
az webapp config appsettings set \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net" \
        NODE_ENV="production" \
        WEBSITE_NODE_DEFAULT_VERSION="20-lts" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="false" \
        WEBSITE_RUN_FROM_PACKAGE="0" \
        WEBSITE_ENABLE_SYNC_UPDATE_SITE="true" \
        WEBSITE_DYNAMIC_CACHE="0" \
        WEBSITE_LOCAL_CACHE_OPTION="Never"

echo "🚀 Step 9: Deploying fresh build to Azure..."
# Deploy with timeout
deploy_frontend() {
    timeout --preserve-status --kill-after=10 300 az webapp deployment source config-zip \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src ../frontend-deploy.zip
}

if deploy_frontend; then
    echo "✅ Deployment successful!"
else
    DEPLOY_EXIT_CODE=$?
    if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
        echo "⏰ Deployment timed out but may still be processing..."
    else
        echo "❌ Deployment failed with exit code: $DEPLOY_EXIT_CODE"
        exit 1
    fi
fi

echo "🔄 Step 10: Starting the application..."
az webapp start --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP

echo "⏳ Step 11: Waiting for application to fully start..."
sleep 30

echo "🏥 Step 12: Running health checks..."
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"

echo "🔍 Checking if app is responding..."
for i in {1..5}; do
    if curl -f -s "$FRONTEND_URL" > /dev/null; then
        echo "✅ Frontend is responding!"
        break
    else
        echo "⏳ Attempt $i/5 - waiting for app to respond..."
        sleep 10
    fi
done

echo "🔍 Checking asset files..."
# Check if the main JS file is accessible
MAIN_JS_URL="$FRONTEND_URL/assets/index-DbhCxHJB.js"
if curl -f -s -I "$MAIN_JS_URL" | grep -q "200 OK"; then
    echo "✅ Main JavaScript file is accessible"
else
    echo "⚠️  Main JavaScript file check failed"
    echo "🔍 Let's check what files are available..."
    curl -s "$FRONTEND_URL" | grep -o 'src="[^"]*\.js"' | head -5
fi

# Clean up
rm -f /tmp/frontend-deploy.zip
rm -rf /tmp/frontend-deploy

echo ""
echo "🎉 Clean Frontend Deployment Completed!"
echo "========================================"
echo "🌐 Frontend URL: $FRONTEND_URL"
echo ""
echo "🔗 Next Steps:"
echo "   1. Wait 2-3 minutes for full application startup"
echo "   2. Test the application at: $FRONTEND_URL"
echo "   3. Check browser console for any remaining errors"
echo "   4. If issues persist, run: az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "✨ The deployment has been completely refreshed with cache clearing!"
