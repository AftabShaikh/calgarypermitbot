# Configuration Persistence Fix

## Problem Identified

The `02-deploy-app.sh` script was not using the updated resource names detected by `01-prepare-resources.sh` because:

1. **Loading Order Issue**: The `02-deploy-app.sh` script loaded configurations in wrong order:
   - First: `/tmp/deployment-config.env` (detected values) ✅
   - Second: `config.sh` (original values) ❌ **This overwrote the detected values!**

2. **Variable Completeness**: Some variables were missing from the saved deployment config

## Solution Implemented

### 1. Fixed Configuration Loading Order in `02-deploy-app.sh`

**Before:**
```bash
# Load detected values first
source /tmp/deployment-config.env
# Load original config second (OVERWRITES detected values!)
source config.sh
```

**After:**
```bash
# Load base config first (provides defaults)
source config.sh  
# Load detected values second (TAKES PRECEDENCE)
source /tmp/deployment-config.env
```

### 2. Enhanced Configuration Saving in `01-prepare-resources.sh`

**Improvements:**
- Added comprehensive variable saving with all required fields
- Added proper export statements for all variables
- Ensured critical variables have default values
- Added timestamp and source documentation
- Added debug output showing final configuration before saving

**New saved variables include:**
- All detected resource names (storage, search, openai, cosmos, webapps)
- Connection strings and endpoints
- Deployment settings (timeout, versions, etc.)
- Proper defaults for container names and database names

### 3. Added Configuration Finalization

Before saving the config, the script now:
- Ensures all critical variables have proper values
- Sets defaults for container/database names if not set
- Shows debug output of final configuration
- Validates all resources are properly detected

### 4. Enhanced Debug Output

**In `01-prepare-resources.sh`:**
- Shows final configuration summary before saving
- Tracks when variables are updated vs original config

**In `02-deploy-app.sh`:**
- Shows which resources are being used
- Confirms configuration was loaded from preparation script

## Expected Behavior Now

1. **Run `01-prepare-resources.sh`**: 
   - Detects existing resources or creates new ones
   - Updates environment variables to use detected resource names
   - Saves complete configuration to `/tmp/deployment-config.env`

2. **Run `02-deploy-app.sh`**:
   - Loads base config from `config.sh` (for defaults)
   - Loads detected config from `/tmp/deployment-config.env` (takes precedence)
   - Uses the actual detected resource names, not original config names

## Test Case Example

**Original config.sh:**
```bash
STORAGE_ACCOUNT="calgarypermitbotstg51206"
BACKEND_APP_NAME="calgarypermitbot-backend"
```

**After running 01-prepare-resources.sh (detects existing resources):**
```bash
STORAGE_ACCOUNT="existingstorageaccount123"  # ← Detected existing
BACKEND_APP_NAME="my-existing-backend-app"   # ← Detected existing
```

**When 02-deploy-app.sh runs:**
- Will use `existingstorageaccount123` (detected)
- Will use `my-existing-backend-app` (detected)
- Will NOT use the original names from config.sh

This should completely resolve the issue where the deployment script couldn't find the resources.