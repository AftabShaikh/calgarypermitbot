#!/bin/bash

# Requirements Validation Script for Calgary Permit Bot
# This script validates that all required dependencies are present in requirements.txt

echo "🔍 Validating Calgary Permit Bot Requirements"
echo "============================================="

BACKEND_DIR="/workspaces/calgarypermitbot/app/backend"
REQUIREMENTS_FILE="$BACKEND_DIR/requirements.txt"

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "❌ requirements.txt not found at $REQUIREMENTS_FILE"
    exit 1
fi

echo "📋 Checking requirements.txt at: $REQUIREMENTS_FILE"
echo ""

# Critical packages that must be present
CRITICAL_PACKAGES=(
    "prompty"
    "rich" 
    "tenacity"
    "tiktoken"
    "quart"
    "uvicorn"
    "gunicorn"
    "azure-identity"
    "azure-storage-blob"
    "azure-search-documents"
    "azure-cosmos"
    "azure-cognitiveservices-speech"
    "openai"
    "aiohttp"
    "python-dotenv"
    "pyyaml"
    "cryptography"
    "beautifulsoup4"
    "quart-cors"
    "pillow"
    "flask"
    "msal"
    "msgraph-sdk"
    "python-docx"
    "azure-ai-documentintelligence"
    "azure-monitor-opentelemetry"
    "pymupdf"
    "pypdf"
    "types-beautifulsoup4"
    "types-pillow"
    "typing-extensions"
)

echo "🔍 Checking for critical packages..."
MISSING_PACKAGES=()

for package in "${CRITICAL_PACKAGES[@]}"; do
    if grep -q "^${package}" "$REQUIREMENTS_FILE"; then
        echo "✅ $package"
    else
        echo "❌ $package - MISSING"
        MISSING_PACKAGES+=("$package")
    fi
done

echo ""
echo "📊 Validation Summary:"
echo "======================"
echo "Total packages checked: ${#CRITICAL_PACKAGES[@]}"
echo "Missing packages: ${#MISSING_PACKAGES[@]}"

if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    echo ""
    echo "🎉 All critical packages are present in requirements.txt!"
    echo "✅ Requirements validation passed"
    exit 0
else
    echo ""
    echo "❌ Requirements validation failed!"
    echo "Missing packages:"
    for package in "${MISSING_PACKAGES[@]}"; do
        echo "   - $package"
    done
    echo ""
    echo "🔧 To fix this, add the missing packages to requirements.txt"
    echo "   You can run: ./deploy/fix-requirements.sh"
    exit 1
fi