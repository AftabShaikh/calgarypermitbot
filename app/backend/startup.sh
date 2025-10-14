#!/bin/bash

# Startup script for Calgary Permit Bot Backend on Azure App Service
echo "🚀 Calgary Permit Bot Backend - Startup Script"
echo "=============================================="

# Set environment variables
export PYTHONPATH="/home/site/wwwroot:$PYTHONPATH"
export RUNNING_IN_PRODUCTION="true"
export WEBSITE_HOSTNAME="true"

# Navigate to application directory
cd /home/site/wwwroot

echo "📍 Current directory: $(pwd)"
echo "📁 Directory contents:"
ls -la

# Check if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "✅ Found requirements.txt"
    echo "📦 Installing Python dependencies..."
    
    # Install dependencies with verbose output
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt --verbose --no-cache-dir
    
    echo "✅ Dependencies installed"
else
    echo "❌ requirements.txt not found!"
    exit 1
fi

# Check if key modules are available
echo "🔍 Checking key dependencies..."
python -c "import quart; print('✅ quart imported successfully')" || echo "❌ quart import failed"
python -c "import gunicorn; print('✅ gunicorn imported successfully')" || echo "❌ gunicorn import failed"
python -c "import azure.identity; print('✅ azure.identity imported successfully')" || echo "❌ azure.identity import failed"

# Check application structure
echo "🔍 Checking application files..."
[ -f "run_app.py" ] && echo "✅ run_app.py found" || echo "❌ run_app.py not found"
[ -f "main.py" ] && echo "✅ main.py found" || echo "❌ main.py not found"
[ -f "app.py" ] && echo "✅ app.py found" || echo "❌ app.py not found"

echo "🚀 Starting application..."

# Primary startup method: Use safe startup script
if [ -f "safe_startup.py" ]; then
    echo "Method 1: Using safe startup script (recommended)"
    exec python safe_startup.py
elif [ -f "run_app.py" ]; then
    echo "Method 2: Using run_app.py directly"
    exec python run_app.py
elif [ -f "main.py" ]; then
    echo "Method 3: Using gunicorn with main.py"
    exec gunicorn --bind 0.0.0.0:8000 --worker-class uvicorn.workers.UvicornWorker main:app
elif [ -f "app.py" ]; then
    echo "Method 4: Using gunicorn with app.py"
    exec gunicorn --bind 0.0.0.0:8000 --worker-class uvicorn.workers.UvicornWorker app:app
else
    echo "❌ No suitable application entry point found"
    exit 1
fi