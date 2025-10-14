#!/bin/bash

# Test script to verify the OpenAI detection fix
echo "🧪 Testing OpenAI Detection Fix"
echo "==============================="

# Source the config to get RESOURCE_GROUP
if [ -f ./config.sh ]; then
    source ./config.sh
    echo "✅ Config loaded - Resource Group: $RESOURCE_GROUP"
    echo "✅ Original OPENAI_SERVICE from config: $OPENAI_SERVICE"
else
    echo "❌ config.sh not found"
    exit 1
fi

# Source the find_existing_resource function from the main script
source <(grep -A 50 "find_existing_resource()" 01-prepare-resources.sh | head -60)

echo ""
echo "🔍 Testing find_existing_resource function..."
DETECTED_OPENAI=$(find_existing_resource "openai")

if [ -n "$DETECTED_OPENAI" ]; then
    echo "✅ Detection successful: '$DETECTED_OPENAI'"
    echo ""
    echo "🔄 Variable update simulation:"
    echo "   Before: OPENAI_SERVICE='$OPENAI_SERVICE'"
    echo "   After:  OPENAI_SERVICE='$DETECTED_OPENAI'"
    echo ""
    echo "✅ The script should now detect and use your existing OpenAI service!"
else
    echo "❌ Detection failed - no OpenAI service found"
    echo ""
    echo "🔍 Manual check:"
    echo "All cognitive services:"
    az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, kind:kind}" -o table
fi

echo ""
echo "🧠 Next step: Run the main deployment script"
echo "   cd /workspaces/calgarypermitbot/deploy"
echo "   ./01-prepare-resources.sh"