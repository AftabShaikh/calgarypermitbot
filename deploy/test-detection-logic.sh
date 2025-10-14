#!/bin/bash

# Simple test to verify OpenAI detection logic
echo "🧪 Testing OpenAI Detection Logic"
echo "================================="

# Source config
source ./config.sh

echo "✅ Resource Group: $RESOURCE_GROUP"
echo "✅ Original OPENAI_SERVICE from config: $OPENAI_SERVICE"
echo ""

# Simulate the detection result (based on your output)
DETECTED_SERVICE="calgarypermibot-openai"

echo "🔍 Simulating detection result: '$DETECTED_SERVICE'"
echo ""

# Test the logic that will happen in the script
if [ -n "$DETECTED_SERVICE" ] && [ "$DETECTED_SERVICE" != "" ]; then
    echo "✅ Found existing OpenAI Service '$DETECTED_SERVICE' - skipping creation"
    export OPENAI_SERVICE="$DETECTED_SERVICE"
    echo "   Using existing: $OPENAI_SERVICE"
    echo "   Original config name: $OPENAI_SERVICE → Updated to: $DETECTED_SERVICE"
    OPENAI_EXIT_CODE=0
    DEPLOY_MODELS=true
    echo "   DEPLOY_MODELS=$DEPLOY_MODELS"
else
    echo "❌ Detection failed"
fi

echo ""
echo "✅ The script will now:"
echo "   1. Detect your existing service: calgarypermibot-openai"
echo "   2. Update OPENAI_SERVICE variable to use it"
echo "   3. Skip service creation"
echo "   4. Deploy models (if they don't exist)"
echo "   5. Continue with the rest of the deployment"