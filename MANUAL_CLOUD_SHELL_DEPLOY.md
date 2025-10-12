# Manual Deployment for Azure Cloud Shell
# =====================================

## Step 1: Set up environment variables
```bash
export AZURE_ENV_NAME="calgarypermitbot"
export AZURE_LOCATION="eastus"
export AZURE_RESOURCE_GROUP="rg-calgarypermitbot"
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## Step 2: Create resource group
```bash
az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION
```

## Step 3: Create App Service Plan and Web App
```bash
# Create App Service Plan
az appservice plan create \
  --name "${AZURE_ENV_NAME}-plan" \
  --resource-group $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION \
  --sku B1 \
  --is-linux

# Create Web App
az webapp create \
  --name "${AZURE_ENV_NAME}-app" \
  --resource-group $AZURE_RESOURCE_GROUP \
  --plan "${AZURE_ENV_NAME}-plan" \
  --runtime "PYTHON|3.11"
```

## Step 4: Build and deploy the application
```bash
# Build frontend (if exists)
cd app/frontend && npm install && npm run build && cd ../..

# Package backend
mkdir deploy
cp -r app/backend/* deploy/
if [ -d "app/frontend/dist" ]; then
  mkdir -p deploy/static
  cp -r app/frontend/dist/* deploy/static/
fi

# Add gunicorn to requirements if not present
if ! grep -q "gunicorn" deploy/requirements.txt; then
  echo "gunicorn>=21.2.0" >> deploy/requirements.txt
fi

# Create deployment package
cd deploy && zip -r ../app-package.zip . && cd ..

# Deploy
az webapp deployment source config-zip \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name "${AZURE_ENV_NAME}-app" \
  --src app-package.zip
```

## Step 5: Configure Web App
```bash
# Set basic configuration
az webapp config appsettings set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name "${AZURE_ENV_NAME}-app" \
  --settings \
    SCM_DO_BUILD_DURING_DEPLOYMENT=true \
    ENABLE_ORYX_BUILD=true \
    RUNNING_IN_PRODUCTION=true

# Set startup command
az webapp config set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name "${AZURE_ENV_NAME}-app" \
  --startup-file "gunicorn -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 main:app"
```

## Step 6: Create AI services manually (optional)
```bash
# Create OpenAI service
az cognitiveservices account create \
  --name "${AZURE_ENV_NAME}-openai" \
  --resource-group $AZURE_RESOURCE_GROUP \
  --location "eastus" \
  --kind "OpenAI" \
  --sku "S0"

# Create AI Search service
az search service create \
  --name "${AZURE_ENV_NAME}-search" \
  --resource-group $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION \
  --sku "basic"

# Create Storage Account
az storage account create \
  --name "${AZURE_ENV_NAME}storage" \
  --resource-group $AZURE_RESOURCE_GROUP \
  --location $AZURE_LOCATION \
  --sku "Standard_LRS"
```

## Step 7: Get your app URL
```bash
az webapp show --resource-group $AZURE_RESOURCE_GROUP --name "${AZURE_ENV_NAME}-app" --query 'defaultHostName' -o tsv
```