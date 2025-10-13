#!/bin/bash

# Calgary Permit Bot - Resource Cleanup and Conflict Resolution Script
# This script helps resolve naming conflicts and cleanup stuck resources

set -e

echo "🧹 Calgary Permit Bot - Resource Cleanup & Conflict Resolution"
echo "============================================================="
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

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "INFO")  echo -e "ℹ️  ${BLUE}$message${NC}" ;;
        "WARN")  echo -e "⚠️  ${YELLOW}$message${NC}" ;;
        "ERROR") echo -e "❌ ${RED}$message${NC}" ;;
        "SUCCESS") echo -e "✅ ${GREEN}$message${NC}" ;;
        *) echo -e "$message" ;;
    esac
}

# Parse command line arguments
FORCE_DELETE=false
DRY_RUN=false
RESOLVE_CONFLICTS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --resolve-conflicts)
            RESOLVE_CONFLICTS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force             Force delete all resources (dangerous!)"
            echo "  --dry-run           Show what would be deleted without actually deleting"
            echo "  --resolve-conflicts Only resolve naming conflicts, don't delete resources"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run               # Show resources that exist"
            echo "  $0 --resolve-conflicts     # Check and resolve naming conflicts"
            echo "  $0 --force                 # Delete all resources (BE CAREFUL!)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_status "INFO" "Resource Group: $RESOURCE_GROUP"
print_status "INFO" "Location: $LOCATION"
echo ""

# Check if Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    print_status "ERROR" "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Function to check resource status
check_resource_status() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    
    echo "🔍 Checking $resource_type: $resource_name"
    
    if eval "$check_command" > /dev/null 2>&1; then
        STATUS=$(eval "$check_command" 2>/dev/null | jq -r '.provisioningState // .status // "Unknown"' 2>/dev/null || echo "Exists")
        print_status "WARN" "$resource_type '$resource_name' exists (Status: $STATUS)"
        return 0
    else
        print_status "SUCCESS" "$resource_type '$resource_name' does not exist"
        return 1
    fi
}

# Function to delete resource with confirmation
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    if [ "$DRY_RUN" = true ]; then
        print_status "INFO" "[DRY RUN] Would delete $resource_type: $resource_name"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = true ]; then
        print_status "WARN" "Force deleting $resource_type: $resource_name"
        if eval "$delete_command" > /dev/null 2>&1; then
            print_status "SUCCESS" "$resource_type deleted successfully"
        else
            print_status "ERROR" "Failed to delete $resource_type"
        fi
    else
        echo ""
        read -p "Delete $resource_type '$resource_name'? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "INFO" "Deleting $resource_type: $resource_name"
            if eval "$delete_command" > /dev/null 2>&1; then
                print_status "SUCCESS" "$resource_type deleted successfully"
            else
                print_status "ERROR" "Failed to delete $resource_type"
            fi
        else
            print_status "INFO" "Skipping deletion of $resource_type"
        fi
    fi
}

echo "🔍 Scanning for existing resources..."
echo "====================================="

# Check Resource Group
if check_resource_status "Resource Group" "$RESOURCE_GROUP" "az group show --name '$RESOURCE_GROUP'"; then
    RESOURCE_GROUP_EXISTS=true
    
    # If only resolving conflicts, don't offer to delete the resource group
    if [ "$RESOLVE_CONFLICTS" = false ]; then
        delete_resource "Resource Group" "$RESOURCE_GROUP" "az group delete --name '$RESOURCE_GROUP' --yes"
        
        if [ "$?" -eq 0 ] && [ "$DRY_RUN" = false ]; then
            print_status "SUCCESS" "Resource group deleted. All resources should be cleaned up."
            exit 0
        fi
    fi
else
    RESOURCE_GROUP_EXISTS=false
fi

if [ "$RESOURCE_GROUP_EXISTS" = true ]; then
    echo ""
    echo "🔍 Checking individual resources in resource group..."
    echo "===================================================="
    
    # Check Storage Account
    STORAGE_PATTERN="calgarypermitbotstg*"
    EXISTING_STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_STORAGE" ]; then
        check_resource_status "Storage Account" "$EXISTING_STORAGE" "az storage account show --name '$EXISTING_STORAGE' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "Storage Account" "$EXISTING_STORAGE" "az storage account delete --name '$EXISTING_STORAGE' --resource-group '$RESOURCE_GROUP' --yes"
        fi
    fi
    
    # Check Search Service
    SEARCH_PATTERN="calgarypermitbot-search*"
    EXISTING_SEARCH=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-search')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_SEARCH" ]; then
        check_resource_status "AI Search Service" "$EXISTING_SEARCH" "az search service show --name '$EXISTING_SEARCH' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "AI Search Service" "$EXISTING_SEARCH" "az search service delete --name '$EXISTING_SEARCH' --resource-group '$RESOURCE_GROUP' --yes"
        fi
    fi
    
    # Check OpenAI Service
    OPENAI_PATTERN="calgarypermitbot-openai*"
    EXISTING_OPENAI=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-openai')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_OPENAI" ]; then
        check_resource_status "OpenAI Service" "$EXISTING_OPENAI" "az cognitiveservices account show --name '$EXISTING_OPENAI' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "OpenAI Service" "$EXISTING_OPENAI" "az cognitiveservices account delete --name '$EXISTING_OPENAI' --resource-group '$RESOURCE_GROUP' --yes"
        fi
    fi
    
    # Check Cosmos DB
    COSMOS_PATTERN="calgarypermitbot-cosmos*"
    EXISTING_COSMOS=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-cosmos')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_COSMOS" ]; then
        check_resource_status "Cosmos DB" "$EXISTING_COSMOS" "az cosmosdb show --name '$EXISTING_COSMOS' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "Cosmos DB" "$EXISTING_COSMOS" "az cosmosdb delete --name '$EXISTING_COSMOS' --resource-group '$RESOURCE_GROUP' --yes"
        fi
    fi
    
    # Check App Service Plan
    EXISTING_ASP=$(az appservice plan list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_ASP" ]; then
        check_resource_status "App Service Plan" "$EXISTING_ASP" "az appservice plan show --name '$EXISTING_ASP' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "App Service Plan" "$EXISTING_ASP" "az appservice plan delete --name '$EXISTING_ASP' --resource-group '$RESOURCE_GROUP' --yes"
        fi
    fi
    
    # Check Web Apps
    EXISTING_BACKEND=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-backend')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_BACKEND" ]; then
        check_resource_status "Backend Web App" "$EXISTING_BACKEND" "az webapp show --name '$EXISTING_BACKEND' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "Backend Web App" "$EXISTING_BACKEND" "az webapp delete --name '$EXISTING_BACKEND' --resource-group '$RESOURCE_GROUP'"
        fi
    fi
    
    EXISTING_FRONTEND=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-frontend')].name | [0]" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_FRONTEND" ]; then
        check_resource_status "Frontend Web App" "$EXISTING_FRONTEND" "az webapp show --name '$EXISTING_FRONTEND' --resource-group '$RESOURCE_GROUP'"
        if [ "$RESOLVE_CONFLICTS" = false ]; then
            delete_resource "Frontend Web App" "$EXISTING_FRONTEND" "az webapp delete --name '$EXISTING_FRONTEND' --resource-group '$RESOURCE_GROUP'"
        fi
    fi
fi

echo ""
echo "📋 Cleanup Summary"
echo "=================="

if [ "$RESOLVE_CONFLICTS" = true ]; then
    print_status "INFO" "Conflict resolution complete."
    echo ""
    print_status "INFO" "💡 To avoid naming conflicts in the future:"
    echo "   - The deployment scripts now use timestamp-based naming"
    echo "   - Wait for resources to fully delete before redeploying"
    echo "   - Use different resource names if conflicts persist"
else
    if [ "$DRY_RUN" = true ]; then
        print_status "INFO" "Dry run complete - no resources were deleted."
        echo ""
        print_status "INFO" "💡 To actually delete resources:"
        echo "   - Remove --dry-run flag"
        echo "   - Use --force to skip confirmations"
    else
        print_status "SUCCESS" "Cleanup process complete."
    fi
fi

echo ""
print_status "INFO" "🚀 Ready to redeploy with: ./deploy/quick-deploy.sh"