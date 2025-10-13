#!/bin/bash

# Calgary Permit Bot - Deployment Status Checker
# This script checks the current status of resources being deployed

set -e

echo "📊 Calgary Permit Bot - Deployment Status Checker"
echo "================================================"
echo ""

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status with colors
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "SUCCESS") echo -e "✅ ${GREEN}$message${NC}" ;;
        "WARN")    echo -e "⚠️  ${YELLOW}$message${NC}" ;;
        "ERROR")   echo -e "❌ ${RED}$message${NC}" ;;
        "INFO")    echo -e "ℹ️  ${BLUE}$message${NC}" ;;
        *)         echo -e "$message" ;;
    esac
}

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    print_status "ERROR" "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Function to check resource status
check_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local status_query="$4"
    
    echo ""
    echo "🔍 Checking $resource_type: $resource_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if eval "$check_command" > /dev/null 2>&1; then
        if [ -n "$status_query" ]; then
            STATUS=$(eval "$status_query" 2>/dev/null || echo "Unknown")
        else
            STATUS="Exists"
        fi
        
        # Convert status to lowercase for case-insensitive comparison
        STATUS_LOWER=$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')
        
        case $STATUS_LOWER in
            "succeeded"|"running"|"available")
                print_status "SUCCESS" "$resource_type is ready (Status: $STATUS)"
                ;;
            "creating"|"provisioning"|"inprogress")
                print_status "WARN" "$resource_type is being created (Status: $STATUS)"
                echo "   ⏳ This is normal - creation in progress"
                ;;
            "failed"|"error")
                print_status "ERROR" "$resource_type creation failed (Status: $STATUS)"
                ;;
            *)
                print_status "INFO" "$resource_type exists (Status: $STATUS)"
                ;;
        esac
    else
        print_status "INFO" "$resource_type not found - not created yet"
    fi
}

echo "🔍 Current deployment status:"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo ""

# Check Resource Group
check_resource "Resource Group" "$RESOURCE_GROUP" \
    "az group show --name '$RESOURCE_GROUP'" \
    "az group show --name '$RESOURCE_GROUP' --query 'properties.provisioningState' -o tsv"

# Check Storage Account
STORAGE_PATTERN="calgarypermitbotstg*"
if [[ "$STORAGE_ACCOUNT" == *'$('* ]]; then
    # Storage account name contains timestamp logic, try to find actual name
    ACTUAL_STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbotstg')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_STORAGE" ]; then
        STORAGE_ACCOUNT="$ACTUAL_STORAGE"
    fi
fi

check_resource "Storage Account" "$STORAGE_ACCOUNT" \
    "az storage account show --name '$STORAGE_ACCOUNT' --resource-group '$RESOURCE_GROUP'" \
    "az storage account show --name '$STORAGE_ACCOUNT' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv"

# Check AI Search Service  
ACTUAL_SEARCH=""
if [[ "$SEARCH_SERVICE" == *'$('* ]]; then
    # Search service name contains timestamp logic, try to find actual name
    ACTUAL_SEARCH=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-search')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_SEARCH" ]; then
        SEARCH_SERVICE="$ACTUAL_SEARCH"
    fi
fi

check_resource "AI Search Service" "$SEARCH_SERVICE" \
    "az search service show --name '$SEARCH_SERVICE' --resource-group '$RESOURCE_GROUP'" \
    "az search service show --name '$SEARCH_SERVICE' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv"

# If search service not found with expected name, look for any search services
if [ -z "$ACTUAL_SEARCH" ]; then
    echo ""
    echo "🔍 Looking for any AI Search services in resource group..."
    SEARCH_SERVICES=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Status:provisioningState, Location:location}" -o table 2>/dev/null || echo "")
    if [ -n "$SEARCH_SERVICES" ] && [ "$SEARCH_SERVICES" != "" ]; then
        echo "$SEARCH_SERVICES"
    else
        print_status "INFO" "No AI Search services found in resource group"
    fi
fi

# Check OpenAI Service
ACTUAL_OPENAI=""
if [[ "$OPENAI_SERVICE" == *'$('* ]]; then
    ACTUAL_OPENAI=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-openai')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_OPENAI" ]; then
        OPENAI_SERVICE="$ACTUAL_OPENAI"
    fi
fi

check_resource "OpenAI Service" "$OPENAI_SERVICE" \
    "az cognitiveservices account show --name '$OPENAI_SERVICE' --resource-group '$RESOURCE_GROUP'" \
    "az cognitiveservices account show --name '$OPENAI_SERVICE' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv"

# Check Cosmos DB
ACTUAL_COSMOS=""
if [[ "$COSMOS_ACCOUNT" == *'$('* ]]; then
    ACTUAL_COSMOS=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-cosmos')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_COSMOS" ]; then
        COSMOS_ACCOUNT="$ACTUAL_COSMOS"
    fi
fi

check_resource "Cosmos DB" "$COSMOS_ACCOUNT" \
    "az cosmosdb show --name '$COSMOS_ACCOUNT' --resource-group '$RESOURCE_GROUP'" \
    "az cosmosdb show --name '$COSMOS_ACCOUNT' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv"

# Check App Service Plan
check_resource "App Service Plan" "$APP_SERVICE_PLAN" \
    "az appservice plan show --name '$APP_SERVICE_PLAN' --resource-group '$RESOURCE_GROUP'" \
    "az appservice plan show --name '$APP_SERVICE_PLAN' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv"

# Check Web Apps
check_resource "Backend Web App" "$BACKEND_APP_NAME" \
    "az webapp show --name '$BACKEND_APP_NAME' --resource-group '$RESOURCE_GROUP'" \
    "az webapp show --name '$BACKEND_APP_NAME' --resource-group '$RESOURCE_GROUP' --query 'state' -o tsv"

check_resource "Frontend Web App" "$FRONTEND_APP_NAME" \
    "az webapp show --name '$FRONTEND_APP_NAME' --resource-group '$RESOURCE_GROUP'" \
    "az webapp show --name '$FRONTEND_APP_NAME' --resource-group '$RESOURCE_GROUP' --query 'state' -o tsv"

echo ""
echo "📊 Summary"
echo "=========="

# Count resources in various states
TOTAL_RESOURCES=7  # RG, Storage, Search, OpenAI, Cosmos, ASP, Backend, Frontend
READY_COUNT=0
CREATING_COUNT=0
FAILED_COUNT=0
MISSING_COUNT=0

# This is a simple summary - in a more complex script, we'd track the actual states
print_status "INFO" "Use this output to check if deployment is progressing normally"
print_status "INFO" "Resources in 'Creating' or 'Provisioning' state are normal during deployment"
print_status "WARN" "If a resource shows 'Failed' status, the deployment needs attention"

echo ""
echo "💡 Tips:"
echo "   - AI Search service typically takes 3-5 minutes to provision"
echo "   - OpenAI service can take 2-3 minutes"  
echo "   - Cosmos DB can take 5-10 minutes"
echo "   - If deployment seems stuck for >10 minutes on one resource, check for errors"

echo ""
print_status "INFO" "To monitor deployment progress, run this script again in a few minutes"