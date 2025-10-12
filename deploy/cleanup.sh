#!/bin/bash

# Calgary Permit Bot - Cleanup Script
# This script removes all resources created for the Calgary Permit Bot

set -e

# Configuration (should match the preparation script)
RESOURCE_GROUP="rg-calgarypermitbot"

echo "🗑️  Calgary Permit Bot - Resource Cleanup"
echo "========================================="
echo ""
echo "⚠️  WARNING: This will delete ALL resources in the resource group:"
echo "   Resource Group: $RESOURCE_GROUP"
echo ""
echo "This includes:"
echo "- Web Apps (Frontend & Backend)"
echo "- Storage Account and all data"
echo "- Azure AI Search Service"
echo "- Azure OpenAI Service"
echo "- Cosmos DB Account"
echo "- App Service Plan"
echo ""

read -p "Are you sure you want to delete all resources? Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

echo ""
echo "🗑️  Deleting resource group and all resources..."

az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

echo "✅ Cleanup initiated!"
echo "===================="
echo ""
echo "📝 Note: Resource deletion is running in the background."
echo "   It may take 5-10 minutes to complete."
echo ""
echo "   To check status:"
echo "   az group show --name $RESOURCE_GROUP"
echo ""
echo "   When deleted, you'll see: ResourceGroupNotFound"