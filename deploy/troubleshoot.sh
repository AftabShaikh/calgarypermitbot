#!/bin/bash

# Calgary Permit Bot - Troubleshooting Script
# This script helps diagnose deployment issues

echo "🔍 Calgary Permit Bot - Deployment Troubleshooting"
echo "================================================="
echo ""

# Configuration (should match preparation script)
RESOURCE_GROUP="rg-calgarypermitbot"
LOCATION="westus2"
APP_SERVICE_PLAN="asp-calgarypermitbot"

echo "📋 Checking Azure CLI login status..."
if az account show > /dev/null 2>&1; then
    SUBSCRIPTION=$(az account show --query name -o tsv)
    ACCOUNT=$(az account show --query user.name -o tsv)
    echo "✅ Logged in as: $ACCOUNT"
    echo "   Subscription: $SUBSCRIPTION"
else
    echo "❌ Not logged into Azure CLI"
    echo "Please run: az login"
    exit 1
fi

echo ""
echo "📋 Checking resource group..."
if az group show --name $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "✅ Resource group '$RESOURCE_GROUP' exists"
    LOCATION_ACTUAL=$(az group show --name $RESOURCE_GROUP --query location -o tsv)
    echo "   Location: $LOCATION_ACTUAL"
else
    echo "❌ Resource group '$RESOURCE_GROUP' does not exist"
fi

echo ""
echo "📋 Checking App Service Plans in resource group..."
PLANS=$(az appservice plan list --resource-group $RESOURCE_GROUP --query "[].{Name:name,SKU:sku.name,Location:location}" -o table 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$PLANS" ]; then
    echo "$PLANS"
else
    echo "❌ No App Service Plans found or resource group doesn't exist"
fi

echo ""
echo "📋 Checking Web Apps in resource group..."
WEBAPPS=$(az webapp list --resource-group $RESOURCE_GROUP --query "[].{Name:name,State:state,Location:location}" -o table 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$WEBAPPS" ]; then
    echo "$WEBAPPS"
else
    echo "❌ No Web Apps found or resource group doesn't exist"
fi

echo ""
echo "📋 Checking Storage Accounts in resource group..."
STORAGE=$(az storage account list --resource-group $RESOURCE_GROUP --query "[].{Name:name,Location:location,SKU:sku.name}" -o table 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$STORAGE" ]; then
    echo "$STORAGE"
else
    echo "❌ No Storage Accounts found or resource group doesn't exist"
fi

echo ""
echo "📋 Checking quota and limits..."
echo "App Service Plan quota in $LOCATION:"
az vm list-usage --location $LOCATION --query "[?contains(name.value, 'cores')].{Name:name.localizedValue,Current:currentValue,Limit:limit}" -o table 2>/dev/null || echo "Unable to check quota"

echo ""
echo "📋 Checking available App Service SKUs in $LOCATION..."
az appservice list-locations --sku S1 --linux-workers-enabled --query "[?contains(name, '$LOCATION')].name" -o table 2>/dev/null || echo "Unable to check available SKUs"

echo ""
echo "🔧 Suggested Actions:"
echo "===================="

if ! az group show --name $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "1. Create resource group first:"
    echo "   az group create --name $RESOURCE_GROUP --location $LOCATION"
fi

if ! az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP > /dev/null 2>&1; then
    echo "2. Try creating App Service Plan manually:"
    echo "   az appservice plan create \\"
    echo "     --name $APP_SERVICE_PLAN \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --location $LOCATION \\"
    echo "     --sku S1 \\"
    echo "     --is-linux"
    echo ""
    echo "3. If S1 fails, try B1 (Basic):"
    echo "   az appservice plan create \\"
    echo "     --name $APP_SERVICE_PLAN \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --location $LOCATION \\"
    echo "     --sku B1 \\"
    echo "     --is-linux"
    echo ""
    echo "4. If Linux fails, try Windows:"
    echo "   az appservice plan create \\"
    echo "     --name $APP_SERVICE_PLAN \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --location $LOCATION \\"
    echo "     --sku S1"
fi

echo ""
echo "5. Check Azure status page: https://status.azure.com"
echo "6. Try a different region if $LOCATION has issues"
echo "7. Check subscription limits in Azure Portal"

echo ""
echo "📞 Need Help?"
echo "============"
echo "If the issue persists:"
echo "- Check Azure Portal for detailed error messages"
echo "- Try deploying to a different region (eastus, eastus2)"
echo "- Verify your subscription has sufficient quota"
echo "- Contact Azure support if needed"