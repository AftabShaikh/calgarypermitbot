import os
import sys
from quart import Quart, jsonify

# Create a simple fallback app that can start without Azure services
def create_minimal_app():
    app = Quart(__name__)
    
    @app.route('/')
    async def index():
        return jsonify({
            "message": "Calgary Permit Bot is starting up...",
            "status": "minimal_mode",
            "note": "Azure services need to be configured for full functionality"
        })
    
    @app.route('/health')
    async def health():
        return jsonify({"status": "healthy", "mode": "minimal"})
    
    return app

if __name__ == "__main__":
    # Set environment variables that the app expects
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    
    # Try to import the main app, fall back to minimal if it fails
    try:
        print("🔄 Attempting to start full Calgary Permit Bot...")
        from main import app
        print("✅ Full app loaded successfully")
        main_app = app
    except Exception as e:
        print(f"⚠️  Full app failed to load: {e}")
        print("🔄 Starting in minimal mode...")
        main_app = create_minimal_app()
        print("✅ Minimal app loaded successfully")
    
    # Get port from environment (Azure sets this)
    port = int(os.environ.get("PORT", 8000))
    print(f"🚀 Starting Calgary Permit Bot on port {port}")
    
    # Run the app
    main_app.run(host="0.0.0.0", port=port, debug=False)