#!/bin/bash

# Calgary Permit Bot - Real-time Deployment Monitor
# Run this in a separate terminal while deployment is running

echo "📊 Calgary Permit Bot - Real-time Deployment Monitor"
echo "===================================================="
echo "Press Ctrl+C to stop monitoring"
echo ""

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "❌ Configuration file not found"
    exit 1
fi

# Function to get resource status
get_status() {
    local resource_type="$1"
    local check_cmd="$2"
    local status_cmd="$3"
    
    if eval "$check_cmd" > /dev/null 2>&1; then
        if [ -n "$status_cmd" ]; then
            STATUS=$(eval "$status_cmd" 2>/dev/null || echo "Unknown")
        else
            STATUS="Exists"
        fi
        
        # Convert to lowercase for case-insensitive comparison  
        STATUS_LOWER=$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')
        
        case $STATUS_LOWER in
            "succeeded"|"running"|"available") echo "🟢 $STATUS" ;;
            "creating"|"provisioning"|"inprogress") echo "🟡 $STATUS" ;;
            "failed"|"error") echo "🔴 $STATUS" ;;
            *) echo "🔵 $STATUS" ;;
        esac
    else
        echo "⚫ Not Found"
    fi
}

# Monitor loop
while true; do
    clear
    echo "📊 Calgary Permit Bot - Live Status Monitor"
    echo "==========================================="
    echo "$(date)"
    echo ""
    
    # Resource Group
    RG_STATUS=$(get_status "Resource Group" \
        "az group show --name '$RESOURCE_GROUP'" \
        "az group show --name '$RESOURCE_GROUP' --query 'properties.provisioningState' -o tsv")
    printf "%-20s %s\n" "Resource Group:" "$RG_STATUS"
    
    # Find actual storage account name
    ACTUAL_STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbotstg')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_STORAGE" ]; then
        STORAGE_STATUS=$(get_status "Storage Account" \
            "az storage account show --name '$ACTUAL_STORAGE' --resource-group '$RESOURCE_GROUP'" \
            "az storage account show --name '$ACTUAL_STORAGE' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv")
        printf "%-20s %s\n" "Storage Account:" "$STORAGE_STATUS"
    else
        printf "%-20s %s\n" "Storage Account:" "⚫ Not Found"
    fi
    
    # Find actual search service name
    ACTUAL_SEARCH=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-search')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_SEARCH" ]; then
        SEARCH_STATUS=$(get_status "AI Search Service" \
            "az search service show --name '$ACTUAL_SEARCH' --resource-group '$RESOURCE_GROUP'" \
            "az search service show --name '$ACTUAL_SEARCH' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv")
        printf "%-20s %s\n" "AI Search Service:" "$SEARCH_STATUS"
    else
        printf "%-20s %s\n" "AI Search Service:" "⚫ Not Found"
    fi
    
    # Find actual OpenAI service name
    ACTUAL_OPENAI=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-openai')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_OPENAI" ]; then
        OPENAI_STATUS=$(get_status "OpenAI Service" \
            "az cognitiveservices account show --name '$ACTUAL_OPENAI' --resource-group '$RESOURCE_GROUP'" \
            "az cognitiveservices account show --name '$ACTUAL_OPENAI' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv")
        printf "%-20s %s\n" "OpenAI Service:" "$OPENAI_STATUS"
    else
        printf "%-20s %s\n" "OpenAI Service:" "⚫ Not Found"
    fi
    
    # Find actual Cosmos DB name
    ACTUAL_COSMOS=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-cosmos')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$ACTUAL_COSMOS" ]; then
        COSMOS_STATUS=$(get_status "Cosmos DB" \
            "az cosmosdb show --name '$ACTUAL_COSMOS' --resource-group '$RESOURCE_GROUP'" \
            "az cosmosdb show --name '$ACTUAL_COSMOS' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv")
        printf "%-20s %s\n" "Cosmos DB:" "$COSMOS_STATUS"
    else
        printf "%-20s %s\n" "Cosmos DB:" "⚫ Not Found"
    fi
    
    # App Service Plan
    ASP_STATUS=$(get_status "App Service Plan" \
        "az appservice plan show --name '$APP_SERVICE_PLAN' --resource-group '$RESOURCE_GROUP'" \
        "az appservice plan show --name '$APP_SERVICE_PLAN' --resource-group '$RESOURCE_GROUP' --query 'provisioningState' -o tsv")
    printf "%-20s %s\n" "App Service Plan:" "$ASP_STATUS"
    
    # Backend Web App
    BACKEND_STATUS=$(get_status "Backend Web App" \
        "az webapp show --name '$BACKEND_APP_NAME' --resource-group '$RESOURCE_GROUP'" \
        "az webapp show --name '$BACKEND_APP_NAME' --resource-group '$RESOURCE_GROUP' --query 'state' -o tsv")
    printf "%-20s %s\n" "Backend Web App:" "$BACKEND_STATUS"
    
    # Frontend Web App
    FRONTEND_STATUS=$(get_status "Frontend Web App" \
        "az webapp show --name '$FRONTEND_APP_NAME' --resource-group '$RESOURCE_GROUP'" \
        "az webapp show --name '$FRONTEND_APP_NAME' --resource-group '$RESOURCE_GROUP' --query 'state' -o tsv")
    printf "%-20s %s\n" "Frontend Web App:" "$FRONTEND_STATUS"
    
    echo ""
    echo "Legend:"
    echo "🟢 Ready/Success  🟡 Creating/In Progress  🔴 Failed  🔵 Other Status  ⚫ Not Found"
    echo ""
    echo "Monitoring... (refreshes every 30 seconds)"
    echo "Press Ctrl+C to stop"
    
    sleep 30
done