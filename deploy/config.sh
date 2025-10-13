# Calgary Permit Bot Deployment Configuration
# This file contains all deployment settings and can be sourced by scripts

# Basic Configuration
export RESOURCE_GROUP="rg-calgarypermitbot"
export LOCATION="westus2"
export SUBSCRIPTION_ID=""  # Will be set automatically if not provided

# App Service Configuration
export APP_SERVICE_PLAN="asp-calgarypermitbot"
export APP_SERVICE_SKU="B1"  # Basic tier as requested
export BACKEND_APP_NAME="calgarypermitbot-backend"
export FRONTEND_APP_NAME="calgarypermitbot-frontend"

# Storage Configuration
export STORAGE_ACCOUNT="calgarypermitbotstg$(date +%s | tail -c 6)"
export STORAGE_CONTAINER="content"

# Azure AI Search Configuration
export SEARCH_SERVICE="calgarypermitbot-search"
export SEARCH_SKU="basic"

# Azure OpenAI Configuration
export OPENAI_SERVICE="calgarypermitbot-openai"
export OPENAI_SKU="S0"

# Cosmos DB Configuration
export COSMOS_ACCOUNT="calgarypermitbot-cosmos"
export COSMOS_DATABASE="chathistory"
export COSMOS_CONTAINER="chatcontainer"

# Document Intelligence Configuration (if needed)
export DOCUMENT_INTELLIGENCE_SERVICE="calgarypermitbot-docint"

# Deployment Settings
export VERBOSE_OUTPUT="false"
export WAIT_TIMEOUT_MINUTES="15"
export DATA_FOLDER="data"
export CONFIG_FILE="/tmp/deployment-config.env"

# Runtime Configuration for Apps
export PYTHON_VERSION="3.11"
export NODE_VERSION="18"

# Tags for resource management
export TAGS="Environment=Production Project=CalgarypermitBot Owner=AftabShaikh"

echo "✅ Configuration loaded successfully"
echo "📍 Location: $LOCATION"
echo "🏗️  Resource Group: $RESOURCE_GROUP"
echo "💰 App Service SKU: $APP_SERVICE_SKU"