#!/bin/bash

# Azure Cloud Shell Deployment Script (No azd required)
echo "🚀 Calgary Permit Bot - Azure Cloud Shell Deployment"
echo "=================================================="

# Configuration
AZURE_ENV_NAME=${1:-"calgarypermitbot"}
AZURE_LOCATION=${2:-"eastus"}
AZURE_RESOURCE_GROUP="rg-$AZURE_ENV_NAME"

echo "Environment: $AZURE_ENV_NAME"
echo "Location: $AZURE_LOCATION"
echo "Resource Group: $AZURE_RESOURCE_GROUP"

# Get current user info
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

echo "Subscription: $AZURE_SUBSCRIPTION_ID"
echo "Principal ID: $AZURE_PRINCIPAL_ID"

# Create resource group
echo "📦 Creating resource group..."
az group create \
  --name $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION

# Deploy infrastructure using resource group scope (simpler than subscription scope)
echo "🏗️  Deploying infrastructure to resource group..."

# Create a simplified parameters file that avoids the problematic parameters
cat > rg-deployment-parameters.json << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {"value": "$AZURE_ENV_NAME"},
    "location": {"value": "$AZURE_LOCATION"},
    "principalId": {"value": "$AZURE_PRINCIPAL_ID"},
    "deploymentTarget": {"value": "appservice"},
    "webAppExists": {"value": false}
  }
}
EOF

# Deploy to resource group scope instead of subscription scope
az deployment group create \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file infra/core/host/appservice.bicep \
  --parameters @rg-deployment-parameters.json \
  --name "appservice-deployment"

echo "✅ Basic infrastructure deployed!"

# Get resource names
echo "🔍 Getting resource information..."
APP_SERVICE_NAME=$(az webapp list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv 2>/dev/null || echo "")

if [ -z "$APP_SERVICE_NAME" ]; then
  echo "❌ App Service not found. Trying manual resource creation..."
  
  # Create App Service Plan and Web App manually
  APP_SERVICE_PLAN_NAME="${AZURE_ENV_NAME}-plan"
  APP_SERVICE_NAME="${AZURE_ENV_NAME}-app"
  
  echo "Creating App Service Plan: $APP_SERVICE_PLAN_NAME"
  az appservice plan create \
    --name $APP_SERVICE_PLAN_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_LOCATION \
    --sku B1 \
    --is-linux
  
  echo "Creating Web App: $APP_SERVICE_NAME"
  az webapp create \
    --name $APP_SERVICE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN_NAME \
    --runtime "PYTHON|3.11"
fi

echo "App Service: $APP_SERVICE_NAME"

# Build frontend if it exists
echo "🔨 Building frontend..."
if [ -d "app/frontend" ]; then
    cd app/frontend
    npm install || echo "npm install failed, skipping frontend build"
    npm run build || echo "npm build failed, skipping frontend build"
    cd ../..
fi

# Prepare deployment package
echo "📦 Preparing deployment package..."
mkdir -p deploy
cp -r app/backend/* deploy/

# Copy frontend build if it exists
if [ -d "app/frontend/dist" ]; then
    mkdir -p deploy/static
    cp -r app/frontend/dist/* deploy/static/ || echo "Frontend copy failed, continuing..."
fi

# Ensure gunicorn is in requirements
if [ -f "deploy/requirements.txt" ] && ! grep -q "gunicorn" deploy/requirements.txt; then
    echo "gunicorn>=21.2.0" >> deploy/requirements.txt
fi

# Create startup command for App Service
cat > deploy/startup.sh << 'EOF'
#!/bin/bash
cd /home/site/wwwroot
gunicorn -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 main:app
EOF
chmod +x deploy/startup.sh

# Deploy application
echo "🚀 Deploying application..."
cd deploy
zip -r ../app-package.zip . -x "*.pyc" "__pycache__/*"
cd ..

az webapp deployment source config-zip \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --src app-package.zip

# Configure basic app settings (without Azure AI services for now)
echo "⚙️  Configuring basic application settings..."
az webapp config appsettings set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --settings \
    WEBSITE_RUN_FROM_PACKAGE=1 \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
    ENABLE_ORYX_BUILD=true \
    RUNNING_IN_PRODUCTION=true

# Configure startup command
az webapp config set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --startup-file "gunicorn -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 main:app"

# Get app URL
APP_URL=$(az webapp show --resource-group $AZURE_RESOURCE_GROUP --name $APP_SERVICE_NAME --query 'defaultHostName' -o tsv)

echo ""
echo "🎉 Basic deployment completed!"
echo "========================================="
echo "Your Calgary Permit Bot is available at:"
echo "https://$APP_URL"
echo ""
echo "⚠️  Note: You'll need to manually configure Azure AI services:"
echo "1. Create Azure OpenAI service"
echo "2. Create Azure AI Search service"
echo "3. Create Storage Account"
echo "4. Update app settings with connection details"
echo ""
echo "Resources created in resource group: $AZURE_RESOURCE_GROUP"
echo "- App Service: $APP_SERVICE_NAME"

# Cleanup
rm -f rg-deployment-parameters.json app-package.zip
rm -rf deploy/

echo ""
echo "Next steps:"
echo "1. Visit https://$APP_URL to test basic functionality"
echo "2. Configure Azure AI services through Azure Portal"
echo "3. Update app settings with service connection strings"