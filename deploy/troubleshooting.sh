#!/bin/bash

# Calgary Permit Bot - Deployment Troubleshooting Script
# This script helps diagnose and fix common deployment issues

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

echo "🔧 Calgary Permit Bot - Deployment Troubleshooting"
echo "=================================================="
echo "Backend App: $BACKEND_APP_NAME"
echo "Frontend App: $FRONTEND_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Function to fix Python dependency issues
fix_python_dependencies() {
    echo "🔧 Fixing Python dependency issues..."
    
    # Update app settings for better Python support
    az webapp config appsettings set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --settings \
            SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
            ENABLE_ORYX_BUILD="true" \
            PYTHON_ENABLE_GUNICORN_MULTICORE="false" \
            PYTHONPATH="/home/site/wwwroot" \
            XDG_CACHE_HOME="/tmp/.cache" \
            ORYX_ENV_TYPE="prod-dependencies-only" \
            BUILD_FLAGS="" \
            PRE_BUILD_SCRIPT_PATH="" \
            POST_BUILD_SCRIPT_PATH="" \
            RUNNING_IN_PRODUCTION="true"
    
    # Set proper startup command
    az webapp config set \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --startup-file "safe_startup.py"
    
    echo "✅ Python configuration updated"
}

# Function to restart and wait for apps
restart_and_wait() {
    echo "🔄 Restarting backend application..."
    az webapp restart --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
    
    echo "⏳ Waiting for application to start..."
    sleep 60
    
    echo "🔄 Restarting frontend application..."
    az webapp restart --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP
    
    echo "⏳ Waiting for frontend to start..."
    sleep 30
}

# Function to check logs for common issues
check_logs() {
    echo "📝 Checking backend logs for common issues..."
    
    # Get recent logs
    BACKEND_LOGS=$(az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --provider filesystem 2>/dev/null | tail -50)
    
    # Check for common issues
    if echo "$BACKEND_LOGS" | grep -q "ModuleNotFoundError"; then
        echo "❌ Found ModuleNotFoundError in logs"
        echo "🔧 This indicates missing Python dependencies"
        echo "Recommended action: Fix Python dependencies"
        return 1
    fi
    
    if echo "$BACKEND_LOGS" | grep -q "Could not find virtual environment"; then
        echo "❌ Found virtual environment issues"
        echo "🔧 This indicates Oryx build problems"
        echo "Recommended action: Fix Python dependencies"
        return 1
    fi
    
    if echo "$BACKEND_LOGS" | grep -q "startup.sh"; then
        echo "✅ Startup script is being executed"
    else
        echo "⚠️  Startup script may not be configured properly"
    fi
    
    return 0
}

# Function to deploy minimal version
deploy_minimal() {
    echo "🔧 Deploying minimal version with core dependencies..."
    
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    BACKEND_FOLDER="$PROJECT_ROOT/app/backend"
    
    if [ ! -d "$BACKEND_FOLDER" ]; then
        echo "❌ Backend folder not found at $BACKEND_FOLDER"
        return 1
    fi
    
    cd "$BACKEND_FOLDER"
    
    # Create minimal deployment
    MINIMAL_DEPLOY="/tmp/backend-troubleshoot-minimal.zip"
    
    # Copy essential files only
    rm -rf /tmp/backend-minimal
    mkdir -p /tmp/backend-minimal
    
    # Copy core files
    cp safe_startup.py /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ safe_startup.py not found"
    cp run_app.py /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ run_app.py not found"
    cp main.py /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ main.py not found"
    cp app.py /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ app.py not found"
    cp startup.sh /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ startup.sh not found"
    cp requirements-core.txt /tmp/backend-minimal/requirements.txt 2>/dev/null || cp requirements.txt /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ No requirements file found"
    
    # Copy essential directories
    cp -r core /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ core directory not found"
    cp -r approaches /tmp/backend-minimal/ 2>/dev/null || echo "⚠️ approaches directory not found"
    
    # Create deployment package
    cd /tmp/backend-minimal
    zip -r "$MINIMAL_DEPLOY" .
    
    echo "📦 Minimal package created: $MINIMAL_DEPLOY"
    echo "📊 Size: $(ls -lh "$MINIMAL_DEPLOY" | awk '{print $5}')"
    
    # Deploy minimal version
    echo "🚀 Deploying minimal version..."
    if az webapp deploy \
        --name $BACKEND_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --src-path "$MINIMAL_DEPLOY" \
        --type zip; then
        echo "✅ Minimal deployment successful!"
        return 0
    else
        echo "❌ Minimal deployment failed"
        return 1
    fi
}

# Main troubleshooting menu
show_menu() {
    echo ""
    echo "🛠️  Troubleshooting Options:"
    echo "=========================="
    echo "1. Check current status and logs"
    echo "2. Fix Python dependency issues"
    echo "3. Restart applications and wait"
    echo "4. Deploy minimal version (core dependencies only)"
    echo "5. Run full diagnostic"
    echo "6. Show manual deployment instructions"
    echo "7. Clean up and redeploy"
    echo "8. Exit"
    echo ""
}

# Main loop
while true; do
    show_menu
    read -p "Choose an option (1-8): " choice
    
    case $choice in
        1)
            echo "🔍 Checking current status..."
            ./check-deployment-status.sh
            ;;
        2)
            fix_python_dependencies
            ;;
        3)
            restart_and_wait
            ;;
        4)
            deploy_minimal
            ;;
        5)
            echo "🔍 Running full diagnostic..."
            check_logs
            ./check-deployment-status.sh
            ;;
        6)
            echo "📋 Manual Deployment Instructions:"
            echo "=================================="
            echo "1. Use Azure Portal:"
            echo "   https://portal.azure.com → $BACKEND_APP_NAME → Deployment Center"
            echo ""
            echo "2. Use manual deployment script:"
            echo "   ./deploy/manual-backend-deploy.sh"
            echo ""
            echo "3. Try minimal deployment:"
            echo "   Select option 4 from this menu"
            ;;
        7)
            echo "🧹 Cleaning up and redeploying..."
            read -p "This will restart the full deployment process. Continue? (y/N): " confirm
            if [[ $confirm == [yY] ]]; then
                ./02-deploy-app.sh
            fi
            ;;
        8)
            echo "👋 Exiting troubleshooting"
            break
            ;;
        *)
            echo "❌ Invalid option. Please choose 1-8."
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done