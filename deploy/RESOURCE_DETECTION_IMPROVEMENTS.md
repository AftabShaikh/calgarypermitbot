# Resource Detection Improvements

## Changes Made to `01-prepare-resources.sh`

### 1. Enhanced OpenAI Service Detection

**Problem**: Script was not able to detect existing OpenAI services reliably.

**Solution**: Improved the `find_existing_resource "openai"` function with 8 different detection methods:

1. **Method 1**: Exact kind match (`kind=='OpenAI'`)
2. **Method 2**: Case insensitive kind match
3. **Method 3**: Kind containing 'openai'
4. **Method 4**: Check for services with OpenAI model deployments (GPT/embedding models)
5. **Method 5**: Services with 'openai' in name
6. **Method 6**: AI-related naming patterns (gpt, ai-, -ai, chat)
7. **Method 7**: OpenAI endpoint patterns
8. **Method 8**: Check service capabilities for OpenAI API support

**Added Features**:
- Enhanced debugging output showing all cognitive services in table format
- Step-by-step detection method testing with results
- Better error handling and fallback mechanisms

### 2. Enhanced Web App Detection

**Problem**: Script was not detecting existing backend and frontend web apps.

**Solution**: Improved detection for both backend and frontend apps:

#### Backend Web App Detection (`webapp-backend`):
1. **Method 1**: Look for Python runtime in `linuxFxVersion`
2. **Method 2**: Apps with 'backend', 'api', or 'back' in name
3. **Method 3**: Python runtime in different property paths
4. **Method 4**: Check app settings for Python-related configurations (python, .py, gunicorn, flask, django)

#### Frontend Web App Detection (`webapp-frontend`):
1. **Method 1**: Look for Node.js runtime in `linuxFxVersion`
2. **Method 2**: Apps with 'frontend', 'front', 'ui', or 'web' in name
3. **Method 3**: Node runtime in different property paths
4. **Method 4**: Check app settings for Node.js-related configurations (node, npm, .js, express, react, angular, vue)
5. **Method 5**: Select remaining apps that don't look like backend

**Added Features**:
- Debug output showing all web apps in table format
- Enhanced logging when existing apps are found
- Config name update tracking

### 3. Improved Resource Re-detection in Phase 4

**Problem**: Missing frontend app re-detection in Phase 4 configuration.

**Solution**: 
- Added frontend web app re-detection logic
- Enhanced debug output to show both backend and frontend app names
- Consistent error handling across all resource types

### 4. Better User Feedback

**Improvements**:
- Enhanced debug logging with emojis and clear step indicators
- Table output for better resource visibility
- Config update tracking (showing original vs detected names)
- Method-by-method detection feedback

## Testing the Improvements

To test these improvements:

1. Run the script with existing resources in your resource group
2. Check the debug output to see detection methods in action
3. Verify that existing resources are properly detected and used
4. Environment variables should be updated to use detected resource names

## Expected Behavior

- **OpenAI Service**: Should detect any existing OpenAI/cognitive service even if not named exactly as configured
- **Backend App**: Should detect Python web apps by runtime, name patterns, or configuration
- **Frontend App**: Should detect Node.js web apps by runtime, name patterns, or configuration
- **All Resources**: Environment variables automatically updated to use detected names

## Debug Output Examples

```bash
📋 All cognitive services in resource group:
Name              Kind      Location    Endpoint
my-openai-svc     OpenAI    eastus      https://my-openai-svc.openai.azure.com/

🔍 Primary detection result: 'my-openai-svc'
✅ Found existing OpenAI Service 'my-openai-svc' - skipping creation
📝 Config updated: 'calgary-openai-12345' → 'my-openai-svc'
```

This should resolve the issues with existing resource detection.