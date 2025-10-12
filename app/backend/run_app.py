import os
import sys
from quart import Quart, jsonify

def create_fallback_app():
    """Create a simple fallback app when full app fails to load"""
    app = Quart(__name__)
    
    @app.route('/')
    async def index():
        return jsonify({
            "message": "Calgary Permit Bot - Basic Mode",
            "status": "running",
            "note": "Some Azure services may not be fully configured yet",
            "endpoints": {
                "health": "/health",
                "status": "/status"
            }
        })
    
    @app.route('/health')
    async def health():
        return jsonify({"status": "healthy", "mode": "fallback"})
    
    @app.route('/status')
    async def status():
        return jsonify({
            "environment_variables": {
                "AZURE_STORAGE_ACCOUNT": bool(os.getenv("AZURE_STORAGE_ACCOUNT")),
                "AZURE_SEARCH_SERVICE": bool(os.getenv("AZURE_SEARCH_SERVICE")), 
                "AZURE_OPENAI_SERVICE": bool(os.getenv("AZURE_OPENAI_SERVICE")),
                "RUNNING_IN_PRODUCTION": os.getenv("RUNNING_IN_PRODUCTION", "false")
            }
        })
    
    return app

if __name__ == "__main__":
    # Set environment variables that the app expects
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    
    # Try to import and run the main app
    try:
        print("🔄 Attempting to start full Calgary Permit Bot...")
        from main import app
        print("✅ Full app imported successfully")
        main_app = app
    except ImportError as e:
        print(f"⚠️  Import error: {e}")
        print("🔄 Starting fallback mode...")
        main_app = create_fallback_app()
    except Exception as e:
        print(f"⚠️  Unexpected error: {e}")
        print("🔄 Starting fallback mode...")
        main_app = create_fallback_app()
    
    # Get port from environment
    port = int(os.environ.get("PORT", 8000))
    print(f"🚀 Starting Calgary Permit Bot on port {port}")
    
    # Run the app
    try:
        main_app.run(host="0.0.0.0", port=port, debug=False)
    except Exception as e:
        print(f"❌ Failed to start server: {e}")
        sys.exit(1)