#!/bin/bash
# Improved down-all.sh script that removes symbolic links instead of deleting files
# This script stops all services and disables their Nginx configurations

set -e

echo "Stopping all services..."

# Function to check if a command succeeded and provide feedback
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        exit 1
    fi
}

# Stop all services across all projects
echo "Stopping all Docker services..."
docker compose -p core down
check_status "Stopped core services"

docker compose -p n8n down
check_status "Stopped n8n services"

docker compose -p mcp down
check_status "Stopped mcp services"

docker compose -p ai down
check_status "Stopped ai services"

docker compose -p utility down
check_status "Stopped utility services"

docker compose -p hosted-n8n down
check_status "Stopped hosted-n8n services"

# Disable all service configurations by removing symbolic links
echo "Disabling all service configurations..."

# Keep only core configurations in sites-enabled
echo "Removing all service-specific nginx configurations..."
find /home/groot/nginx/sites-enabled/ -type l -not -name "00-http-redirect.conf" -not -name "default.conf" -not -name "supabase.conf" -exec rm -f {} \;
check_status "Removed symbolic links for service-specific configurations"

# Clean up container nginx configuration if core-nginx container is running
if docker ps | grep -q "core-nginx"; then
    echo "Cleaning up nginx container configuration..."
    
    # Remove all symlinks in container's sites-enabled except for core configs
    docker exec -it core-nginx find /etc/nginx/sites-enabled/ -type l -not -name "00-http-redirect.conf" -not -name "default.conf" -not -name "supabase.conf" -exec rm -f {} \;
    check_status "Removed symbolic links in container's sites-enabled directory"
    
    # Reload nginx configuration
    echo "Reloading nginx configuration..."
    docker exec -it core-nginx nginx -s reload
    check_status "Reloaded nginx configuration"
else
    echo "⚠️ core-nginx container is not running. Skipping container cleanup."
fi

echo "All services stopped and configurations disabled successfully." 