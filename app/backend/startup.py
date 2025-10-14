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
        logger.error(f"Missing packages: {missing}")
        return False
    
    logger.info("✅ All core dependencies available")
    return True

def start_app():
    """Start the Calgary Permit Bot application"""
    try:
        logger.info("🔄 Loading Calgary Permit Bot...")
        
        # Import and run the application
        from run_app import create_fallback_app
        
        # Try to import the main app first
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
        logger.info(f"🚀 Starting server on port {port}")
        
        # Run with Quart
        application.run(host="0.0.0.0", port=port, debug=False)
        
    except Exception as e:
        logger.error(f"❌ Failed to start application: {e}")
        return False
    
    return True

if __name__ == "__main__":
    if setup_environment() and check_dependencies():
        start_app()
    else:
        logger.error("❌ Startup failed")
        sys.exit(1)