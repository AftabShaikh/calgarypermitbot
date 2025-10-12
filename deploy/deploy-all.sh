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
echo "- App Service Plan: B1 (Basic)"
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
./deploy/01-prepare-resources.sh

echo ""
echo "📋 Pausing for 30 seconds to allow resources to be fully ready..."
sleep 30

echo ""
echo "🚀 Step 2: Deploying Applications..."
echo "===================================="
./deploy/02-deploy-app.sh

echo ""
echo "✅ Complete deployment finished!"
echo "==============================="