#!/bin/bash
echo "=== Custom Build Script ==="
echo "Using pip instead of poetry"

cd /home/site/wwwroot

# Install requirements using pip
if [ -f "requirements.txt" ]; then
    echo "Installing from requirements.txt"
    pip install --upgrade pip
    pip install -r requirements.txt --no-cache-dir
else
    echo "No requirements.txt found"
fi

echo "=== Build Complete ==="