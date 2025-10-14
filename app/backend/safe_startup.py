#!/usr/bin/env python3
"""
Safe startup script for Calgary Permit Bot Backend
This script handles dependency installation and graceful startup
"""

import os
import sys
import subprocess
import time
from pathlib import Path

def log(message):
    """Simple logging function"""
    print(f"[STARTUP] {message}", flush=True)

def install_dependencies():
    """Install Python dependencies with error handling"""
    log("🔍 Checking Python dependencies...")
    
    # Check if requirements.txt exists
    req_files = []
    if Path("requirements-core.txt").exists():
        req_files.append("requirements-core.txt")
        log("✅ Found requirements-core.txt")
    if Path("requirements.txt").exists():
        req_files.append("requirements.txt")
        log("✅ Found requirements.txt")
    
    if not req_files:
        log("❌ No requirements files found!")
        return False
    
    # Try to install dependencies
    for req_file in req_files:
        log(f"📦 Installing dependencies from {req_file}...")
        try:
            # Upgrade pip first
            subprocess.run([sys.executable, "-m", "pip", "install", "--upgrade", "pip"], 
                         check=True, capture_output=True, text=True)
            
            # Install requirements
            result = subprocess.run([
                sys.executable, "-m", "pip", "install", 
                "-r", req_file, 
                "--no-cache-dir", 
                "--verbose"
            ], check=True, capture_output=True, text=True, timeout=600)
            
            log(f"✅ Successfully installed dependencies from {req_file}")
            return True
            
        except subprocess.TimeoutExpired:
            log(f"⏰ Timeout installing from {req_file}")
            continue
        except subprocess.CalledProcessError as e:
            log(f"❌ Failed to install from {req_file}: {e}")
            log(f"stderr: {e.stderr}")
            continue
        except Exception as e:
            log(f"❌ Unexpected error with {req_file}: {e}")
            continue
    
    return False

def check_dependencies():
    """Check if key dependencies are available"""
    dependencies = [
        ("quart", "Quart web framework"),
        ("azure.identity", "Azure Identity"),
        ("azure.storage.blob", "Azure Storage"),
        ("openai", "OpenAI client")
    ]
    
    log("🔍 Checking key dependencies...")
    missing = []
    
    for module, description in dependencies:
        try:
            __import__(module)
            log(f"✅ {description} - OK")
        except ImportError:
            log(f"❌ {description} - MISSING")
            missing.append(module)
    
    return len(missing) == 0, missing

def create_simple_app():
    """Create a minimal Flask app as fallback"""
    log("🔄 Creating minimal fallback app...")
    
    try:
        from quart import Quart, jsonify
        
        app = Quart(__name__)
        
        @app.route('/')
        async def index():
            return jsonify({
                "message": "Calgary Permit Bot - Safe Mode",
                "status": "running",
                "mode": "minimal"
            })
        
        @app.route('/health')
        async def health():
            return jsonify({"status": "healthy", "mode": "safe"})
        
        return app
    except ImportError:
        log("❌ Cannot create even minimal app - quart not available")
        return None

def main():
    """Main startup routine"""
    log("🚀 Calgary Permit Bot - Safe Startup")
    log("=" * 50)
    
    # Set environment variables
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["PYTHONPATH"] = f"/home/site/wwwroot:{os.environ.get('PYTHONPATH', '')}"
    
    log(f"📍 Working directory: {os.getcwd()}")
    log(f"🐍 Python version: {sys.version}")
    log(f"📦 Python path: {sys.path[:3]}...")
    
    # List current directory
    log("📁 Directory contents:")
    for item in sorted(os.listdir(".")):
        log(f"   {item}")
    
    # Install dependencies
    if not install_dependencies():
        log("⚠️ Dependency installation failed, but continuing...")
    
    # Check dependencies
    deps_ok, missing = check_dependencies()
    if not deps_ok:
        log(f"⚠️ Missing dependencies: {missing}")
    
    # Try to start the main application
    log("🔄 Attempting to start main application...")
    
    try:
        # Try importing the main app
        if Path("run_app.py").exists():
            log("📄 Using run_app.py...")
            exec(open("run_app.py").read())
        elif Path("main.py").exists():
            log("📄 Using main.py...")
            from main import app
            port = int(os.environ.get("PORT", 8000))
            app.run(host="0.0.0.0", port=port, debug=False)
        else:
            log("📄 Using fallback app...")
            app = create_simple_app()
            if app:
                port = int(os.environ.get("PORT", 8000))
                app.run(host="0.0.0.0", port=port, debug=False)
            else:
                log("❌ Cannot create any app")
                sys.exit(1)
                
    except Exception as e:
        log(f"❌ Application startup failed: {e}")
        log("🔄 Trying fallback mode...")
        
        try:
            app = create_simple_app()
            if app:
                port = int(os.environ.get("PORT", 8000))
                log(f"🚀 Starting fallback app on port {port}")
                app.run(host="0.0.0.0", port=port, debug=False)
            else:
                log("❌ Fallback failed")
                sys.exit(1)
        except Exception as e2:
            log(f"❌ Fallback also failed: {e2}")
            sys.exit(1)

if __name__ == "__main__":
    main()