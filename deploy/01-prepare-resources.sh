#!/bin/bash

# Calgary Permit Bot - Resource Preparation Script
# This script creates all necessary Azure resources for the Calgary Permit Bot application

set -e  # Exit on any error

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    echo "📋 Configuration loaded from config.sh"
else
    echo "❌ Configuration file not found at $SCRIPT_DIR/config.sh"
    exit 1
fi

# Function to run Azure CLI commands with error capture
run_az_command() {
    local description="$1"
    shift  # Remove first argument, rest are the command
    
    echo "🔄 $description..."
    
    # Capture both stdout and stderr
    local output
    local exit_code
    output=$("$@" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "✅ $description completed successfully"
        # If there's useful output, show it
        if [ -n "$output" ] && ! echo "$output" | grep -q '^{.*}$'; then
            echo "$output"
        fi
    else
        echo "❌ $description failed"
        echo "Command: $*"
        echo "Error details:"
        echo "$output"
        return $exit_code
    fi
}

# Auto-detect subscription if not set
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "🔍 Auto-detecting Azure subscription..."
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
    if [ -n "$SUBSCRIPTION_ID" ]; then
        echo "✅ Using subscription: $SUBSCRIPTION_ID"
    else
        echo "❌ No active Azure subscription found. Please run 'az login' first."
        exit 1
    fi
fi

echo "🚀 Starting Calgary Permit Bot Resource Preparation"
echo "=================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Backend App: $BACKEND_APP_NAME"
echo "Frontend App: $FRONTEND_APP_NAME"
echo ""

# Check if user wants verbose output
if [ "$1" = "-v" ] || [ "$1" = "--verbose" ]; then
    VERBOSE=true
    echo "🔍 Verbose mode enabled - showing detailed Azure CLI output"
    echo ""
else
    VERBOSE=false
    echo "💡 Tip: Use '$0 --verbose' for detailed Azure CLI output"
    echo ""
fi

# Step 1: Create Resource Group
echo "📦 Creating resource group..."
echo "   Name: $RESOURCE_GROUP"
echo "   Location: $LOCATION"

# Capture both stdout and stderr for resource group creation
echo "Creating resource group..."
RG_OUTPUT=$(az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION 2>&1)
RG_EXIT_CODE=$?

if [ $RG_EXIT_CODE -eq 0 ]; then
    echo "✅ Resource group created successfully"
    
    # Quick check that resource group is ready (usually immediate)
    echo "⏳ Verifying resource group..."
    TIMEOUT=20  # 20 seconds max for resource group
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        if az group show --name $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>/dev/null | grep -qi "succeeded"; then
            echo "✅ Resource group is ready (took ${COUNTER}s)"
            break
        fi
        echo "   📦 Verifying resource group... (${COUNTER}s elapsed)"
        sleep 2
        COUNTER=$((COUNTER + 2))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Resource group verification timed out after ${TIMEOUT}s, but continuing..."
    fi
else
    echo "❌ Failed to create resource group"
    echo "Error details:"
    echo "$RG_OUTPUT"
    exit 1
fi

# Helper functions for resource detection by type (not name)
find_existing_resource() {
    local resource_type="$1"
    local storage_account="$2"  # Optional parameter for storage-related checks
    local cosmos_account="$3"   # Optional parameter for cosmos-related checks
    local openai_service="$4"   # Optional parameter for openai-related checks
    
    case "$resource_type" in
        "storage")
            # Find any storage account in the resource group
            az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null
            ;;
        "storage-container")
            # Find content container in the specified storage account
            if [ -n "$storage_account" ]; then
                az storage container list --account-name "$storage_account" --auth-mode login --query "[?name=='content'].name" -o tsv 2>/dev/null
            fi
            ;;
        "search") 
            # Find any search service in the resource group
            az search service list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null
            ;;
        "openai")
            # Find any cognitive services account with kind=OpenAI in the resource group
            az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'][0].name" -o tsv 2>/dev/null
            ;;
        "openai-deployment-gpt")
            # Find GPT model deployment in the specified OpenAI service
            if [ -n "$openai_service" ]; then
                az cognitiveservices account deployment list --name "$openai_service" --resource-group "$RESOURCE_GROUP" --query "[?contains(model.name, 'gpt')][0].name" -o tsv 2>/dev/null
            fi
            ;;
        "openai-deployment-embedding")
            # Find embedding model deployment in the specified OpenAI service
            if [ -n "$openai_service" ]; then
                az cognitiveservices account deployment list --name "$openai_service" --resource-group "$RESOURCE_GROUP" --query "[?contains(model.name, 'embedding')][0].name" -o tsv 2>/dev/null
            fi
            ;;
        "cosmos")
            # Find any Cosmos DB account in the resource group
            az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null
            ;;
        "cosmos-database")
            # Find chathistory database in the specified Cosmos DB account
            if [ -n "$cosmos_account" ]; then
                az cosmosdb sql database list --account-name "$cosmos_account" --resource-group "$RESOURCE_GROUP" --query "[?id=='chathistory'].id" -o tsv 2>/dev/null
            fi
            ;;
        "cosmos-container")
            # Find chatcontainer in the specified Cosmos DB account
            if [ -n "$cosmos_account" ]; then
                az cosmosdb sql container list --account-name "$cosmos_account" --database-name "chathistory" --resource-group "$RESOURCE_GROUP" --query "[?id=='chatcontainer'].id" -o tsv 2>/dev/null
            fi
            ;;
        "appplan")
            # Find any app service plan in the resource group
            az appservice plan list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null
            ;;
        "webapp-backend")
            # Find backend web app (Python runtime)
            az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(siteConfig.linuxFxVersion, 'PYTHON')][0].name" -o tsv 2>/dev/null
            ;;
        "webapp-frontend")
            # Find frontend web app (Node.js runtime) 
            az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(siteConfig.linuxFxVersion, 'NODE')][0].name" -o tsv 2>/dev/null
            ;;
    esac
}

echo ""
echo "🔧 Phase 1: Backend Infrastructure Services"  
echo "==========================================="
echo "🔍 Scanning resource group for existing resources..."
echo "   Resource Group: $RESOURCE_GROUP"
echo "   This will reuse any existing resources of the correct type"
echo ""

# Step 2: Create Storage Account FIRST (needed for document storage) 
echo "💾 Checking for existing Storage Account..."

# Check if any storage account already exists in the resource group
EXISTING_STORAGE=$(find_existing_resource "storage")
if [ -n "$EXISTING_STORAGE" ] && [ "$EXISTING_STORAGE" != "" ]; then
    echo "✅ Found existing Storage Account '$EXISTING_STORAGE' - skipping creation"
    export STORAGE_ACCOUNT="$EXISTING_STORAGE"
    echo "   Using existing: $STORAGE_ACCOUNT"
else
    echo "   No existing storage account found, creating: $STORAGE_ACCOUNT"

if az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --allow-blob-public-access false; then
    
    echo "✅ Storage Account creation initiated"
    
    # Wait for storage account to be ready (smart waiting)
    echo "⏳ Checking Storage Account status..."
    TIMEOUT=120  # 2 minutes max
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 Storage status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "succeeded" ]; then
            echo "✅ Storage Account is ready (took ${COUNTER}s)"
            break
        elif [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "failed" ]; then
            echo "❌ Storage Account creation failed"
            exit 1
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ Storage Account not found yet, still creating..."
        else
            echo "   💾 Status: $STATUS - continuing to wait..."
        fi
        
        sleep 8
        COUNTER=$((COUNTER + 8))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for Storage Account creation (${TIMEOUT}s)"
        echo "Final status: $STATUS"
        exit 1
    fi
else
    echo "❌ Failed to create Storage Account"
    exit 1
fi

# Step 3: Create storage container
echo "📁 Checking for existing storage container..."
EXISTING_CONTAINER=$(find_existing_resource "storage-container" "$STORAGE_ACCOUNT")
if [ -n "$EXISTING_CONTAINER" ] && [ "$EXISTING_CONTAINER" != "" ]; then
    echo "✅ Found existing storage container 'content' - skipping creation"
else
    echo "   No existing content container found, creating..."
    if az storage container create \
        --name content \
        --account-name $STORAGE_ACCOUNT \
        --auth-mode login; then
        
        echo "✅ Storage container created"
    
    # Wait for container to be accessible (quick check)
    echo "⏳ Verifying storage container access..."
    TIMEOUT=30  # 30 seconds max for container
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        if az storage container show --name content --account-name $STORAGE_ACCOUNT --auth-mode login > /dev/null 2>&1; then
            echo "✅ Storage container is accessible (took ${COUNTER}s)"
            break
        fi
        
        echo "   📁 Checking container access... (${COUNTER}s elapsed)"
        sleep 3
        COUNTER=$((COUNTER + 3))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  Storage container access check timed out after ${TIMEOUT}s, but continuing..."
    fi
    else
        echo "❌ Failed to create storage container"
        exit 1
    fi
fi

# Step 4: Create Azure AI Search Service with retry logic
echo "🔍 Checking for existing AI Search Service..."

# Check if any search service already exists in the resource group
EXISTING_SEARCH=$(find_existing_resource "search")
if [ -n "$EXISTING_SEARCH" ] && [ "$EXISTING_SEARCH" != "" ]; then
    echo "✅ Found existing AI Search Service '$EXISTING_SEARCH' - skipping creation"
    export SEARCH_SERVICE="$EXISTING_SEARCH"
    echo "   Using existing: $SEARCH_SERVICE"
else
    echo "   No existing search service found, creating: $SEARCH_SERVICE"

# Function to create search service with retry logic
create_search_service() {
    local service_name="$1"
    local max_attempts=5
    local attempt=1
    local wait_time=30
    
    while [ $attempt -le $max_attempts ]; do
        echo "   Attempt $attempt/$max_attempts: Creating search service '$service_name'..."
        
        # Try to create the search service
        if az search service create \
            --name "$service_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku basic 2>/dev/null; then
            
            echo "✅ AI Search Service creation initiated successfully"
            export SEARCH_SERVICE="$service_name"
            
            # Wait for the service to be ready
            echo "⏳ Waiting for AI Search Service to be ready..."
            local status_timeout=300  # 5 minutes max
            local status_counter=0
            
            while [ $status_counter -lt $status_timeout ]; do
                local status=$(az search service show --name "$service_name" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                
                echo "   🔍 Status: '$status' (${status_counter}s elapsed)"
                
                # Convert status to lowercase for comparison (Azure sometimes returns different cases)
                status_lower=$(echo "$status" | tr '[:upper:]' '[:lower:]')
                
                if [ "$status_lower" = "succeeded" ] || [ "$status_lower" = "running" ]; then
                    echo "✅ AI Search Service is ready (took ${status_counter}s)"
                    return 0
                elif [ "$status_lower" = "failed" ]; then
                    echo "❌ AI Search Service provisioning failed"
                    return 1
                elif [ "$status" = "NotFound" ] && [ $status_counter -gt 60 ]; then
                    echo "❌ Service not found after creation - something went wrong"
                    return 1
                fi
                
                sleep 10
                status_counter=$((status_counter + 10))
            done
            
            echo "❌ Timeout waiting for service to be ready"
            return 1
        else
            # Check if it's a ServiceDeleting error or name conflict
            ERROR_OUTPUT=$(az search service create \
                --name "$service_name" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --sku basic 2>&1 || true)
            
            if echo "$ERROR_OUTPUT" | grep -q "ServiceDeleting\|background operation"; then
                echo "   ⏳ Service '$service_name' is being deleted in background, waiting ${wait_time}s..."
                sleep $wait_time
                wait_time=$((wait_time * 2))  # Exponential backoff
            elif echo "$ERROR_OUTPUT" | grep -q "already exists\|AlreadyExists"; then
                echo "   ⚠️  Service '$service_name' already exists, trying with different name..."
                service_name="${SEARCH_SERVICE%%-*}-search-$(date +%s | tail -c 8)"
                echo "   🔄 New name: $service_name"
            else
                echo "   ❌ Unexpected error: $ERROR_OUTPUT"
                if [ $attempt -eq $max_attempts ]; then
                    return 1
                fi
                sleep $wait_time
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "❌ Failed to create search service after $max_attempts attempts"
    return 1
}

    # Call the function with retry logic
    if create_search_service "$SEARCH_SERVICE"; then
        echo "✅ AI Search Service creation and provisioning completed"
    else
        echo "❌ Failed to create AI Search Service"
        exit 1
    fi
fi

# Step 5: Register AI Services provider and create OpenAI Service
echo "🤖 Registering AI Services provider..."
az provider register --namespace Microsoft.CognitiveServices || true

echo "🧠 Checking Azure OpenAI Service..."
echo "   Name: $OPENAI_SERVICE"

# Function to create OpenAI service with retry logic and quota handling
create_openai_service() {
    local service_name="$1"
    local max_attempts=3
    local attempt=1
    local wait_time=20
    
    while [ $attempt -le $max_attempts ]; do
        echo "   Attempt $attempt/$max_attempts: Creating OpenAI service '$service_name'..."
        
        ERROR_OUTPUT=$(az cognitiveservices account create \
            --name "$service_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 2>&1 || true)
        
        if echo "$ERROR_OUTPUT" | grep -q "SpecialFeatureOrQuotaIdRequired\|QuotaId.*required"; then
            echo "   ⚠️  Azure OpenAI access not available for this subscription"
            echo "   💡 This requires special approval from Microsoft"
            echo "   📋 To request access:"
            echo "      1. Visit: https://aka.ms/oai/access"
            echo "      2. Fill out the Azure OpenAI access request form"
            echo "      3. Wait for approval (can take several days)"
            echo ""
            echo "   🔄 Continuing deployment without OpenAI service..."
            echo "   📝 You can add OpenAI service later once access is approved"
            
            # Set a flag to indicate OpenAI is not available
            export OPENAI_UNAVAILABLE=true
            export OPENAI_SERVICE=""
            return 2  # Special return code for quota issue
            
        elif echo "$ERROR_OUTPUT" | grep -q "already exists\|AlreadyExists"; then
            echo "   ⚠️  Service '$service_name' already exists, trying with different name..."
            service_name="${OPENAI_SERVICE%%-*}-openai-$(date +%s | tail -c 8)"
            echo "   🔄 New name: $service_name"
            
        elif echo "$ERROR_OUTPUT" | grep -q -v "ERROR\|error"; then
            echo "✅ OpenAI Service creation initiated successfully"
            export OPENAI_SERVICE="$service_name"
            return 0
            
        else
            echo "   ❌ Error: $ERROR_OUTPUT"
            if [ $attempt -eq $max_attempts ]; then
                return 1
            fi
            sleep $wait_time
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Check if any OpenAI service already exists in the resource group
EXISTING_OPENAI=$(find_existing_resource "openai")
if [ -n "$EXISTING_OPENAI" ] && [ "$EXISTING_OPENAI" != "" ]; then
    echo "✅ Found existing OpenAI Service '$EXISTING_OPENAI' - skipping creation"
    export OPENAI_SERVICE="$EXISTING_OPENAI"
    echo "   Using existing: $OPENAI_SERVICE"
    OPENAI_EXIT_CODE=0
    DEPLOY_MODELS=true
else
    echo "   No existing OpenAI service found, creating: $OPENAI_SERVICE"
    OPENAI_RESULT=$(create_openai_service "$OPENAI_SERVICE")
    OPENAI_EXIT_CODE=$?
fi

if [ $OPENAI_EXIT_CODE -eq 0 ]; then
    echo "✅ OpenAI Service creation initiated"
    
    # Wait for OpenAI Service to be ready
    echo "⏳ Checking OpenAI Service status..."
    TIMEOUT=300  # 5 minutes max
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az cognitiveservices account show --name $OPENAI_SERVICE --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 OpenAI status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "succeeded" ]; then
            echo "✅ OpenAI Service is ready (took ${COUNTER}s)"
            break
        elif [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "failed" ]; then
            echo "❌ OpenAI Service creation failed"
            exit 1
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ OpenAI Service not found yet, still creating..."
        else
            echo "   🧠 Status: $STATUS - continuing to wait..."
        fi
        
        sleep 15
        COUNTER=$((COUNTER + 15))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for OpenAI Service creation (${TIMEOUT}s)"
        exit 1
    fi
    
    # Step 6: Deploy OpenAI Models (wait for each model)
    echo "📚 Deploying OpenAI models..."
    DEPLOY_MODELS=true
    
elif [ $OPENAI_EXIT_CODE -eq 2 ]; then
    echo "⚠️  Skipping OpenAI model deployment - service not available"
    DEPLOY_MODELS=false
else
    echo "❌ Failed to create OpenAI Service"
    exit 1
fi
fi

# Deploy models only if OpenAI service is available
if [ "$DEPLOY_MODELS" = "true" ] && [ -n "$OPENAI_SERVICE" ]; then

# Deploy GPT-4o-mini model
echo "   Checking for existing GPT model deployment..."
EXISTING_GPT=$(find_existing_resource "openai-deployment-gpt" "" "" "$OPENAI_SERVICE")
if [ -n "$EXISTING_GPT" ] && [ "$EXISTING_GPT" != "" ]; then
    echo "✅ Found existing GPT model deployment '$EXISTING_GPT' - skipping creation"
else
    echo "   No existing GPT model deployment found, deploying gpt-4o-mini..."
    if az cognitiveservices account deployment create \
        --name $OPENAI_SERVICE \
        --resource-group $RESOURCE_GROUP \
        --deployment-name gpt-4o-mini \
        --model-name gpt-4o-mini \
        --model-version "2024-07-18" \
        --model-format OpenAI \
        --capacity 10; then
        
        echo "✅ GPT-4o-mini model deployed"
    else
        echo "❌ Failed to deploy GPT-4o-mini model"
        exit 1
    fi
fi

# Deploy text-embedding model
echo "   Checking for existing embedding model deployment..."
EXISTING_EMBEDDING=$(find_existing_resource "openai-deployment-embedding" "" "" "$OPENAI_SERVICE")
if [ -n "$EXISTING_EMBEDDING" ] && [ "$EXISTING_EMBEDDING" != "" ]; then
    echo "✅ Found existing embedding model deployment '$EXISTING_EMBEDDING' - skipping creation"
else
    echo "   No existing embedding model deployment found, deploying text-embedding-3-large..."
    if az cognitiveservices account deployment create \
        --name $OPENAI_SERVICE \
        --resource-group $RESOURCE_GROUP \
        --deployment-name text-embedding-3-large \
        --model-name text-embedding-3-large \
        --model-version "1" \
        --model-format OpenAI \
        --capacity 10; then
        
        echo "✅ text-embedding-3-large model deployed"
    else
        echo "❌ Failed to deploy text-embedding-3-large model"
        exit 1
    fi
fi

else
    echo "📋 OpenAI models skipped - service not available"
    echo "   You can deploy models later once OpenAI access is approved"
fi

# Step 7: Register Cosmos DB provider and create Cosmos DB
echo "🌐 Registering Cosmos DB provider..."
az provider register --namespace Microsoft.DocumentDB || true

echo "🗄️  Checking for existing Cosmos DB account..."

# Check if any Cosmos DB account already exists in the resource group
EXISTING_COSMOS=$(find_existing_resource "cosmos")
if [ -n "$EXISTING_COSMOS" ] && [ "$EXISTING_COSMOS" != "" ]; then
    echo "✅ Found existing Cosmos DB account '$EXISTING_COSMOS' - skipping creation"
    export COSMOS_ACCOUNT="$EXISTING_COSMOS"
    echo "   Using existing: $COSMOS_ACCOUNT"
else
    echo "   No existing Cosmos DB found, creating: $COSMOS_ACCOUNT"
    echo "   This may take several minutes..."

# Function to create Cosmos DB with retry logic
create_cosmos_db() {
    local account_name="$1"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "   Attempt $attempt/$max_attempts: Creating Cosmos DB '$account_name'..."
        
        if az cosmosdb create \
            --name "$account_name" \
            --resource-group "$RESOURCE_GROUP" \
            --kind GlobalDocumentDB \
            --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=False \
            --default-consistency-level Session \
            --enable-automatic-failover false \
            --enable-multiple-write-locations false \
            --capabilities EnableServerless 2>/dev/null; then
            
            echo "✅ Cosmos DB creation initiated successfully"
            export COSMOS_ACCOUNT="$account_name"
            return 0
        else
            ERROR_OUTPUT=$(az cosmosdb create \
                --name "$account_name" \
                --resource-group "$RESOURCE_GROUP" \
                --kind GlobalDocumentDB \
                --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=False \
                --default-consistency-level Session \
                --enable-automatic-failover false \
                --enable-multiple-write-locations false \
                --capabilities EnableServerless 2>&1 || true)
            
            if echo "$ERROR_OUTPUT" | grep -q "already exists\|AlreadyExists"; then
                echo "   ⚠️  Account '$account_name' already exists, trying with different name..."
                account_name="${COSMOS_ACCOUNT%%-*}-cosmos-$(date +%s | tail -c 8)"
                echo "   🔄 New name: $account_name"
            else
                echo "   ❌ Error: $ERROR_OUTPUT"
                if [ $attempt -eq $max_attempts ]; then
                    return 1
                fi
                sleep 30
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

if create_cosmos_db "$COSMOS_ACCOUNT"; then
    
    echo "✅ Cosmos DB creation initiated"
    
    # Wait for Cosmos DB to be ready (smart waiting with longer intervals)
    echo "⏳ Checking Cosmos DB status (this may take several minutes)..."
    TIMEOUT=600  # 10 minutes max
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az cosmosdb show --name $COSMOS_ACCOUNT --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 Cosmos status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "succeeded" ]; then
            echo "✅ Cosmos DB is ready (took ${COUNTER}s)"
            break
        elif [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "failed" ]; then
            echo "❌ Cosmos DB creation failed"
            exit 1
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ Cosmos DB not found yet, still creating..."
        else
            echo "   🗄️  Status: $STATUS - Cosmos DB takes time..."
        fi
        
        sleep 30
        COUNTER=$((COUNTER + 30))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for Cosmos DB creation (${TIMEOUT}s)"
        exit 1
    fi
else
    echo "❌ Failed to create Cosmos DB account"
    exit 1
fi
fi

# Step 8: Create Cosmos DB database and container
echo "📊 Checking for existing Cosmos DB database..."
EXISTING_DB=$(find_existing_resource "cosmos-database" "$COSMOS_ACCOUNT")
if [ -n "$EXISTING_DB" ] && [ "$EXISTING_DB" != "" ]; then
    echo "✅ Found existing Cosmos DB database 'chathistory' - skipping creation"
else
    echo "   No existing chathistory database found, creating..."
    if az cosmosdb sql database create \
        --account-name $COSMOS_ACCOUNT \
        --resource-group $RESOURCE_GROUP \
        --name chathistory; then
        echo "✅ Cosmos DB database created"
    else
        echo "❌ Failed to create Cosmos DB database"
        exit 1
    fi
fi

echo "📋 Checking for existing Cosmos DB container..."
EXISTING_CONTAINER=$(find_existing_resource "cosmos-container" "$COSMOS_ACCOUNT")
if [ -n "$EXISTING_CONTAINER" ] && [ "$EXISTING_CONTAINER" != "" ]; then
    echo "✅ Found existing Cosmos DB container 'chatcontainer' - skipping creation"
else
    echo "   No existing chatcontainer found, creating..."
    if az cosmosdb sql container create \
        --account-name $COSMOS_ACCOUNT \
        --resource-group $RESOURCE_GROUP \
        --database-name chathistory \
        --name chatcontainer \
        --partition-key-path "/entra_oid"; then
        echo "✅ Cosmos DB container created"
    else
        echo "❌ Failed to create Cosmos DB container"
        exit 1
    fi
fi

echo ""
echo "🔧 Phase 2: Creating App Service Infrastructure"
echo "==============================================="

# Step 9: Create App Service Plan
echo "🖥️  Checking for existing App Service Plan..."

# Check if any App Service Plan already exists in the resource group
EXISTING_PLAN=$(find_existing_resource "appplan")
if [ -n "$EXISTING_PLAN" ] && [ "$EXISTING_PLAN" != "" ]; then
    echo "✅ Found existing App Service Plan '$EXISTING_PLAN' - skipping creation"
    export APP_SERVICE_PLAN="$EXISTING_PLAN"
    echo "   Using existing: $APP_SERVICE_PLAN"
else
    echo "   No existing app service plan found, creating: $APP_SERVICE_PLAN"
    echo "   Resource Group: $RESOURCE_GROUP"
    echo "   Location: $LOCATION"
    echo "   SKU: $APP_SERVICE_SKU (Basic)"

# Capture both stdout and stderr for App Service Plan creation
echo "Creating App Service Plan..."
ASP_OUTPUT=$(az appservice plan create \
    --name $APP_SERVICE_PLAN \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku $APP_SERVICE_SKU \
    --is-linux 2>&1)
ASP_EXIT_CODE=$?

if [ $ASP_EXIT_CODE -eq 0 ]; then
    echo "✅ App Service Plan creation initiated"
    
    # Wait for App Service Plan to be ready (smart waiting)
    echo "⏳ Checking App Service Plan status..."
    TIMEOUT=300  # 5 minutes max
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        # Get status and handle potential errors
        STATUS=$(az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 Current status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "succeeded" ]; then
            echo "✅ App Service Plan is ready (took ${COUNTER}s)"
            break
        elif [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "failed" ]; then
            echo "❌ App Service Plan creation failed during provisioning"
            az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP 2>/dev/null || echo "Could not get plan details"
            exit 1
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ App Service Plan not found yet, still creating..."
        else
            echo "   📋 Status: $STATUS - continuing to wait..."
        fi
        
        sleep 10
        COUNTER=$((COUNTER + 10))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "❌ Timeout waiting for App Service Plan creation (${TIMEOUT}s)"
        echo "Final status check:"
        az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP 2>/dev/null || echo "App Service Plan not found"
        exit 1
    fi
else
    echo "❌ Failed to create App Service Plan"
    echo "Error details:"
    echo "$ASP_OUTPUT"
    echo ""
    echo "This could be due to:"
    echo "   - Insufficient quota in the subscription"
    echo "   - Linux App Service Plans not available in $LOCATION"
    echo "   - Name conflict (unlikely with timestamp suffix)"
    echo "   - SKU S1 not available in this region/subscription"
    echo ""
    echo "Checking existing plans in the resource group..."
    az appservice plan list --resource-group $RESOURCE_GROUP -o table || true
    echo ""
    echo "Checking available SKUs in $LOCATION..."
    az appservice list-locations --sku S1 --linux-workers-enabled --query "[?contains(name, '$LOCATION')]" -o table || true
    exit 1
fi
fi

# Step 11: Create Backend Web App
echo "🔧 Checking for existing Backend Web App..."

# Check if any Python backend web app already exists in the resource group
EXISTING_BACKEND=$(find_existing_resource "webapp-backend")
if [ -n "$EXISTING_BACKEND" ] && [ "$EXISTING_BACKEND" != "" ]; then
    echo "✅ Found existing Backend Web App '$EXISTING_BACKEND' - skipping creation"
    export BACKEND_APP_NAME="$EXISTING_BACKEND"
    echo "   Using existing: $BACKEND_APP_NAME"
else
    echo "   No existing backend web app found, creating: $BACKEND_APP_NAME"

# Capture both stdout and stderr for Backend Web App creation
if az webapp create \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN \
    --runtime "PYTHON|3.11" \
    --startup-file "python run_app.py"; then
    
    echo "✅ Backend Web App creation initiated"
    
    # Wait for backend web app to be ready (smart waiting)
    echo "⏳ Checking Backend Web App status..."
    TIMEOUT=120  # 2 minutes max for web apps
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az webapp show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 Backend app status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "running" ] || [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "stopped" ]; then
            echo "✅ Backend Web App is ready (took ${COUNTER}s, status: $STATUS)"
            break
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ Backend Web App not found yet, still creating..."
        else
            echo "   📱 Status: $STATUS - continuing to wait..."
        fi
        
        sleep 8
        COUNTER=$((COUNTER + 8))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "✅ Backend Web App creation completed after ${TIMEOUT}s (final status: $STATUS)"
    fi
else
    echo "❌ Failed to create Backend Web App"
    exit 1
fi
fi

# Step 12: Create Frontend Web App
echo "🎨 Checking for existing Frontend Web App..."

# Check if any Node.js frontend web app already exists in the resource group
EXISTING_FRONTEND=$(find_existing_resource "webapp-frontend")
if [ -n "$EXISTING_FRONTEND" ] && [ "$EXISTING_FRONTEND" != "" ]; then
    echo "✅ Found existing Frontend Web App '$EXISTING_FRONTEND' - skipping creation"
    export FRONTEND_APP_NAME="$EXISTING_FRONTEND"
    echo "   Using existing: $FRONTEND_APP_NAME"
else
    echo "   No existing frontend web app found, creating: $FRONTEND_APP_NAME"

if az webapp create \
    --name $FRONTEND_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --plan $APP_SERVICE_PLAN \
    --runtime "NODE|20-lts"; then
    
    echo "✅ Frontend Web App creation initiated"
    
    # Wait for frontend web app to be ready (smart waiting)
    echo "⏳ Checking Frontend Web App status..."
    TIMEOUT=120  # 2 minutes max for web apps
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        STATUS=$(az webapp show --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv 2>/dev/null || echo "NotFound")
        
        echo "   🔍 Frontend app status: '$STATUS' (${COUNTER}s elapsed)"
        
        if [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "running" ] || [ "$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')" = "stopped" ]; then
            echo "✅ Frontend Web App is ready (took ${COUNTER}s, status: $STATUS)"
            break
        elif [ "$STATUS" = "NotFound" ]; then
            echo "   ⏳ Frontend Web App not found yet, still creating..."
        else
            echo "   🌐 Status: $STATUS - continuing to wait..."
        fi
        
        sleep 8
        COUNTER=$((COUNTER + 8))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "✅ Frontend Web App creation completed after ${TIMEOUT}s (final status: $STATUS)"
    fi
else
    echo "❌ Failed to create Frontend Web App"
    exit 1
fi
fi

echo ""
echo "🔧 Phase 3: Configuring Identity and Permissions"
echo "================================================"

# Step 13: Enable managed identity for backend
echo "🔐 Enabling managed identity for backend..."
if az webapp identity assign \
    --name $BACKEND_APP_NAME \
    --resource-group $RESOURCE_GROUP; then
    
    echo "✅ Managed identity assignment initiated"
    
    # Wait for managed identity to be ready (smart waiting)
    echo "⏳ Checking managed identity status..."
    TIMEOUT=60  # 1 minute max for identity
    COUNTER=0
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        PRINCIPAL_ID=$(az webapp identity show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "principalId" -o tsv 2>/dev/null || echo "")
        
        echo "   🔍 Checking principal ID... (${COUNTER}s elapsed)"
        
        if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ] && [ "$PRINCIPAL_ID" != "" ]; then
            echo "✅ Managed identity is ready (Principal ID: $PRINCIPAL_ID, took ${COUNTER}s)"
            break
        else
            echo "   🔐 Principal ID not available yet (current: '$PRINCIPAL_ID')"
        fi
        
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        PRINCIPAL_ID=$(az webapp identity show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "principalId" -o tsv 2>/dev/null || echo "")
        if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ] && [ "$PRINCIPAL_ID" != "" ]; then
            echo "✅ Managed identity ready (Principal ID: $PRINCIPAL_ID)"
        else
            echo "❌ Failed to get managed identity principal ID"
            exit 1
        fi
    fi
else
    echo "❌ Failed to enable managed identity"
    exit 1
fi



echo ""
echo "🔧 Phase 4: Configuring Application Settings"
echo "============================================"

# Step 15: Configure Backend App Settings
echo "⚙️  Configuring backend app settings..."

# Get connection information
echo "   Getting service endpoints..."
STORAGE_CONNECTION=$(az storage account show-connection-string --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query connectionString -o tsv)
SEARCH_ENDPOINT=$(az search service show --name $SEARCH_SERVICE --resource-group $RESOURCE_GROUP --query hostName -o tsv)

# Get OpenAI endpoint only if service exists
if [ -n "$OPENAI_SERVICE" ] && [ "$OPENAI_UNAVAILABLE" != "true" ]; then
    OPENAI_ENDPOINT=$(az cognitiveservices account show --name $OPENAI_SERVICE --resource-group $RESOURCE_GROUP --query properties.endpoint -o tsv)
    echo "   OpenAI Endpoint: $OPENAI_ENDPOINT"
else
    OPENAI_ENDPOINT=""
    echo "   OpenAI Endpoint: [Not available - requires access approval]"
fi

COSMOS_ENDPOINT=$(az cosmosdb show --name $COSMOS_ACCOUNT --resource-group $RESOURCE_GROUP --query documentEndpoint -o tsv)

echo "   Storage Connection: [hidden for security]"
echo "   Search Endpoint: https://$SEARCH_ENDPOINT"
echo "   Cosmos Endpoint: $COSMOS_ENDPOINT"

# Configure app settings
echo "   Configuring backend app settings..."
if az webapp config appsettings set \
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
        AZURE_COSMOSDB_ENDPOINT=$COSMOS_ENDPOINT \
        AZURE_CHAT_HISTORY_DATABASE=chathistory \
        AZURE_CHAT_HISTORY_CONTAINER=chatcontainer \
        AZURE_CHAT_HISTORY_VERSION=1 \
        USE_CHAT_HISTORY_COSMOS=true \
        OPENAI_HOST=azure \
        SCM_DO_BUILD_DURING_DEPLOYMENT=true \
        WEBSITE_RUN_FROM_PACKAGE=1 > /dev/null; then
    
    echo "✅ Backend app settings configured successfully"
else
    echo "❌ Failed to configure backend app settings"
    exit 1
fi

# Step 14: Save configuration to file
echo "💾 Saving configuration..."
cat > /tmp/deployment-config.env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
APP_SERVICE_PLAN=$APP_SERVICE_PLAN
APP_SERVICE_SKU=$APP_SERVICE_SKU
BACKEND_APP_NAME=$BACKEND_APP_NAME
FRONTEND_APP_NAME=$FRONTEND_APP_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
STORAGE_CONTAINER=$STORAGE_CONTAINER
SEARCH_SERVICE=$SEARCH_SERVICE
OPENAI_SERVICE=$OPENAI_SERVICE
COSMOS_ACCOUNT=$COSMOS_ACCOUNT
COSMOS_DATABASE=$COSMOS_DATABASE
COSMOS_CONTAINER=$COSMOS_CONTAINER
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

if [ -n "$OPENAI_SERVICE" ] && [ "$OPENAI_UNAVAILABLE" != "true" ]; then
    echo "✅ OpenAI Service: $OPENAI_SERVICE"
else
    echo "⚠️  OpenAI Service: Not available (requires access approval)"
    echo "   📋 To request access: https://aka.ms/oai/access"
fi

echo "✅ Cosmos DB: $COSMOS_ACCOUNT"
echo ""
echo "📋 Configuration saved to: /tmp/deployment-config.env"

if [ "$OPENAI_UNAVAILABLE" = "true" ]; then
    echo ""
    echo "⚠️  IMPORTANT: OpenAI service is not available"
    echo "   The application may have limited AI functionality until OpenAI access is approved"
    echo "   You can still proceed with deployment using other Azure services"
    echo ""
fi

echo "🚀 Ready for deployment! Run ./02-deploy-app.sh next."