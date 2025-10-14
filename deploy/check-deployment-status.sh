#!/bin/bash

# Deployment Status Check Script for Calgary Permit Bot
# Use this script to check the status of your deployments

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
if [ -f /tmp/deployment-config.env ]; then
    source /tmp/deployment-config.env
    echo "📋 Configuration loaded"
elif [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    echo "📋 Configuration loaded from config.sh"
else
    echo "❌ Configuration not found. Please run 01-prepare-resources.sh first"
    exit 1
fi

echo "🔍 Calgary Permit Bot - Deployment Status Check"
echo "==============================================="
echo "Backend App: $BACKEND_APP_NAME"
echo "Frontend App: $FRONTEND_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Check backend status
echo "🔧 Backend Status:"
echo "=================="
BACKEND_URL="https://$BACKEND_APP_NAME.azurewebsites.net"
echo "URL: $BACKEND_URL"

# Check if backend is running
if az webapp show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv | grep -q "Running"; then
    echo "✅ Backend app service is running"
else
    echo "❌ Backend app service is not running"
fi

# Check backend health endpoint
echo "Checking health endpoint..."
if curl -f "$BACKEND_URL/health" -m 10 > /dev/null 2>&1; then
    echo "✅ Backend health check passed"
else
    echo "❌ Backend health check failed (service may be starting or not deployed)"
fi

echo ""

# Check frontend status
echo "🎨 Frontend Status:"
echo "=================="
FRONTEND_URL="https://$FRONTEND_APP_NAME.azurewebsites.net"
echo "URL: $FRONTEND_URL"

# Check if frontend is running
if az webapp show --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP --query "state" -o tsv | grep -q "Running"; then
    echo "✅ Frontend app service is running"
else
    echo "❌ Frontend app service is not running"
fi

# Check frontend accessibility
echo "Checking frontend accessibility..."
if curl -f "$FRONTEND_URL" -m 10 > /dev/null 2>&1; then
    echo "✅ Frontend is accessible"
else
    echo "❌ Frontend is not accessible (service may be starting or not deployed)"
fi

echo ""

# Check deployment status
echo "📊 Deployment Information:"
echo "========================="

# Get backend deployment info
echo "Backend last deployment:"
az webapp deployment list --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query "[0].{status:status,author:author,message:message,receivedTime:receivedTime}" -o table 2>/dev/null || echo "No deployment info available"

echo ""

# Get frontend deployment info
echo "Frontend last deployment:"
az webapp deployment list --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP --query "[0].{status:status,author:author,message:message,receivedTime:receivedTime}" -o table 2>/dev/null || echo "No deployment info available"

echo ""

# Show recent logs
echo "📝 Recent Backend Logs (last 20 lines):"
echo "========================================"
az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --provider filesystem 2>/dev/null | tail -20 || echo "Unable to fetch logs"

echo ""
echo "📝 Recent Frontend Logs (last 20 lines):"
echo "========================================="
az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP --provider filesystem 2>/dev/null | tail -20 || echo "Unable to fetch logs"

echo ""
echo "🔗 Quick Links:"
echo "=============="
echo "Frontend: $FRONTEND_URL"
echo "Backend Health: $BACKEND_URL/health"
echo "Backend API: $BACKEND_URL/api"
echo ""
echo "Azure Portal Links:"
echo "Backend: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$BACKEND_APP_NAME"
echo "Frontend: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FRONTEND_APP_NAME"