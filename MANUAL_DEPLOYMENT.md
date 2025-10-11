# Manual Deployment Steps (Alternative to deploy-to-azure.sh)

## Prerequisites
- Access to Azure Cloud Shell or Azure CLI installed locally
- Azure subscription with appropriate permissions

## Step-by-Step Manual Deployment

### 1. Set Environment Variables
```bash
export AZURE_ENV_NAME="calgarypermitbot"
export AZURE_LOCATION="eastus" 
export AZURE_RESOURCE_GROUP="rg-calgarypermitbot"
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
```

### 2. Create Resource Group
```bash
az group create --name $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION
```

### 3. Deploy Infrastructure
```bash
# Create parameters file
cat > deployment-parameters.json << EOF
{
  "environmentName": {"value": "$AZURE_ENV_NAME"},
  "location": {"value": "$AZURE_LOCATION"},
  "principalId": {"value": "$AZURE_PRINCIPAL_ID"}
}
EOF

# Deploy using Bicep
az deployment sub create \
  --name "calgarypermitbot-deployment" \
  --location $AZURE_LOCATION \
  --template-file infra/main.bicep \
  --parameters @deployment-parameters.json
```

### 4. Build and Deploy Application
```bash
# Build frontend
cd app/frontend && npm install && npm run build && cd ../..

# Get App Service name
APP_SERVICE_NAME=$(az webapp list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)

# Deploy using zip
cd app/backend
zip -r ../../app-package.zip .
cd ../..

az webapp deployment source config-zip \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --src app-package.zip
```

### 5. Configure Settings
```bash
# Get resource names
STORAGE_ACCOUNT=$(az storage account list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)
SEARCH_SERVICE=$(az search service list --resource-group $AZURE_RESOURCE_GROUP --query '[0].name' -o tsv)
OPENAI_SERVICE=$(az cognitiveservices account list --resource-group $AZURE_RESOURCE_GROUP --query '[?kind==`OpenAI`].name' -o tsv)

# Set app settings
az webapp config appsettings set \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --settings \
    AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT \
    AZURE_SEARCH_SERVICE=$SEARCH_SERVICE \
    AZURE_OPENAI_SERVICE=$OPENAI_SERVICE
```