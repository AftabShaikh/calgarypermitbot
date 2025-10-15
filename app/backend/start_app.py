#!/usr/bin/env python3
"""
Robust startup script for Azure App Service
Falls back to basic HTTP server if dependencies fail
"""
import os
import sys
import subprocess
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

def install_critical_deps():
    """Install critical dependencies at runtime"""
    logger.info("Installing critical dependencies...")
    critical_deps = ["quart==0.19.4", "flask==3.0.3", "python-dotenv==1.0.1"]
    
    for dep in critical_deps:
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", dep, "--no-cache-dir", "--quiet"], 
                         check=True, timeout=60)
            logger.info(f"Installed {dep}")
        except Exception as e:
            logger.warning(f"Failed to install {dep}: {e}")

def create_basic_server():
    """Create basic HTTP server"""
    logger.info("Creating basic HTTP server...")
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import json
    
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            if self.path == '/health':
                response = {"status": "healthy", "mode": "basic"}
            else:
                response = {"message": "Calgary Permit Bot", "status": "basic mode"}
            
            self.wfile.write(json.dumps(response).encode())
        
        def log_message(self, format, *args):
            logger.info(format % args)
    
    port = int(os.environ.get("PORT", 8000))
    server = HTTPServer(("0.0.0.0", port), Handler)
    logger.info(f"Basic server running on port {port}")
    server.serve_forever()

if __name__ == "__main__":
    # Set environment
    os.environ["WEBSITE_HOSTNAME"] = "true"
    os.environ["RUNNING_IN_PRODUCTION"] = "true"
    
    try:
        # Try run_app.py first
        logger.info("Attempting to run run_app.py...")
        exec(open('run_app.py').read())
    except Exception as e:
        logger.warning(f"run_app.py failed: {e}")
        try:
            # Try installing dependencies and run again
            install_critical_deps()
            exec(open('run_app.py').read())
        except Exception as e2:
            logger.error(f"All startup methods failed: {e2}")
            create_basic_server()
