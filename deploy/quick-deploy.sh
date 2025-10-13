#!/bin/bash

# Calgary Permit Bot - Quick Deploy Script
# This script performs a complete deployment in one step
# Designed to work in Azure Cloud Shell and local environments

set -e  # Exit on any error

echo "🚀 Calgary Permit Bot - Quick Deploy"
echo "===================================="
echo ""

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
SKIP_PREPARE=false
SKIP_DATA_UPLOAD=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-prepare)
            SKIP_PREPARE=true
            shift
            ;;
        --skip-data-upload)
            SKIP_DATA_UPLOAD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-prepare      Skip resource preparation step"
            echo "  --skip-data-upload  Skip uploading data files"
            echo "  -v, --verbose       Enable verbose output"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Full deployment"
            echo "  $0 --skip-prepare            # Deploy apps only"  
            echo "  $0 --skip-data-upload        # Deploy without uploading data"
            echo "  $0 --verbose                 # Show detailed output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    echo "📋 Configuration loaded from config.sh"
else
    echo "❌ Configuration file not found at $SCRIPT_DIR/config.sh"
    exit 1
fi

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install Azure CLI first."
    exit 1
fi

# Check if logged into Azure
if ! az account show > /dev/null 2>&1; then
    echo "❌ Not logged into Azure. Please run 'az login' first."
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Show deployment plan
echo "📋 Deployment Plan"
echo "=================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "App Service SKU: $APP_SERVICE_SKU"
echo "Backend App: $BACKEND_APP_NAME"
echo "Frontend App: $FRONTEND_APP_NAME"
echo "Storage Account: $STORAGE_ACCOUNT"
echo ""

if [ "$SKIP_PREPARE" = true ]; then
    echo "⏭️  Skipping resource preparation"
else
    echo "🏗️  Will prepare Azure resources"
fi

if [ "$SKIP_DATA_UPLOAD" = true ]; then
    echo "⏭️  Skipping data upload"
else
    echo "📁 Will upload data files"
fi

echo ""
read -p "Continue with deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""

# Step 1: Prepare resources (unless skipped)
if [ "$SKIP_PREPARE" = false ]; then
    echo "🏗️  Step 1: Preparing Azure Resources"
    echo "====================================="
    
    chmod +x "$SCRIPT_DIR/01-prepare-resources.sh"
    
    if [ "$VERBOSE" = true ]; then
        "$SCRIPT_DIR/01-prepare-resources.sh" --verbose
    else
        "$SCRIPT_DIR/01-prepare-resources.sh"
    fi
    
    echo ""
    echo "✅ Resource preparation completed!"
    echo ""
else
    echo "⏭️  Skipping resource preparation"
    
    # Create minimal configuration for deploy-only
    echo "📋 Creating deployment configuration..."
    
    # Try to auto-detect existing resources
    EXISTING_STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot')].name | [0]" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_STORAGE" ]; then
        STORAGE_ACCOUNT="$EXISTING_STORAGE"
        echo "✅ Auto-detected storage account: $STORAGE_ACCOUNT"
    else
        echo "❌ Could not auto-detect storage account. Resources may not exist."
        echo "💡 Run without --skip-prepare to create resources first."
        exit 1
    fi
    
    # Create minimal config file
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
EOF
    
    echo "✅ Configuration created"
    echo ""
fi

# Step 2: Deploy applications
echo "🚀 Step 2: Deploying Applications"
echo "================================="

# Set environment variable for data upload skip
if [ "$SKIP_DATA_UPLOAD" = true ]; then
    export SKIP_DATA_UPLOAD=true
fi

chmod +x "$SCRIPT_DIR/02-deploy-app.sh"

# Modify the deployment script to respect SKIP_DATA_UPLOAD
if [ "$SKIP_DATA_UPLOAD" = true ]; then
    echo "⏭️  Data upload will be skipped"
fi

"$SCRIPT_DIR/02-deploy-app.sh"

echo ""
echo "✅ Application deployment completed!"
echo ""

# Step 3: Final summary
echo "🎉 Deployment Complete!"
echo "======================"

if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    
    BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
    FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"
    
    echo "🌐 Application URLs:"
    echo "   Frontend: $FRONTEND_URL"
    echo "   Backend:  $BACKEND_URL"
    echo "   Health:   $BACKEND_URL/health"
    echo ""
    echo "📋 Azure Resources:"
    echo "   Resource Group: $RESOURCE_GROUP"
    echo "   Location: $LOCATION"
    echo "   Storage Account: $STORAGE_ACCOUNT"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Wait 2-3 minutes for services to fully start"
    echo "   2. Visit the frontend URL to test the application"
    echo "   3. Monitor logs if needed:"
    echo "      az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP"
    echo "      az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP"
    echo ""
else
    echo "⚠️  Configuration file not found, but deployment should be complete."
fi

echo "🎊 Enjoy your Calgary Permit Bot!"