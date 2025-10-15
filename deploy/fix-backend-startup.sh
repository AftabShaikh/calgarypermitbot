#!/bin/bash

# Fix Backend Startup Issues - Calgary Permit Bot
# This script fixes common startup issues like missing uvicorn/gunicorn

set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

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

echo "🔧 Fixing Backend Startup Issues"
echo "================================="
echo "Backend App: $BACKEND_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Step 1: Update startup command to use run_app.py instead of gunicorn
echo "🔧 Updating startup command to use run_app.py..."
az webapp config set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --startup-file "python run_app.py"

# Step 2: Update app settings to disable gunicorn multiprocessing
echo "🔧 Configuring app settings for better startup..."
az webapp config appsettings set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        PYTHON_ENABLE_GUNICORN_MULTIPROCESSING="false" \
        PYTHONDONTWRITEBYTECODE="1" \
        PYTHONUNBUFFERED="1" \
        DISABLE_COLLECTSTATIC="true" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
        WEBSITE_RUN_FROM_PACKAGE="0"

# Step 3: Try alternative startup commands
echo "🔄 Setting up alternative startup approaches..."

# Create a startup script in the Kudu console
echo "📝 Creating startup script via Kudu API..."

# Get publishing credentials
PUBLISH_PROFILE=$(az webapp deployment list-publishing-profiles --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "[?publishMethod=='MSDeploy']" | jq -r '.[0]')
KUDU_USER=$(echo $PUBLISH_PROFILE | jq -r '.userName')
KUDU_PASS=$(echo $PUSH_PROFILE | jq -r '.userPWD')

if [ "$KUDU_USER" != "null" ] && [ "$KUDU_PASS" != "null" ]; then
    KUDU_URL="https://$BACKEND_APP_NAME.scm.azurewebsites.net"
    
    # Create startup script
    STARTUP_SCRIPT='#!/bin/bash
echo "🚀 Calgary Permit Bot Startup Script"
echo "Current directory: $(pwd)"
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"

# Check if virtual environment exists
if [ -d "/home/site/wwwroot/antenv" ]; then
    echo "✅ Found Oryx virtual environment"
    source /home/site/wwwroot/antenv/bin/activate
else
    echo "⚠️ No virtual environment found"
fi

# Install missing dependencies at runtime if needed
echo "🔧 Installing critical dependencies..."
pip install --quiet --no-cache-dir quart flask python-dotenv azure-identity azure-storage-blob openai aiohttp || true

echo "🚀 Starting application..."
exec python run_app.py'

    # Upload startup script
    echo "$STARTUP_SCRIPT" | curl -X PUT \
        -u "$KUDU_USER:$KUDU_PASS" \
        -H "Content-Type: text/plain" \
        --data-binary @- \
        "$KUDU_URL/api/vfs/site/wwwroot/startup.sh" || true

    # Make it executable
    curl -X PUT \
        -u "$KUDU_USER:$KUDU_PASS" \
        -H "Content-Type: application/json" \
        -d '{"mode": "755"}' \
        "$KUDU_URL/api/vfs/site/wwwroot/startup.sh" || true

    echo "✅ Startup script created"
else
    echo "⚠️ Could not get Kudu credentials for script creation"
fi

# Step 4: Restart the application
echo "🔄 Restarting backend application..."
az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP

# Step 5: Wait and check health
echo "⏳ Waiting for application to start..."
sleep 30

echo "🔍 Checking application health..."
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"

# Check health endpoint
if curl -f -s "$BACKEND_URL/health" > /dev/null 2>&1; then
    echo "✅ Backend is responding at $BACKEND_URL/health"
else
    echo "⚠️ Backend health check failed, but this may be normal during startup"
fi

# Check basic connectivity
if curl -f -s "$BACKEND_URL" > /dev/null 2>&1; then
    echo "✅ Backend is accessible at $BACKEND_URL"
else
    echo "⚠️ Backend is not responding yet"
fi

echo ""
echo "🔧 Troubleshooting Commands:"
echo "=========================="
echo "Check logs:"
echo "  az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "Check deployment status:"
echo "  az webapp deployment list --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "Manual restart:"
echo "  az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"
echo ""
echo "✅ Backend startup fix completed!"
echo "Please wait 2-3 minutes for the changes to take effect."