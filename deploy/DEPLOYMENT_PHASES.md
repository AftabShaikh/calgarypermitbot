# Calgary Permit Bot - Deployment Phases Overview

This document explains the reorganized deployment process that creates backend infrastructure services first, then app services, ensuring proper dependency order and minimizing deployment failures.

## Phase Structure

### Phase 1: Backend Infrastructure Services
**Purpose**: Create core data and AI services that the application depends on

1. **Storage Account** (`$STORAGE_ACCOUNT`)
   - Standard_LRS storage with blob access
   - Creates `content` container for documents
   - Smart wait logic ensures account is fully provisioned

2. **Azure AI Search** (`$SEARCH_SERVICE`) 
   - Standard tier search service
   - Waits for service to be running before continuing
   - Creates foundation for document indexing

3. **Azure OpenAI Service** (`$OPENAI_SERVICE`)
   - Deploys GPT-4o-mini for chat (gpt-4o-mini model)  
   - Deploys text-embedding-3-large for embeddings
   - Validates model deployments before proceeding

4. **Cosmos DB Account** (`$COSMOS_ACCOUNT`)
   - NoSQL account for conversation history
   - Creates `chathistory` database
   - Creates `chatcontainer` for storing chat sessions
   - Ensures database/container are accessible

### Phase 2: App Service Infrastructure
**Purpose**: Create hosting infrastructure once backend services are ready

5. **App Service Plan** (`$APP_SERVICE_PLAN`)
   - Standard S1 tier for production workloads
   - Linux-based hosting environment

6. **Backend Web App** (`$BACKEND_APP_NAME`)
   - Python 3.11 runtime
   - Managed identity enabled for secure access
   - Links to all Phase 1 services

7. **Frontend Web App** (`$FRONTEND_APP_NAME`)  
   - Node.js runtime for React application
   - Connects to backend API

### Phase 3: Identity and Permissions Configuration
**Purpose**: Configure security and access controls

8. **Managed Identity Setup**
   - Enables system-assigned managed identity
   - Eliminates need for service credentials

9. **Role Assignments**
   - Storage Blob Data Contributor (for document access)
   - Search Index Data Contributor (for search operations)
   - Search Service Contributor (for service management)
   - Cognitive Services OpenAI User (for AI model access)  
   - Cosmos DB Account Reader Role (for database access)

### Phase 4: Application Configuration
**Purpose**: Configure application settings and environment variables

10. **Backend App Settings**
    - All Azure service connection details
    - Model deployment names and endpoints
    - Database and container configurations
    - Build and deployment settings

## Smart Wait Logic

Each service creation includes intelligent status checking:

- **Immediate Success Detection**: Stops waiting as soon as service is ready
- **Real-time Status Updates**: Shows current provisioning state
- **Failure Detection**: Identifies failed deployments quickly
- **Timeout Protection**: Prevents indefinite hanging
- **Context-aware Messages**: Meaningful progress indicators

## Benefits of This Approach

1. **Dependency Resolution**: Backend services are fully ready before apps that use them
2. **Faster Deployment**: Smart waiting reduces total deployment time
3. **Better Error Handling**: Clear failure messages at each phase
4. **Reduced Complexity**: Linear progression through logical phases
5. **Easier Debugging**: Issues isolated to specific phases

## Usage

```bash
# Run complete resource preparation
./01-prepare-resources.sh

# Run with detailed output
./01-prepare-resources.sh --verbose

# Run complete deployment
./deploy-all.sh
```

## Configuration Output

The script saves all deployment details to `/tmp/deployment-config.env` for use by subsequent deployment scripts.

## Error Recovery

If deployment fails at any phase:

1. Check the phase where failure occurred
2. Review service-specific error messages
3. Use `./troubleshoot.sh` for detailed diagnostics
4. Re-run deployment (idempotent operations)