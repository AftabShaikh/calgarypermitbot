#!/bin/bash

echo "🚀 Simple Azure Deployment Using azd (Official Method)"
echo "===================================================="

# Install Azure Developer CLI if not already installed
if ! command -v azd &> /dev/null; then
    echo "Installing Azure Developer CLI..."
    curl -fsSL https://aka.ms/install-azd.sh | bash
    source ~/.bashrc
fi

# Authenticate
echo "Authenticating with Azure..."
azd auth login

# Create environment
echo "Creating new azd environment..."
azd env new

# Set deployment target to App Service
echo "Configuring for App Service deployment..."
azd env set DEPLOYMENT_TARGET appservice
azd env set AZURE_CONTAINER_APPS_WORKLOAD_PROFILE Consumption

# Deploy everything
echo "Deploying application..."
azd up

echo "✅ Deployment completed!"
echo "Check the azd output for your application URL."