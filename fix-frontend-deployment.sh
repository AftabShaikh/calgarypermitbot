#!/bin/bash

# Calgary Permit Bot - Frontend Deployment Fix
# This script fixes the file hash mismatch issue by ensuring atomic deployment

echo "🔧 Fixing Calgary Permit Bot Frontend Deployment"
echo "==============================================="
echo "This script fixes the JavaScript file hash mismatch issue"
echo ""

# Configuration
RESOURCE_GROUP="rg-calgarypermitbot"
FRONTEND_APP_NAME="calgarypermitbot-frontend"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📋 Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Frontend App: $FRONTEND_APP_NAME"
echo "   Project Root: $PROJECT_ROOT"
echo ""

# Step 1: Clean build the frontend
echo "🔨 Step 1: Clean build the frontend..."
cd "$PROJECT_ROOT/app/frontend"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf node_modules/.vite
rm -rf ../backend/static/*
npm run build

# Verify build output
echo "📁 Build output verification:"
ls -la ../backend/static/
echo ""
echo "🔍 HTML file references:"
grep -o 'src="/assets/index-[^"]*\.js"' ../backend/static/index.html || echo "No JS references found"
echo ""

# Step 2: Create deployment package
echo "📦 Step 2: Creating deployment package..."
cd ../backend

# Create temporary deployment directory
rm -rf /tmp/frontend-fix-deploy
mkdir -p /tmp/frontend-fix-deploy

# Copy all static files
cp -r static/* /tmp/frontend-fix-deploy/

# Create Express server for SPA serving
cat > /tmp/frontend-fix-deploy/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 8080;

// Enable debug logging
const DEBUG = process.env.NODE_ENV !== 'production';

if (DEBUG) {
    app.use((req, res, next) => {
        console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
        next();
    });
}

// Serve static files with proper MIME types and caching headers
app.use(express.static(path.join(__dirname), {
    setHeaders: (res, filePath) => {
        // Set proper MIME types
        if (filePath.endsWith('.js')) {
            res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
        } else if (filePath.endsWith('.css')) {
            res.setHeader('Content-Type', 'text/css; charset=utf-8');
        } else if (filePath.endsWith('.html')) {
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
        }
        
        // Add cache-busting headers for assets
        if (filePath.includes('/assets/')) {
            res.setHeader('Cache-Control', 'public, max-age=31536000'); // 1 year for hashed assets
        } else {
            res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
            res.setHeader('Pragma', 'no-cache');
            res.setHeader('Expires', '0');
        }
    }
}));

// Handle SPA routing - serve index.html for non-asset routes
app.get('*', (req, res) => {
    // Let express.static handle asset requests first
    if (req.path.startsWith('/assets/') || 
        req.path.endsWith('.js') || 
        req.path.endsWith('.css') || 
        req.path.endsWith('.map') ||
        req.path.endsWith('.ico') ||
        req.path.includes('.')) {
        // File not found by static middleware
        console.log(`404: File not found - ${req.path}`);
        res.status(404).send('File not found');
        return;
    }
    
    // For SPA routes, serve index.html
    console.log(`SPA Route: ${req.path} -> index.html`);
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(port, () => {
    console.log(`🚀 Frontend server running on port ${port}`);
    console.log(`📁 Serving static files from: ${__dirname}`);
    console.log(`🔧 Debug mode: ${DEBUG ? 'ON' : 'OFF'}`);
    
    // Log available files
    const fs = require('fs');
    const assetsDir = path.join(__dirname, 'assets');
    if (fs.existsSync(assetsDir)) {
        console.log('📦 Available assets:');
        fs.readdirSync(assetsDir).forEach(file => {
            console.log(`   - /assets/${file}`);
        });
    }
});
EOF

# Create package.json
cat > /tmp/frontend-fix-deploy/package.json << 'EOF'
{
  "name": "calgarypermitbot-frontend",
  "version": "1.0.0",
  "description": "Calgary Permit Bot Frontend - Fixed Deployment",
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

# Step 3: Create deployment zip
echo "📦 Step 3: Creating deployment zip..."
cd /tmp/frontend-fix-deploy
zip -r ../frontend-fix-deploy.zip .

echo "✅ Deployment package created: /tmp/frontend-fix-deploy.zip"
echo "📏 Package size: $(ls -lh /tmp/frontend-fix-deploy.zip | awk '{print $5}')"
echo ""

# Step 4: Deploy to Azure
echo "🚀 Step 4: Deploying to Azure..."
echo "⚠️  IMPORTANT: Make sure you're logged in to Azure CLI first!"
echo ""

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install Azure CLI first."
    echo "   Installation: https://aka.ms/InstallAzureCli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

echo "✅ Azure CLI found and authenticated"

# Stop the app briefly for atomic deployment
echo "⏸️  Stopping app for atomic deployment..."
az webapp stop --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP

# Clear any cached deployment
echo "🧹 Clearing deployment cache..."
az webapp deployment source delete --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null || true

# Configure app settings to prevent caching issues
echo "🔧 Configuring app to prevent caching issues..."
az webapp config appsettings set \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        WEBSITE_RUN_FROM_PACKAGE="0" \
        WEBSITE_ENABLE_SYNC_UPDATE_SITE="true" \
        NODE_ENV="production" \
        WEBSITE_NODE_DEFAULT_VERSION="20-lts" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# Deploy the fixed frontend
echo "📤 Deploying fixed frontend..."
az webapp deployment source config-zip \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --src /tmp/frontend-fix-deploy.zip

# Start the app
echo "▶️  Starting app..."
az webapp start --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP

# Wait for deployment to complete
echo "⏳ Waiting for deployment to complete..."
sleep 30

# Step 5: Verification
echo "🔍 Step 5: Verifying deployment..."
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"

echo "🌐 Testing frontend URL: $FRONTEND_URL"

# Test if the app is responding
if curl -f -s "$FRONTEND_URL" > /dev/null; then
    echo "✅ Frontend is responding"
else
    echo "⚠️  Frontend not responding yet - may still be starting"
fi

# Check what files are actually deployed
echo "📋 Checking deployed files..."
echo "HTML references:"
curl -s "$FRONTEND_URL" | grep -o 'src="/assets/index-[^"]*\.js"' || echo "No JS references found in deployed HTML"

echo ""
echo "🎉 Frontend deployment fix completed!"
echo "=================================="
echo "🌐 Frontend URL: $FRONTEND_URL"
echo ""
echo "📝 Next steps:"
echo "   1. Wait 1-2 minutes for the app to fully start"
echo "   2. Test the application in your browser"
echo "   3. Hard refresh the page (Ctrl+F5) to clear browser cache"
echo "   4. Check browser console for any remaining errors"
echo ""
echo "🔧 If issues persist:"
echo "   - Check app logs: az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo "   - Restart the app: az webapp restart --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""

# Clean up
rm -rf /tmp/frontend-fix-deploy
rm -f /tmp/frontend-fix-deploy.zip

echo "✅ Cleanup completed"