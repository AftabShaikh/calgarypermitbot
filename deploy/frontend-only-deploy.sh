#!/bin/bash

# Calgary Permit Bot - Frontend Only Deployment Script
# This script deploys only the frontend application

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
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🎨 Starting Calgary Permit Bot Frontend-Only Deployment"
echo "====================================================="
echo "📋 Using configured resources:"
echo "   Backend App: $BACKEND_APP_NAME (already deployed)"
echo "   Frontend App: $FRONTEND_APP_NAME"
echo ""

# Validate that required resources exist
echo "🔍 Validating required resources exist..."

# Check if frontend app exists
if ! az webapp show --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "❌ Frontend web app '$FRONTEND_APP_NAME' not found in resource group '$RESOURCE_GROUP'"
    echo "Please run ./deploy/01-prepare-resources.sh first to create the required resources."
    exit 1
fi

echo "✅ Frontend app found!"
echo ""

# Build and deploy frontend
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
    
    # Set backend URL for build (using existing backend)
    BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
    export VITE_BACKEND_URL="$BACKEND_URL"
    export REACT_APP_BACKEND_URL="$BACKEND_URL"
    
    echo "🔗 Using existing backend: $BACKEND_URL"
    
    # Build the application
    echo "🔨 Building frontend application..."
    npm run build
    
    # Prepare deployment package
    echo "📦 Preparing frontend deployment package..."
    
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
    
    # Configure frontend app settings and runtime
    echo "🔧 Configuring frontend application settings and runtime..."
    
    # Set Node.js runtime first
    az webapp config set \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --linux-fx-version "NODE|20-lts" \
        --startup-file "npm install && node server.js"
    
    # Set app settings
    az webapp config appsettings set \
        --name $FRONTEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --settings \
            BACKEND_URL="$BACKEND_URL" \
            NODE_ENV="production" \
            WEBSITE_NODE_DEFAULT_VERSION="20-lts" \
            SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
            WEBSITE_RUN_FROM_PACKAGE="0"
    
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
        
        # Wait a moment for deployment to complete
        echo "⏳ Waiting for deployment to settle..."
        sleep 30
        
        # Test frontend
        FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"
        echo "🔍 Testing frontend deployment..."
        if curl -f -s "$FRONTEND_URL" > /dev/null 2>&1; then
            echo "✅ Frontend is responding"
        else
            echo "⚠️ Frontend health check failed (may still be starting up)"
        fi
        
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
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
else
    echo "❌ Frontend folder not found at $FRONTEND_FOLDER"
    echo "Available directories in app/:"
    ls -la "$PROJECT_ROOT/app/" || true
    exit 1
fi

# Clean up temporary files
rm -f /tmp/frontend-deploy.zip
rm -rf /tmp/frontend-deploy

echo ""
echo "✅ Calgary Permit Bot Frontend Deployment Completed!"
echo "=================================================="
echo "🌐 Frontend URL: https://$FRONTEND_APP_NAME.azurewebsites.net"
echo "🔧 Backend URL:  $BACKEND_URL (already deployed)"
echo ""
echo "🔗 Application Endpoints:"
echo "   - Main Application: https://$FRONTEND_APP_NAME.azurewebsites.net"
echo "   - API Backend: $BACKEND_URL"
echo "   - Health Check: $BACKEND_URL/health"
echo ""
echo "📝 Next Steps:"
echo "   1. Wait 2-3 minutes for frontend to fully start"
echo "   2. Visit the frontend URL to test the application"
echo "   3. Check frontend logs if needed:"
echo "      az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "🎉 Frontend deployment successful!"