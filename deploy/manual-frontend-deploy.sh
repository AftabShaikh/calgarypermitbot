#!/bin/bash

# Manual Frontend Deployment Script for Calgary Permit Bot
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

echo "🎨 Manual Frontend Deployment"
echo "============================="
echo "Frontend App: $FRONTEND_APP_NAME"
echo "Backend App: $BACKEND_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Navigate to frontend folder
FRONTEND_FOLDER="$PROJECT_ROOT/app/frontend"
if [ ! -d "$FRONTEND_FOLDER" ]; then
    echo "❌ Frontend folder not found at $FRONTEND_FOLDER"
    exit 1
fi

cd "$FRONTEND_FOLDER"

echo "📦 Installing dependencies..."
npm ci

# Set backend URL for build
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
export VITE_BACKEND_URL="$BACKEND_URL"
export REACT_APP_BACKEND_URL="$BACKEND_URL"

echo "🔨 Building frontend application..."
echo "Backend URL: $BACKEND_URL"
npm run build

echo "📦 Preparing deployment package..."

# Create deployment folder
DEPLOY_DIR="/tmp/frontend-manual-deploy"
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Copy built files
if [ -d "dist" ]; then
    cp -r dist/* "$DEPLOY_DIR/"
    echo "✅ Copied files from dist/ folder"
elif [ -d "build" ]; then
    cp -r build/* "$DEPLOY_DIR/"
    echo "✅ Copied files from build/ folder"
else
    echo "❌ No build output found (looking for dist/ or build/ folders)"
    ls -la
    exit 1
fi

# Create Express server for SPA
cat > "$DEPLOY_DIR/server.js" << 'EOF'
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

# Create package.json
cat > "$DEPLOY_DIR/package.json" << 'EOF'
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

# Create web.config for proper routing
cat > "$DEPLOY_DIR/web.config" << 'EOF'
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

# Create deployment package
DEPLOY_ZIP="/tmp/frontend-manual-deploy.zip"
cd "$DEPLOY_DIR"
zip -r "$DEPLOY_ZIP" .
cd "$PROJECT_ROOT"

echo "✅ Deployment package created: $DEPLOY_ZIP"
echo "📊 Package size: $(ls -lh "$DEPLOY_ZIP" | awk '{print $5}')"
echo ""

echo "🚀 Deploying to Azure App Service..."
echo "⚠️  This may take 5-15 minutes. Please be patient..."

# Try deployment
if timeout 1800 az webapp deploy \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --src-path "$DEPLOY_ZIP" \
    --type zip; then
    echo "✅ Frontend deployed successfully!"
else
    DEPLOY_EXIT_CODE=$?
    echo "❌ Deployment failed (exit code: $DEPLOY_EXIT_CODE)"
    
    echo ""
    echo "🔧 ALTERNATIVE DEPLOYMENT METHODS"
    echo "=================================="
    echo ""
    echo "1. Azure Portal Upload:"
    echo "   - Go to: https://portal.azure.com"
    echo "   - Navigate to: $FRONTEND_APP_NAME (App Service)"
    echo "   - Go to: Deployment Center → Manual deployment"
    echo "   - Upload: $DEPLOY_ZIP"
    echo ""
    echo "2. Extract and use FTP:"
    echo "   - Extract: $DEPLOY_ZIP"
    echo "   - Get FTP credentials from Azure Portal"
    echo "   - Upload contents to /site/wwwroot/"
    echo ""
    echo "3. Try alternative Azure CLI command:"
    echo "   az webapp deployment source config-zip \\"
    echo "       --name $FRONTEND_APP_NAME \\"
    echo "       --resource-group $RESOURCE_GROUP \\"
    echo "       --src $DEPLOY_ZIP"
    echo ""
    exit 1
fi

echo ""
echo "🏥 Running health check..."
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"
echo "Frontend URL: $FRONTEND_URL"

# Wait for service to start
echo "⏳ Waiting for service to start..."
sleep 60

# Health check
if curl -f "$FRONTEND_URL" -m 30 > /dev/null 2>&1; then
    echo "✅ Frontend health check passed!"
else
    echo "⚠️  Health check failed (service may still be starting)"
fi

echo ""
echo "🎉 Manual frontend deployment completed!"
echo "Frontend URL: $FRONTEND_URL"
echo "Backend URL: $BACKEND_URL"
echo ""
echo "📝 Next steps:"
echo "1. Wait 2-3 minutes for the service to fully start"
echo "2. Visit the frontend URL to test the application"
echo "3. Check logs if needed:"
echo "   az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"

# Clean up
rm -rf "$DEPLOY_DIR"