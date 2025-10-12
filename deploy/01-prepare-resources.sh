#!/bin/bash

# Calgary Permit Bot - Resource Preparation Script
# This script creates all necessary Azure resources for the Calgary Permit Bot application

set -e  # Exit on any error

# Configuration
RESOURCE_GROUP="rg-calgarypermitbot"
LOCATION="westus2"
APP_SERVICE_PLAN="asp-calgarypermitbot"
BACKEND_APP_NAME="calgarypermitbot-backend"
FRONTEND_APP_NAME="calgarypermitbot-frontend"
STORAGE_ACCOUNT="calgarypermitbotstg$(date +%s | tail -c 6)"  # Random suffix to ensure uniqueness
SEARCH_SERVICE="calgarypermitbot-search"
OPENAI_SERVICE="calgarypermitbot-openai"
COSMOS_ACCOUNT="calgarypermitbot-cosmos"

echo "🚀 Starting Calgary Permit Bot Resource Preparation"
echo "=================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT"
echo ""

# Step 1: Create Resource Group
echo "📦 Creating resource group..."
echo "   Name: $RESOURCE_GROUP"
echo "   Location: $LOCATION"

if az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION; then
    echo "✅ Resource group created successfully"
    
    # Wait for resource group to be fully ready
    echo "⏳ Waiting for resource group to be fully ready..."
    TIMEOUT=60
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        if az group show --name $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>/dev/null | grep -q "Succeeded"; then
            echo "✅ Resource group is ready"
            break
        fi
        echo "   Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for resource group, but continuing..."
    fi
else
    echo "❌ Failed to create resource group"
    exit 1
fi

# Step 2: Create App Service Plan (S1 tier - Standard)
echo "🖥️  Creating App Service Plan..."
echo "   Plan Name: $APP_SERVICE_PLAN"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo "   SKU: S1 (Standard)"

if az appservice plan create \
    --name $APP_SERVICE_PLAN \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku S1 \
    --is-linux; then
    echo "✅ App Service Plan creation initiated"
    
    # Wait for App Service Plan to be fully ready
    echo "⏳ Waiting for App Service Plan to be ready..."
    TIMEOUT=300  # 5 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null)
        if [ "$STATUS" = "Succeeded" ]; then
            echo "✅ App Service Plan is ready"
            break
        elif [ "$STATUS" = "Failed" ]; then
            echo "❌ App Service Plan creation failed"
            exit 1
        fi
        echo "   Status: $STATUS - Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 10
        COUNTER=$((COUNTER + 10))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for App Service Plan creation"
        exit 1
    fi
else
    echo "❌ Failed to create App Service Plan"
    echo "This could be due to:"
    echo "   - Insufficient quota in the subscription"
    echo "   - Linux App Service Plans not available in $LOCATION"
    echo "   - Name conflict (unlikely with timestamp suffix)"
    echo ""
    echo "Trying to check existing plans in the resource group..."
    az appservice plan list --resource-group $RESOURCE_GROUP -o table || true
    exit 1
fi

# Step 3: Create Backend Web App
echo "🔧 Creating Backend Web App..."
echo "   Name: $BACKEND_APP_NAME"

if az webapp create \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN \
    --runtime "PYTHON|3.11" \
    --startup-file "python run_app.py"; then
    
    echo "✅ Backend Web App creation initiated"
    
    # Wait for backend web app to be ready
    echo "⏳ Waiting for Backend Web App to be ready..."
    TIMEOUT=300  # 5 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az webapp show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv 2>/dev/null)
        if [ "$STATUS" = "Running" ]; then
            echo "✅ Backend Web App is ready"
            break
        fi
        echo "   Status: $STATUS - Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 10
        COUNTER=$((COUNTER + 10))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for Backend Web App, but continuing..."
    fi
else
    echo "❌ Failed to create Backend Web App"
    exit 1
fi

# Enable managed identity for backend
echo "🔐 Enabling managed identity for backend..."
if az webapp identity assign \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP; then
    
    echo "✅ Managed identity assignment initiated"
    
    # Wait for managed identity to be ready
    echo "⏳ Waiting for managed identity to be ready..."
    TIMEOUT=120  # 2 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        PRINCIPAL_ID=$(az webapp identity show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "principalId" -o tsv 2>/dev/null)
        if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ]; then
            echo "✅ Managed identity is ready (Principal ID: $PRINCIPAL_ID)"
            break
        fi
        echo "   Waiting for principal ID... (${COUNTER}s/${TIMEOUT}s)"
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for managed identity, but continuing..."
    fi
else
    echo "❌ Failed to enable managed identity"
    exit 1
fi

# Step 4: Create Frontend Web App
echo "🎨 Creating Frontend Web App..."
echo "   Name: $FRONTEND_APP_NAME"

if az webapp create \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN \
    --runtime "NODE|20-lts"; then
    
    echo "✅ Frontend Web App creation initiated"
    
    # Wait for frontend web app to be ready
    echo "⏳ Waiting for Frontend Web App to be ready..."
    TIMEOUT=300  # 5 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az webapp show --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv 2>/dev/null)
        if [ "$STATUS" = "Running" ]; then
            echo "✅ Frontend Web App is ready"
            break
        fi
        echo "   Status: $STATUS - Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 10
        COUNTER=$((COUNTER + 10))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for Frontend Web App, but continuing..."
    fi
else
    echo "❌ Failed to create Frontend Web App"
    exit 1
fi

# Step 5: Create Storage Account
echo "💾 Creating Storage Account..."
echo "   Name: $STORAGE_ACCOUNT"

if az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false; then
    
    echo "✅ Storage Account creation initiated"
    
    # Wait for storage account to be ready
    echo "⏳ Waiting for Storage Account to be ready..."
    TIMEOUT=180  # 3 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null)
        if [ "$STATUS" = "Succeeded" ]; then
            echo "✅ Storage Account is ready"
            break
        fi
        echo "   Status: $STATUS - Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 10
        COUNTER=$((COUNTER + 10))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for Storage Account creation"
        exit 1
    fi
else
    echo "❌ Failed to create Storage Account"
    exit 1
fi

# Create content container
echo "📁 Creating storage container..."
if az storage container create \
    --name content \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login; then
    
    echo "✅ Storage container created"
    
    # Wait for container to be accessible
    echo "⏳ Waiting for storage container to be ready..."
    TIMEOUT=60
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        if az storage container show --name content --account-name $STORAGE_ACCOUNT --auth-mode login > /dev/null 2>&1; then
            echo "✅ Storage container is ready"
            break
        fi
        echo "   Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for storage container, but continuing..."
    fi
else
    echo "❌ Failed to create storage container"
    exit 1
fi

# Step 6: Create Azure AI Search Service
echo "🔍 Creating Azure AI Search Service..."
az search service create \
    --name $SEARCH_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku basic

# Step 7: Register AI Services provider (if not already registered)
echo "🤖 Registering AI Services provider..."
az provider register --namespace Microsoft.CognitiveServices || true

# Step 8: Create Azure OpenAI Service
echo "🧠 Creating Azure OpenAI Service..."
az cognitiveservices account create \
    --name $OPENAI_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --kind OpenAI \
    --sku S0

# Step 9: Deploy OpenAI Models
echo "📚 Deploying OpenAI models..."
# Deploy GPT-4o-mini model
az cognitiveservices account deployment create \
    --name $OPENAI_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --deployment-name gpt-4o-mini \
    --model-name gpt-4o-mini \
    --model-version "2024-07-18" \
    --model-format OpenAI \
    --capacity 10

# Deploy text-embedding-3-large model
az cognitiveservices account deployment create \
    --name $OPENAI_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --deployment-name text-embedding-3-large \
    --model-name text-embedding-3-large \
    --model-version "1" \
    --model-format OpenAI \
    --capacity 10

# Step 10: Register Cosmos DB provider (if not already registered)
echo "🌐 Registering Cosmos DB provider..."
az provider register --namespace Microsoft.DocumentDB || true

# Step 11: Create Cosmos DB Account
echo "🗄️  Creating Cosmos DB account..."
echo "   Name: $COSMOS_ACCOUNT"
echo "   This may take several minutes..."

if az cosmosdb create \
    --name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --kind GlobalDocumentDB \
    --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=False \
    --default-consistency-level Session \
    --enable-automatic-failover false \
    --enable-multiple-write-locations false \
    --capabilities EnableServerless; then
    
    echo "✅ Cosmos DB creation initiated"
    
    # Wait for Cosmos DB to be ready (this can take a while)
    echo "⏳ Waiting for Cosmos DB to be ready (this may take 5-10 minutes)..."
    TIMEOUT=600  # 10 minutes
    COUNTER=0
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az cosmosdb show --name $COSMOS_ACCOUNT --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null)
        if [ "$STATUS" = "Succeeded" ]; then
            echo "✅ Cosmos DB is ready"
            break
        fi
        echo "   Status: $STATUS - Waiting... (${COUNTER}s/${TIMEOUT}s)"
        sleep 30
        COUNTER=$((COUNTER + 30))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for Cosmos DB creation"
        exit 1
    fi
else
    echo "❌ Failed to create Cosmos DB account"
    exit 1
fi

# Create Cosmos DB database and container
echo "📊 Creating Cosmos DB database and container..."
az cosmosdb sql database create \
    --account-name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --name chathistory

az cosmosdb sql container create \
    --account-name $COSMOS_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --database-name chathistory \
    --name chatcontainer \
    --partition-key-path "/entra_oid"

# Step 12: Set up Role Assignments
echo "🔑 Setting up role assignments..."

# Get backend app principal ID
BACKEND_PRINCIPAL_ID=$(az webapp identity show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# Get resource IDs
STORAGE_ID=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query id -o tsv)
SEARCH_ID=$(az search service show --name $SEARCH_SERVICE --resource-group $RESOURCE_GROUP --query id -o tsv)
OPENAI_ID=$(az cognitiveservices account show --name $OPENAI_SERVICE --resource-group $RESOURCE_GROUP --query id -o tsv)
COSMOS_ID=$(az cosmosdb show --name $COSMOS_ACCOUNT --resource-group $RESOURCE_GROUP --query id -o tsv)

# Assign roles
echo "🔑 Assigning Storage Blob Data Contributor role..."
az role assignment create --assignee $BACKEND_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID

echo "🔑 Assigning Search roles..."
az role assignment create --assignee $BACKEND_PRINCIPAL_ID --role "Search Index Data Contributor" --scope $SEARCH_ID
az role assignment create --assignee $BACKEND_PRINCIPAL_ID --role "Search Service Contributor" --scope $SEARCH_ID

echo "🔑 Assigning OpenAI role..."
az role assignment create --assignee $BACKEND_PRINCIPAL_ID --role "Cognitive Services OpenAI User" --scope $OPENAI_ID

echo "🔑 Assigning Cosmos DB role..."
az role assignment create --assignee $BACKEND_PRINCIPAL_ID --role "Cosmos DB Account Reader Role" --scope $COSMOS_ID

# Wait for role assignments to propagate
echo "⏳ Waiting for role assignments to propagate..."
sleep 60
echo "✅ Role assignments completed"

# Step 13: Configure Backend App Settings
echo "⚙️  Configuring backend app settings..."

# Get connection information
STORAGE_CONNECTION=$(az storage account show-connection-string --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query connectionString -o tsv)
SEARCH_ENDPOINT=$(az search service show --name $SEARCH_SERVICE --resource-group $RESOURCE_GROUP --query hostName -o tsv)
OPENAI_ENDPOINT=$(az cognitiveservices account show --name $OPENAI_SERVICE --resource-group $RESOURCE_GROUP --query properties.endpoint -o tsv)

# Configure app settings
az webapp config appsettings set \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT \
        AZURE_STORAGE_CONTAINER=content \
        AZURE_SEARCH_SERVICE=$SEARCH_SERVICE \
        AZURE_SEARCH_INDEX=gptkbindex \
        AZURE_OPENAI_SERVICE=$OPENAI_SERVICE \
        AZURE_OPENAI_CHATGPT_DEPLOYMENT=gpt-4o-mini \
        AZURE_OPENAI_EMB_DEPLOYMENT=text-embedding-3-large \
        AZURE_COSMOSDB_ACCOUNT=$COSMOS_ACCOUNT \
        AZURE_CHAT_HISTORY_DATABASE=chathistory \
        AZURE_CHAT_HISTORY_CONTAINER=chatcontainer \
        AZURE_CHAT_HISTORY_VERSION=1 \
        USE_CHAT_HISTORY_COSMOS=true \
        OPENAI_HOST=azure \
        SCM_DO_BUILD_DURING_DEPLOYMENT=true \
        WEBSITE_RUN_FROM_PACKAGE=1

# Step 14: Save configuration to file
echo "💾 Saving configuration..."
cat > /tmp/deployment-config.env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
APP_SERVICE_PLAN=$APP_SERVICE_PLAN
BACKEND_APP_NAME=$BACKEND_APP_NAME
FRONTEND_APP_NAME=$FRONTEND_APP_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
SEARCH_SERVICE=$SEARCH_SERVICE
OPENAI_SERVICE=$OPENAI_SERVICE
COSMOS_ACCOUNT=$COSMOS_ACCOUNT
BACKEND_PRINCIPAL_ID=$BACKEND_PRINCIPAL_ID
STORAGE_CONNECTION=$STORAGE_CONNECTION
SEARCH_ENDPOINT=$SEARCH_ENDPOINT
OPENAI_ENDPOINT=$OPENAI_ENDPOINT
EOF

echo ""
echo "✅ Resource preparation completed successfully!"
echo "=================================================="
echo "✅ Resource Group: $RESOURCE_GROUP"
echo "✅ Backend App: https://$BACKEND_APP_NAME.azurewebsites.net"
echo "✅ Frontend App: https://$FRONTEND_APP_NAME.azurewebsites.net"
echo "✅ Storage Account: $STORAGE_ACCOUNT"
echo "✅ Search Service: $SEARCH_SERVICE"
echo "✅ OpenAI Service: $OPENAI_SERVICE"
echo "✅ Cosmos DB: $COSMOS_ACCOUNT"
echo ""
echo "📋 Configuration saved to: /tmp/deployment-config.env"
echo "🚀 Ready for deployment! Run ./02-deploy-app.sh next."