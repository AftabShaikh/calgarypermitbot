#!/bin/bash

# Calgary Permit Bot - Complete Deployment Script
# This script runs both resource preparation and application deployment

set -e  # Exit on any error

echo "🚀 Calgary Permit Bot - Complete Deployment"
echo "==========================================="
echo ""
echo "This script will:"
echo "1. Create all necessary Azure resources"
echo "2. Deploy the frontend and backend applications"
echo "3. Upload data files to storage"
echo "4. Configure all services"
echo ""
echo "Target Configuration:"
echo "- Location: West US 2"
echo "- App Service Plan: S1 (Standard)"
echo "- Two Web Apps: Frontend + Backend"
echo ""

read -p "Press Enter to continue or Ctrl+C to cancel..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to repository root
cd "$REPO_ROOT"

# Make scripts executable
chmod +x deploy/01-prepare-resources.sh
chmod +x deploy/02-deploy-app.sh

echo ""
echo "🏗️  Step 1: Preparing Azure Resources..."
echo "======================================="
if ! ./deploy/01-prepare-resources.sh; then
    echo "❌ Resource preparation failed!"
    echo "Please check the error messages above and try again."
    exit 1
fi

echo ""
echo "✅ Resource preparation completed successfully!"
echo ""
echo "📋 All resources are ready! Proceeding to application deployment..."
echo "   (Individual resources already waited for readiness)"

echo ""
echo "🚀 Step 2: Deploying Applications..."
echo "===================================="
if ! ./deploy/02-deploy-app.sh; then
    echo "❌ Application deployment failed!"
    echo "Please check the error messages above."
    echo "Resources have been created - you can retry deployment with:"
    echo "  ./deploy/02-deploy-app.sh"
    exit 1
fi

echo ""
echo "✅ Complete deployment finished!"
echo "==============================="