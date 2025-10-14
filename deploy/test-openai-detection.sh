#!/bin/bash

# Test script to debug OpenAI service detection
# Load configuration
if [ -f "config.sh" ]; then
    source "config.sh"
else
    echo "❌ config.sh not found"
    exit 1
fi

echo "🔍 Testing OpenAI service detection"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

echo "1. Testing Azure CLI authentication..."
if az account show > /dev/null 2>&1; then
    echo "✅ Azure CLI is authenticated"
    SUBSCRIPTION=$(az account show --query name -o tsv)
    echo "   Subscription: $SUBSCRIPTION"
else
    echo "❌ Azure CLI not authenticated. Run 'az login' first."
    exit 1
fi

echo ""
echo "2. Listing all resources in resource group..."
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table

echo ""
echo "3. Listing cognitive services specifically..."
echo "Command: az cognitiveservices account list --resource-group $RESOURCE_GROUP"
az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, kind:kind, location:location, provisioningState:properties.provisioningState}" -o table

echo ""
echo "4. Testing OpenAI detection query..."
echo "Command: az cognitiveservices account list --resource-group $RESOURCE_GROUP --query \"[?kind=='OpenAI'][0].name\" -o tsv"
RESULT1=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'][0].name" -o tsv 2>/dev/null)
echo "Result 1: '$RESULT1'"

echo ""
echo "5. Testing alternative OpenAI detection query (case insensitive)..."
echo "Command: az cognitiveservices account list --resource-group $RESOURCE_GROUP --query \"[?contains(tolower(kind), 'openai')][0].name\" -o tsv"
RESULT2=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(tolower(kind), 'openai')][0].name" -o tsv 2>/dev/null)
echo "Result 2: '$RESULT2'"

echo ""
echo "6. Testing broad search for any cognitive services..."
echo "Command: az cognitiveservices account list --resource-group $RESOURCE_GROUP --query \"[0].name\" -o tsv"
RESULT3=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
echo "Result 3: '$RESULT3'"

if [ -n "$RESULT1" ]; then
    echo ""
    echo "✅ OpenAI service detected with main query: $RESULT1"
elif [ -n "$RESULT2" ]; then
    echo ""
    echo "✅ OpenAI service detected with alternative query: $RESULT2"
elif [ -n "$RESULT3" ]; then
    echo ""
    echo "⚠️  Found cognitive service but not detected as OpenAI: $RESULT3"
    echo "   This might be an OpenAI service with unexpected 'kind' value"
else
    echo ""
    echo "❌ No cognitive services found in resource group"
fi