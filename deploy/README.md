# Calgary Permit Bot - Deployment Guide

This guide provides multiple deployment options for the Calgary Permit Bot application.

## 🎯 Deployment Options

### Option 1: Azure Cloud Shell (Recommended)
Use the provided deployment scripts directly in Azure Cloud Shell.

### Option 2: GitHub Actions Workflow
Automated deployment using GitHub Actions with full resource provisioning.

### Option 3: Manual Azure CLI
Step-by-step manual deployment using Azure CLI commands.

---

## 🚀 Option 1: Azure Cloud Shell Deployment

### Prerequisites
- Azure subscription with appropriate permissions
- Access to Azure Cloud Shell

### Quick Start
1. **Open Azure Cloud Shell** (https://shell.azure.com)
2. **Clone the repository:**
   ```bash
   git clone https://github.com/AftabShaikh/calgarypermitbot.git
   cd calgarypermitbot
   ```

3. **Run complete deployment (NEW - Enhanced):**
   ```bash
   chmod +x deploy/quick-deploy.sh
   ./deploy/quick-deploy.sh
   ```

   **Alternative options:**
   ```bash
   # Deploy apps only (if resources already exist)
   ./deploy/quick-deploy.sh --skip-prepare
   
   # Skip data upload (if data already uploaded)  
   ./deploy/quick-deploy.sh --skip-data-upload
   
   # Verbose output for troubleshooting
   ./deploy/quick-deploy.sh --verbose
   ```

### Step-by-Step Deployment
If you prefer to run each step separately:

1. **Prepare resources:**
   ```bash
   chmod +x deploy/01-prepare-resources.sh
   ./deploy/01-prepare-resources.sh
   ```

2. **Deploy applications:**
   ```bash
   chmod +x deploy/02-deploy-app.sh
   ./deploy/02-deploy-app.sh
   ```

### What Gets Created
- **Resource Group**: `rg-calgarypermitbot`
- **Location**: West US 2 (configurable)
- **App Service Plan**: B1 tier (Basic) - *Updated for cost optimization*
- **Web Apps**: 
  - Backend: `calgarypermitbot-backend`
  - Frontend: `calgarypermitbot-frontend`
- **Storage Account**: For document storage with auto-upload from `data/` folder
- **Azure AI Search**: For document indexing
- **Azure OpenAI**: With GPT-4o-mini and text-embedding models  
- **Cosmos DB**: For chat history (serverless)

### Configuration (NEW)
Deployment settings are now centralized in `deploy/config.sh`. You can customize:

```bash
# Edit deploy/config.sh to customize settings
export LOCATION="eastus"              # Change region
export APP_SERVICE_SKU="S1"           # Change pricing tier
export RESOURCE_GROUP="my-custom-rg"  # Change resource group name
```

**Key Features:**
- ✅ **Backend services created BEFORE web apps** (proper dependency order)
- ✅ **Automatic data upload** from `data/` folder to storage
- ✅ **B1 pricing tier** for cost optimization
- ✅ **US West 2** location as requested
- ✅ **Two-step deployment** process (prepare → deploy)

---

## 🤖 Option 2: GitHub Actions Deployment

### Prerequisites
- Fork this repository to your GitHub account
- Azure service principal with Contributor permissions

### Setup
1. **Create Azure Service Principal:**
   ```bash
   az ad sp create-for-rbac --name "calgarypermitbot-github" \
     --role contributor \
     --scopes /subscriptions/{subscription-id} \
     --sdk-auth
   ```

2. **Add GitHub Secret:**
   - Go to your repository Settings → Secrets and variables → Actions
   - Create a new secret named `AZURE_CREDENTIALS`
   - Paste the JSON output from step 1

### Deploy
1. Go to **Actions** tab in your GitHub repository
2. Select **Deploy Calgary Permit Bot (Complete)**
3. Click **Run workflow**
4. Choose options:
   - ✅ **Create Azure resources**: For first-time deployment
   - **Resource suffix**: Optional (auto-generated if empty)

### Monitor Progress
- Watch the workflow progress in the Actions tab
- Check deployment logs for any issues
- URLs will be displayed at the end of successful deployment

---

## 🛠️ Option 3: Manual Azure CLI Deployment

### Prerequisites
- Azure CLI installed and logged in
- Node.js 20+ and npm installed
- Python 3.11+ installed

### Step 1: Resource Creation
```bash
# Set variables
RESOURCE_GROUP="rg-calgarypermitbot"
LOCATION="westus2"
SUFFIX=$(date +%s | tail -c 6)

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create App Service Plan
az appservice plan create \
  --name "asp-calgarypermitbot" \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku S1 \
  --is-linux

# Create web apps
az webapp create \
  --name "calgarypermitbot-backend-$SUFFIX" \
  --resource-group $RESOURCE_GROUP \
  --plan "asp-calgarypermitbot" \
  --runtime "PYTHON|3.11"

az webapp create \
  --name "calgarypermitbot-frontend-$SUFFIX" \
  --resource-group $RESOURCE_GROUP \
  --plan "asp-calgarypermitbot" \
  --runtime "NODE|20-lts"
```

Continue with storage, AI services, and Cosmos DB creation...

### Step 2: Application Deployment
```bash
# Build frontend
cd app/frontend
npm ci
npm run build
cd ../..

# Deploy backend
cd app/backend
zip -r backend-deploy.zip .
az webapp deploy \
  --name "calgarypermitbot-backend-$SUFFIX" \
  --resource-group $RESOURCE_GROUP \
  --src-path backend-deploy.zip \
  --type zip
cd ../..

# Upload data files
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination content \
  --source data \
  --auth-mode login
```

---

## 🧹 Cleanup

To remove all resources:

### Using Script
```bash
chmod +x deploy/cleanup.sh
./deploy/cleanup.sh
```

### Manual Cleanup
```bash
az group delete --name rg-calgarypermitbot --yes --no-wait
```

---

## 🔧 Configuration

### Environment Variables (Backend)
The following environment variables are automatically configured:

- `AZURE_STORAGE_ACCOUNT`: Storage account name
- `AZURE_STORAGE_CONTAINER`: Container name (content)
- `AZURE_SEARCH_SERVICE`: AI Search service name
- `AZURE_SEARCH_INDEX`: Search index name (gptkbindex)
- `AZURE_OPENAI_SERVICE`: OpenAI service name
- `AZURE_OPENAI_CHATGPT_DEPLOYMENT`: GPT model deployment
- `AZURE_OPENAI_EMB_DEPLOYMENT`: Embedding model deployment
- `AZURE_COSMOSDB_ACCOUNT`: Cosmos DB account name
- `AZURE_CHAT_HISTORY_DATABASE`: Chat history database
- `AZURE_CHAT_HISTORY_CONTAINER`: Chat history container
- `USE_CHAT_HISTORY_COSMOS`: Enable Cosmos DB chat history
- `OPENAI_HOST`: Set to "azure"

### File Upload
The deployment automatically uploads all files from the `data/` folder to the Azure Storage container for document processing.

---

## 🔍 Troubleshooting

### Common Issues

1. **"ServiceDeleting" or Naming Conflict Errors** (NEW)
   ```bash
   # Quick conflict resolution
   ./deploy/cleanup-conflicts.sh --resolve-conflicts
   
   # Check what exists without deleting
   ./deploy/cleanup-conflicts.sh --dry-run
   
   # Force cleanup all resources (CAREFUL!)
   ./deploy/cleanup-conflicts.sh --force
   ```
   
   **What causes this**: Azure services being deleted in background operations, or previous deployments with same names.
   
   **Solutions**:
   - Wait 10-15 minutes for background operations to complete
   - Use the cleanup script to resolve conflicts  
   - The deployment now uses timestamp-based naming to avoid conflicts

2. **Deployment Timeout or Stuck Deployments** (NEW - ENHANCED)
   
   **What happens**: The main deployment script (`02-deploy-app.sh`) now includes:
   - ✅ **Automatic timeout handling** (10 minutes for each deployment)
   - ✅ **Manual deployment fallback** when timeouts occur
   - ✅ **Multiple deployment method options**
   
   **If deployment gets stuck**:
   - The script will automatically timeout after 10 minutes
   - You'll see detailed manual deployment instructions
   - Deployment packages are pre-created and ready for manual upload
   
   **Manual deployment options**:
   ```bash
   # Use dedicated manual deployment scripts
   ./deploy/manual-backend-deploy.sh    # For backend only
   ./deploy/manual-frontend-deploy.sh   # For frontend only
   
   # Check deployment status anytime
   ./deploy/check-deployment-status.sh
   ```
   
   **Manual deployment methods provided**:
   - Azure Portal upload (GUI method)
   - Azure CLI with extended timeout
   - FTP/FTPS deployment
   - Alternative Azure CLI commands
   - Deployment restart and retry logic

3. **Checking Deployment Progress**
   ```bash
   # Real-time status monitoring
   ./deploy/check-deployment-status.sh
   
   # This script shows:
   # - App service status (running/stopped)
   # - Health check results
   # - Recent deployment information
   # - Recent application logs
   # - Direct links to Azure Portal
   ```

2. **Permission Errors**
   - Ensure proper Azure permissions (Contributor role)
   - Check managed identity role assignments

3. **Model Deployment Failures**
   - Verify OpenAI service quota in your region
   - Check model availability in West US 2

4. **Storage Access Issues**
   - Verify managed identity has Storage Blob Data Contributor role
   - Check storage account firewall settings

### Log Checking
```bash
# Backend logs
az webapp log tail --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP

# Frontend logs
az webapp log tail --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP
```

### Health Checks
- Backend: `https://{backend-app-name}.azurewebsites.net/health`
- Frontend: `https://{frontend-app-name}.azurewebsites.net`

---

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review deployment logs in Azure Portal
3. Verify all prerequisites are met
4. Ensure you have sufficient Azure quota for the resources

---

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Frontend      │    │     Backend      │    │  Azure Storage  │
│   (Node.js)     │───▶│   (Python/Flask) │───▶│   (Documents)   │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │                          │
                              ▼                          ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Azure OpenAI   │    │   Cosmos DB      │    │  Azure AI Search│
│   (GPT-4o)      │    │ (Chat History)   │    │   (Indexing)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🎉 Success!

After successful deployment, you'll have:
- ✅ A fully functional Calgary Permit Bot
- ✅ Frontend and backend web applications
- ✅ Document storage and search capabilities
- ✅ AI-powered chat with GPT-4o
- ✅ Chat history persistence
- ✅ All data files uploaded and indexed

Visit your frontend URL to start using the application!

---

## 🛠️ NEW: Enhanced Deployment Scripts

### Available Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `01-prepare-resources.sh` | Creates Azure resources | First-time setup |
| `02-deploy-app.sh` | **Enhanced** with timeout handling | Main deployment (now safer) |
| `manual-backend-deploy.sh` | Manual backend deployment | When auto-deployment times out |
| `manual-frontend-deploy.sh` | Manual frontend deployment | When auto-deployment times out |
| `check-deployment-status.sh` | Monitor deployment progress | Anytime to check status |
| `cleanup.sh` | Remove all resources | When done testing |

### Enhanced Features (NEW)

**Timeout Protection**:
- ✅ Automatic 10-minute timeout for deployments
- ✅ Graceful fallback to manual deployment instructions
- ✅ Pre-prepared deployment packages ready for manual upload

**Multiple Deployment Methods**:
- ✅ Standard Azure CLI deployment (with timeout)
- ✅ Manual Azure Portal upload
- ✅ FTP/FTPS deployment
- ✅ Alternative CLI commands with different options

**Better Monitoring**:
- ✅ Real-time status checks
- ✅ Health endpoint monitoring
- ✅ Recent log display
- ✅ Direct Azure Portal links

### Quick Reference

```bash
# Standard deployment (enhanced with timeouts)
./deploy/01-prepare-resources.sh
./deploy/02-deploy-app.sh

# If deployment gets stuck, you'll see instructions like:
# "💡 Use the provided manual deployment script: ./deploy/manual-backend-deploy.sh"

# Check status anytime
./deploy/check-deployment-status.sh

# Manual deployment if needed
./deploy/manual-backend-deploy.sh     # Backend only
./deploy/manual-frontend-deploy.sh    # Frontend only
```

**What's Different Now**:
- No more indefinite hanging on `az webapp deploy`
- Clear manual deployment instructions when timeouts occur
- Ready-to-use deployment packages
- Better visibility into deployment progress
- Multiple fallback options for reliable deployment