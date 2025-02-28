#!/bin/bash
# Improved down-ai.sh script that removes symbolic links instead of deleting files
# This script stops the AI services and disables their Nginx configurations

set -e

echo "Stopping AI services..."

# Function to check if a command succeeded and provide feedback
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        exit 1
    fi
}

# Stop all AI services
echo "Stopping all AI services..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai down
check_status "Stopped all AI services"

# Disable AI service configurations by removing symbolic links
echo "Disabling AI service configurations..."

# Remove qdrant.conf symbolic link if it exists
if [ -L "/home/groot/nginx/sites-enabled/qdrant.conf" ]; then
    rm -f /home/groot/nginx/sites-enabled/qdrant.conf
    check_status "Removed symbolic link for qdrant.conf from sites-enabled"
else
    echo "⚠️ qdrant.conf symbolic link not found in sites-enabled. Skipping removal."
fi

# Remove ollama.conf symbolic link if it exists
if [ -L "/home/groot/nginx/sites-enabled/ollama.conf" ]; then
    rm -f /home/groot/nginx/sites-enabled/ollama.conf
    check_status "Removed symbolic link for ollama.conf from sites-enabled"
else
    echo "⚠️ ollama.conf symbolic link not found in sites-enabled. Skipping removal."
fi

# Reload nginx configuration if nginx is running
if docker ps | grep -q "core-nginx"; then
    echo "Reloading nginx configuration..."
    docker exec -it core-nginx nginx -s reload
    check_status "Reloaded nginx configuration"
else
    echo "⚠️ core-nginx container is not running. Skipping nginx reload."
fi

echo "AI services shutdown completed." 