#!/bin/bash

# Calgary Permit Bot - Pre-deployment Validation Script
# This script validates that all prerequisites are met for deployment

set -e

echo "🔍 Calgary Permit Bot - Pre-deployment Validation"
echo "================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_PASSED=true

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" = "PASS" ]; then
        echo -e "✅ ${GREEN}$message${NC}"
    elif [ "$status" = "FAIL" ]; then
        echo -e "❌ ${RED}$message${NC}"
        VALIDATION_PASSED=false
    elif [ "$status" = "WARN" ]; then
        echo -e "⚠️  ${YELLOW}$message${NC}"
    else
        echo -e "ℹ️  $message"
    fi
}

echo "📋 Checking Prerequisites..."
echo "============================"

# Check if Azure CLI is installed
if command -v az &> /dev/null; then
    AZ_VERSION=$(az --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    print_status "PASS" "Azure CLI installed (version $AZ_VERSION)"
else
    print_status "FAIL" "Azure CLI not found. Please install Azure CLI."
fi

# Check if logged into Azure
if az account show > /dev/null 2>&1; then
    ACCOUNT_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_status "PASS" "Logged into Azure account: $ACCOUNT_NAME"
    echo "   Subscription: $SUBSCRIPTION_ID"
else
    print_status "FAIL" "Not logged into Azure. Please run 'az login' first."
fi

# Check if Node.js is available (for frontend builds)
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    print_status "PASS" "Node.js available ($NODE_VERSION)"
else
    print_status "WARN" "Node.js not found. Frontend builds may fail locally."
fi

# Check if npm is available
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm --version)
    print_status "PASS" "npm available (version $NPM_VERSION)"
else
    print_status "WARN" "npm not found. Frontend builds may fail locally."
fi

# Check if Python is available
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    print_status "PASS" "Python3 available ($PYTHON_VERSION)"
else
    print_status "WARN" "Python3 not found. Backend development may be affected."
fi

# Check if curl is available (for health checks)
if command -v curl &> /dev/null; then
    print_status "PASS" "curl available for health checks"
else
    print_status "WARN" "curl not found. Health checks may fail."
fi

echo ""
echo "📁 Checking Project Structure..."
echo "==============================="

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check essential files and directories
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    print_status "PASS" "Configuration file found: deploy/config.sh"
else
    print_status "FAIL" "Configuration file missing: deploy/config.sh"
fi

if [ -f "$SCRIPT_DIR/01-prepare-resources.sh" ]; then
    print_status "PASS" "Resource preparation script found"
else
    print_status "FAIL" "Resource preparation script missing"
fi

if [ -f "$SCRIPT_DIR/02-deploy-app.sh" ]; then
    print_status "PASS" "Application deployment script found"
else
    print_status "FAIL" "Application deployment script missing"
fi

if [ -f "$SCRIPT_DIR/quick-deploy.sh" ]; then
    print_status "PASS" "Quick deployment script found"
else
    print_status "FAIL" "Quick deployment script missing"
fi

if [ -d "$PROJECT_ROOT/app/backend" ]; then
    print_status "PASS" "Backend application directory found"
else
    print_status "FAIL" "Backend application directory missing: app/backend"
fi

if [ -d "$PROJECT_ROOT/app/frontend" ]; then
    print_status "PASS" "Frontend application directory found"
else
    print_status "FAIL" "Frontend application directory missing: app/frontend"
fi

if [ -d "$PROJECT_ROOT/data" ]; then
    DATA_FILE_COUNT=$(find "$PROJECT_ROOT/data" -type f | wc -l)
    print_status "PASS" "Data directory found with $DATA_FILE_COUNT files"
else
    print_status "WARN" "Data directory missing: data/"
    print_status "INFO" "Create a 'data' directory and add your documents for upload"
fi

# Check frontend package.json
if [ -f "$PROJECT_ROOT/app/frontend/package.json" ]; then
    print_status "PASS" "Frontend package.json found"
else
    print_status "FAIL" "Frontend package.json missing"
fi

# Check backend requirements
if [ -f "$PROJECT_ROOT/app/backend/requirements.txt" ]; then
    print_status "PASS" "Backend requirements.txt found"
else
    print_status "WARN" "Backend requirements.txt not found"
fi

echo ""
echo "🔐 Checking Azure Permissions..."
echo "==============================="

# Test basic Azure operations
if az account show > /dev/null 2>&1; then
    # Try to list resource groups (basic permission test)
    if az group list --query "[0].name" -o tsv > /dev/null 2>&1; then
        print_status "PASS" "Can list resource groups (basic permissions OK)"
    else
        print_status "FAIL" "Cannot list resource groups. Check permissions."
    fi
    
    # Check if we can create resources (test with location listing)
    if az account list-locations --query "[0].name" -o tsv > /dev/null 2>&1; then
        print_status "PASS" "Can query Azure locations"
    else
        print_status "WARN" "Limited Azure access detected"
    fi
else
    print_status "FAIL" "Cannot access Azure account information"
fi

echo ""
echo "📊 Validation Summary"
echo "===================="

if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "🎉 ${GREEN}All validations passed!${NC}"
    echo ""
    echo "✅ Ready to deploy Calgary Permit Bot"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Run full deployment:"
    echo "      ./deploy/quick-deploy.sh"
    echo ""
    echo "   2. Or run step-by-step:"
    echo "      ./deploy/01-prepare-resources.sh"
    echo "      ./deploy/02-deploy-app.sh"
    echo ""
    echo "   3. Or use GitHub Actions workflow"
    exit 0
else
    echo -e "⚠️  ${YELLOW}Some validations failed${NC}"
    echo ""
    echo "❌ Please resolve the issues above before deployment"
    echo ""
    echo "💡 Common fixes:"
    echo "   - Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    echo "   - Login to Azure: az login"
    echo "   - Install Node.js: https://nodejs.org/"
    echo "   - Check directory structure and file locations"
    exit 1
fi