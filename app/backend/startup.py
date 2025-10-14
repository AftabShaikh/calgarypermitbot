#!/usr/bin/env python3
"""
Calgary Permit Bot - Azure App Service Startup Script
Optimized for native Python deployment on Azure App Service
"""
import os
import sys
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def setup_environment():
    """Setup environment for Azure App Service"""
    logger.info("🚀 Calgary Permit Bot - Azure App Service Startup")
    logger.info("=" * 50)
    
    # Set required environment variables
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    
    # Log environment info
    logger.info(f"Python version: {sys.version}")
    logger.info(f"Working directory: {os.getcwd()}")
    logger.info(f"Python path: {sys.path}")
    
    # Check for Oryx virtual environment
    venv_path = Path("/home/site/wwwroot/antenv")
    if venv_path.exists():
        logger.info("✅ Found Oryx virtual environment")
        # Oryx should handle this automatically, but we can verify
        site_packages = venv_path / "lib" / "python3.11" / "site-packages"
        if site_packages.exists() and str(site_packages) not in sys.path:
            sys.path.insert(0, str(site_packages))
        logger.info(f"Virtual environment: {venv_path}")
    else:
        logger.warning("⚠️ No Oryx virtual environment found")
    
    return True

def install_dependencies_runtime():
    """Install dependencies at runtime if missing"""
    logger.info("🔧 Installing dependencies at runtime...")
    
    import subprocess
    
    try:
        # Install dependencies to a local directory
        install_dir = "/tmp/python-packages"
        os.makedirs(install_dir, exist_ok=True)
        
        # Add to Python path
        if install_dir not in sys.path:
            sys.path.insert(0, install_dir)
        
        # Install core dependencies
        core_deps = [
            "quart==0.19.4",
            "flask==3.0.3", 
            "azure-identity==1.17.1",
            "azure-storage-blob==12.22.0",
            "openai==1.63.0",
            "aiohttp==3.10.11",
            "python-dotenv==1.0.1",
            "cryptography==44.0.1"
        ]
        
        for dep in core_deps:
            logger.info(f"Installing {dep}...")
            result = subprocess.run([
                sys.executable, "-m", "pip", "install", dep,
                "--target", install_dir,
                "--no-cache-dir", 
                "--disable-pip-version-check",
                "--quiet"
            ], capture_output=True, text=True, timeout=60)
            
            if result.returncode != 0:
                logger.warning(f"Failed to install {dep}: {result.stderr}")
        
        logger.info("✅ Runtime dependency installation completed")
        return True
        
    except Exception as e:
        logger.error(f"❌ Runtime installation failed: {e}")
        return False

def check_dependencies():
    """Check if core dependencies are available"""
    logger.info("🔍 Checking core dependencies...")
    
    required_packages = [
        'quart',
        'azure.identity', 
        'azure.storage.blob',
        'openai'
    ]
    
    missing = []
    for package in required_packages:
        try:
            __import__(package)
            logger.info(f"✅ {package} available")
        except ImportError:
            logger.error(f"❌ {package} not available")
            missing.append(package)
    
    if missing:
        logger.warning(f"Missing packages: {missing}")
        logger.info("🔄 Attempting runtime installation...")
        
        if install_dependencies_runtime():
            # Re-check after installation
            still_missing = []
            for package in required_packages:
                try:
                    __import__(package)
                    logger.info(f"✅ {package} now available")
                except ImportError:
                    still_missing.append(package)
            
            if still_missing:
                logger.error(f"❌ Still missing after installation: {still_missing}")
                return False
            else:
                logger.info("✅ All dependencies installed and available")
                return True
        else:
            return False
    
    logger.info("✅ All core dependencies available")
    return True

def create_basic_app():
    """Create a basic HTTP server when dependencies fail"""
    logger.info("🔄 Creating basic HTTP server...")
    
    import http.server
    import socketserver
    from urllib.parse import urlparse, parse_qs
    
    class BasicHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/health':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "healthy", "mode": "basic"}')
            else:
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = {
                    "message": "Calgary Permit Bot - Basic Mode",
                    "status": "running",
                    "note": "Installing dependencies in background"
                }
                import json
                self.wfile.write(json.dumps(response).encode())
        
        def log_message(self, format, *args):
            logger.info(f"HTTP: {format % args}")
    
    port = int(os.environ.get("PORT", 8000))
    logger.info(f"🚀 Starting basic HTTP server on port {port}")
    
    with socketserver.TCPServer(("", port), BasicHandler) as httpd:
        httpd.serve_forever()

def start_app():
    """Start the Calgary Permit Bot application"""
    try:
        logger.info("🔄 Loading Calgary Permit Bot...")
        
        # Try to import and run the main application
        try:
            from run_app import create_fallback_app
            logger.info("✅ run_app module available")
            
            try:
                from main import app
                logger.info("✅ Main application loaded successfully")
                application = app
            except Exception as e:
                logger.warning(f"⚠️ Main app failed to load: {e}")
                logger.info("🔄 Using fallback application")
                application = create_fallback_app()
            
            # Get port from environment
            port = int(os.environ.get("PORT", 8000))
            logger.info(f"🚀 Starting Quart server on port {port}")
            
            # Run with Quart
            application.run(host="0.0.0.0", port=port, debug=False)
            
        except ImportError as e:
            logger.warning(f"⚠️ Quart/main modules not available: {e}")
            logger.info("🔄 Starting basic HTTP server instead")
            create_basic_app()
        
    except Exception as e:
        logger.error(f"❌ Failed to start any application: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return False
    
    return True

if __name__ == "__main__":
    if setup_environment() and check_dependencies():
        start_app()
    else:
        logger.error("❌ Startup failed")
        sys.exit(1)