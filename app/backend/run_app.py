import os
import sys

# Set environment variables that the app expects
os.environ["WEBSITE_HOSTNAME"] = "true"  # This tells the app it's running on Azure
os.environ["RUNNING_IN_PRODUCTION"] = "true"

try:
    from main import app
    print("✅ Successfully imported app from main.py")
    
    # Get port from environment (Azure sets this)
    port = int(os.environ.get("PORT", 8000))
    print(f"🚀 Starting app on port {port}")
    
    # Run the app using Quart's built-in server
    app.run(host="0.0.0.0", port=port, debug=False)
    
except Exception as e:
    print(f"❌ Error starting app: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)