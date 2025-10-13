#!/bin/bash

# Emergency patch for case-sensitive status checking issue
# Run this if your deployment is stuck on "succeeded" status

echo "🔧 Emergency Patch - Fixing Case-Sensitive Status Issue"
echo "======================================================"

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "❌ Configuration file not found"
    exit 1
fi

echo "🔍 Checking current AI Search service status..."

# Find the actual search service
ACTUAL_SEARCH=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'calgarypermitbot-search')].name | [0]" -o tsv 2>/dev/null || echo "")

if [ -n "$ACTUAL_SEARCH" ]; then
    echo "Found search service: $ACTUAL_SEARCH"
    
    STATUS=$(az search service show --name "$ACTUAL_SEARCH" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
    echo "Current status: '$STATUS'"
    
    # Convert to lowercase for comparison
    STATUS_LOWER=$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')
    
    if [ "$STATUS_LOWER" = "succeeded" ] || [ "$STATUS_LOWER" = "running" ]; then
        echo "✅ AI Search Service is actually ready!"
        echo ""
        echo "🚀 Your deployment can continue. The service is working."
        echo ""
        echo "💡 To continue deployment:"
        echo "   1. Stop the current deployment (Ctrl+C)"
        echo "   2. Run: ./deploy/02-deploy-app.sh"
        echo ""
        echo "Or run a fresh deployment:"
        echo "   ./deploy/quick-deploy.sh --skip-prepare"
        
        # Update the config with the actual service name
        export SEARCH_SERVICE="$ACTUAL_SEARCH"
        
        # Save to deployment config
        if [ -f /tmp/deployment-config.env ]; then
            sed -i "s/SEARCH_SERVICE=.*/SEARCH_SERVICE=$ACTUAL_SEARCH/" /tmp/deployment-config.env
            echo "Updated deployment config with actual service name"
        fi
        
        exit 0
    else
        echo "⚠️  Service status: $STATUS"
        echo "The service may still be provisioning or there's an issue."
        exit 1
    fi
else
    echo "❌ No AI Search service found in resource group $RESOURCE_GROUP"
    exit 1
fi