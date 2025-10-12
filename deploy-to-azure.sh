#!/bin/bash

# Calgary Permit Bot - Azure Deployment Script
# Run this in Azure Cloud Shell

set -e

echo "🚀 Calgary Permit Bot Deployment Script"
echo "======================================="

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

# Force App Service deployment (not Container Apps)
export DEPLOYMENT_TARGET="appservice"
export AZURE_CONTAINER_APPS_WORKLOAD_PROFILE="Consumption"

echo "Deployment Target: $DEPLOYMENT_TARGET"

# Create resource group
echo "📦 Creating resource group..."
az group create \
  --name $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION

# Create deployment parameters - using the original template approach
echo "⚙️  Creating deployment parameters..."

# Use the existing parameters template but substitute our values
cp infra/main.parameters.json deployment-parameters.json

# Replace template variables with actual values using sed
sed -i "s/\${AZURE_ENV_NAME}/$AZURE_ENV_NAME/g" deployment-parameters.json
sed -i "s/\${AZURE_RESOURCE_GROUP}/$AZURE_RESOURCE_GROUP/g" deployment-parameters.json
sed -i "s/\${AZURE_LOCATION}/$AZURE_LOCATION/g" deployment-parameters.json
sed -i "s/\${AZURE_PRINCIPAL_ID}/$AZURE_PRINCIPAL_ID/g" deployment-parameters.json
sed -i "s/\${DEPLOYMENT_TARGET=appservice}/appservice/g" deployment-parameters.json
sed -i "s/\${AZURE_CONTAINER_APPS_WORKLOAD_PROFILE=Consumption}/Consumption/g" deployment-parameters.json
sed -i "s/\${OPENAI_HOST=azure}/azure/g" deployment-parameters.json
sed -i "s/\${AZURE_SEARCH_SERVICE_SKU=basic}/basic/g" deployment-parameters.json
sed -i "s/\${AZURE_SEARCH_INDEX=gptkbindex}/gptkbindex/g" deployment-parameters.json

echo "Parameters file created and configured for App Service deployment"

# Deploy infrastructure
echo "🏗️  Deploying Azure infrastructure..."
az deployment sub create \
  --name "$AZURE_ENV_NAME-deployment" \
  --location $AZURE_LOCATION \
  --template-file infra/main.bicep \
  --parameters @deployment-parameters.json

echo "✅ Infrastructure deployed successfully!"

# Get resource names
echo "🔍 Getting resource information..."
APP_SERVICE_NAME=$(az webapp list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)
STORAGE_ACCOUNT=$(az storage account list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)
SEARCH_SERVICE=$(az search service list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)
OPENAI_SERVICE=$(az cognitiveservices account list --resource-group $AZURE_RESOURCE_GROUP --query '[?kind==`OpenAI`].name' -o tsv)

echo "App Service: $APP_SERVICE_NAME"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Search Service: $SEARCH_SERVICE"
echo "OpenAI Service: $OPENAI_SERVICE"

# Build frontend
echo "🔨 Building frontend..."
if [ -d "app/frontend" ]; then
    cd app/frontend
    npm install
    npm run build
    cd ../..
fi

# Prepare deployment package
echo "📦 Preparing deployment package..."
mkdir -p deploy
cp -r app/backend/* deploy/

# Copy frontend build if it exists
if [ -d "app/frontend/dist" ]; then
    mkdir -p deploy/static
    cp -r app/frontend/dist/* deploy/static/
fi

# The project already has a proper requirements.txt, so we'll use it
# But ensure gunicorn is available for App Service
if ! grep -q "gunicorn" deploy/requirements.txt; then
    echo "gunicorn>=21.2.0" >> deploy/requirements.txt
fi

# Create startup command for App Service (optional - App Service can auto-detect)
cat > deploy/startup.sh << 'EOF'
#!/bin/bash
cd /home/site/wwwroot
gunicorn -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 main:app
EOF
chmod +x deploy/startup.sh

# Deploy application
echo "🚀 Deploying application..."
cd deploy
zip -r ../app-package.zip .
cd ..

az webapp deployment source config-zip \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --src app-package.zip

# Configure app settings
echo "⚙️  Configuring application settings..."
az webapp config appsettings set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --settings \
    AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT \
    AZURE_STORAGE_CONTAINER="content" \
    AZURE_SEARCH_SERVICE=$SEARCH_SERVICE \
    AZURE_OPENAI_SERVICE=$OPENAI_SERVICE \
    AZURE_SEARCH_INDEX="gptkbindex" \
    AZURE_OPENAI_CHATGPT_MODEL="gpt-4o-mini" \
    AZURE_OPENAI_CHATGPT_DEPLOYMENT="gpt-4o-mini" \
    AZURE_OPENAI_EMB_MODEL_NAME="text-embedding-3-large" \
    AZURE_OPENAI_EMB_DEPLOYMENT="text-embedding-3-large" \
    AZURE_OPENAI_API_VERSION="2024-10-21" \
    OPENAI_HOST="azure" \
    RUNNING_IN_PRODUCTION="true" \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
    ENABLE_ORYX_BUILD=true

# Configure startup command (optional - Oryx can auto-detect Python apps)
az webapp config set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --startup-file "gunicorn -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 main:app"

# Upload sample data
echo "📄 Uploading sample data..."
STORAGE_KEY=$(az storage account keys list --resource-group $AZURE_RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query '[0].value' -o tsv)

az storage container create \
  --name content \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

if [ -d "data" ]; then
    az storage blob upload-batch \
      --destination content \
      --source data/ \
      --account-name $STORAGE_ACCOUNT \
      --account-key $STORAGE_KEY
fi

# Get app URL
APP_URL=$(az webapp show --resource-group $AZURE_RESOURCE_GROUP --name $APP_SERVICE_NAME --query 'defaultHostName' -o tsv)

echo ""
echo "🎉 Deployment completed successfully!"
echo "========================================="
echo "Your Calgary Permit Bot is available at:"
echo "https://$APP_URL"
echo ""
echo "Resources created in resource group: $AZURE_RESOURCE_GROUP"
echo "- App Service: $APP_SERVICE_NAME"
echo "- Storage Account: $STORAGE_ACCOUNT"
echo "- Search Service: $SEARCH_SERVICE"
echo "- OpenAI Service: $OPENAI_SERVICE"
echo ""
echo "Next steps:"
echo "1. Visit the application URL to test it"
echo "2. Upload additional documents through the web interface"
echo "3. Configure authentication if needed"
echo "4. Monitor the application through Azure Portal"

# Cleanup
rm -f deployment-parameters.json app-package.zip
rm -rf deploy/