#!/bin/bash

# Test script to verify OpenAI detection fixes
# This script tests the enhanced OpenAI detection logic

echo "🧪 Testing OpenAI Detection Fixes"
echo "================================"

# Source the config
if [ -f ./config.sh ]; then
    source ./config.sh
    echo "✅ Loaded config.sh"
else
    echo "❌ config.sh not found"
    exit 1
fi

echo "🔍 Resource Group: $RESOURCE_GROUP"
echo "🔍 Expected OpenAI Service: $OPENAI_SERVICE"
echo ""

# Test Azure CLI authentication
echo "🔐 Testing Azure CLI authentication..."
if az account show >/dev/null 2>&1; then
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo "✅ Azure CLI authenticated (Subscription: $SUBSCRIPTION_ID)"
else
    echo "❌ Azure CLI not authenticated. Run 'az login' first."
    exit 1
fi

echo ""
echo "📋 Listing all cognitive services in resource group..."
COGNITIVE_SERVICES=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, kind:kind, location:location, provisioningState:properties.provisioningState}" -o table 2>/dev/null)
if [ -n "$COGNITIVE_SERVICES" ]; then
    echo "$COGNITIVE_SERVICES"
else
    echo "❌ No cognitive services found or query failed"
fi

echo ""
echo "🔍 Testing OpenAI detection methods..."

# Method 1: Exact kind match
echo "1️⃣ Testing exact kind='OpenAI' match..."
RESULT1=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?kind=='OpenAI'].name" -o tsv 2>/dev/null)
if [ -n "$RESULT1" ]; then
    echo "   ✅ Found: $RESULT1"
else
    echo "   ❌ No match"
fi

# Method 2: Case-insensitive kind match
echo "2️⃣ Testing case-insensitive kind match..."
RESULT2=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?tolower(kind)=='openai'].name" -o tsv 2>/dev/null)
if [ -n "$RESULT2" ]; then
    echo "   ✅ Found: $RESULT2"
else
    echo "   ❌ No match"
fi

# Method 3: Contains 'openai' in kind
echo "3️⃣ Testing contains 'openai' in kind..."
RESULT3=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(tolower(kind), 'openai')].name" -o tsv 2>/dev/null)
if [ -n "$RESULT3" ]; then
    echo "   ✅ Found: $RESULT3"
else
    echo "   ❌ No match"
fi

# Method 4: Name-based detection
echo "4️⃣ Testing name contains 'openai'..."
RESULT4=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(tolower(name), 'openai')].name" -o tsv 2>/dev/null)
if [ -n "$RESULT4" ]; then
    echo "   ✅ Found: $RESULT4"
else
    echo "   ❌ No match"
fi

# Method 5: SKU-based detection
echo "5️⃣ Testing SKU contains 'openai' or 'gpt'..."
RESULT5=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?contains(tolower(sku.name), 'openai') || contains(tolower(sku.name), 'gpt')].name" -o tsv 2>/dev/null)
if [ -n "$RESULT5" ]; then
    echo "   ✅ Found: $RESULT5"
else
    echo "   ❌ No match"
fi

echo ""
echo "📊 Detection Summary:"
echo "===================="

# Collect all unique results
ALL_RESULTS="$RESULT1 $RESULT2 $RESULT3 $RESULT4 $RESULT5"
UNIQUE_RESULTS=$(echo "$ALL_RESULTS" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

if [ -n "$UNIQUE_RESULTS" ]; then
    echo "✅ OpenAI services detected: $UNIQUE_RESULTS"
    echo ""
    echo "🔍 Service details:"
    for service in $UNIQUE_RESULTS; do
        echo "   Service: $service"
        az cognitiveservices account show --resource-group "$RESOURCE_GROUP" --name "$service" --query "{kind:kind, sku:sku.name, endpoint:properties.endpoint, state:properties.provisioningState}" -o table 2>/dev/null || echo "   ❌ Could not get details"
    done
else
    echo "❌ No OpenAI services detected by any method"
    echo ""
    echo "🔍 Raw cognitive services data:"
    az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, kind:kind, sku:sku.name}" -o json 2>/dev/null || echo "Query failed"
fi

echo ""
echo "✅ Test complete!"