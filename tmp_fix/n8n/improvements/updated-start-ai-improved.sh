#!/bin/bash
# Improved start-ai.sh script that uses symbolic links instead of copying files
# This script starts the AI services and enables their Nginx configurations

set -e

echo "Starting AI services..."

# Function to check if a command succeeded and provide feedback
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        exit 1
    fi
}

# Default to GPU-NVIDIA profile if not specified
HW_PROFILE="${1:-gpu-nvidia}"
echo "Using hardware profile: $HW_PROFILE"

# Validate hardware profile
if [[ ! "$HW_PROFILE" =~ ^(cpu|gpu-nvidia|gpu-amd)$ ]]; then
  echo "❌ Error: Invalid hardware profile. Must be one of: cpu, gpu-nvidia, gpu-amd"
  exit 1
fi

# Ensure the core infrastructure is running
if ! docker ps | grep -q "core-nginx"; then
    echo "❌ Core infrastructure is not running. Please run start-core-improved.sh first."
    exit 1
fi

# Copy the updated configuration files to sites-available if they don't exist
echo "Setting up AI service configurations..."

# Qdrant configuration
if [ ! -f "/home/groot/nginx/sites-available/qdrant.conf" ]; then
    cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-qdrant.conf /home/groot/nginx/sites-available/qdrant.conf
    check_status "Copied updated qdrant.conf to sites-available"
else
    echo "⚠️ qdrant.conf already exists in sites-available. Checking for issues..."
    
    # Fix SSL certificate paths
    if grep -q "/home/groot/nginx/certs/nginx.crt" /home/groot/nginx/sites-available/qdrant.conf; then
        echo "Updating SSL certificate paths in qdrant.conf..."
        sed -i 's|ssl_certificate /home/groot/nginx/certs/nginx.crt;|ssl_certificate /etc/nginx/certs/nginx.crt;|g' /home/groot/nginx/sites-available/qdrant.conf
        sed -i 's|ssl_certificate_key /home/groot/nginx/certs/nginx.key;|ssl_certificate_key /etc/nginx/certs/nginx.key;|g' /home/groot/nginx/sites-available/qdrant.conf
        check_status "Updated SSL certificate paths in qdrant.conf"
    fi
    
    # Fix log format
    if grep -q "access_log /var/log/nginx/qdrant-access.log;" /home/groot/nginx/sites-available/qdrant.conf; then
        echo "Updating log format in qdrant.conf..."
        sed -i 's|access_log /var/log/nginx/qdrant-access.log;|access_log /var/log/nginx/qdrant-access.log unified_json;|g' /home/groot/nginx/sites-available/qdrant.conf
        check_status "Updated log format in qdrant.conf"
    fi
    
    # Add frontend_allowed check if it doesn't exist
    if ! grep -q "frontend_allowed" /home/groot/nginx/sites-available/qdrant.conf; then
        echo "Adding access control to qdrant.conf..."
        sed -i '/error_log .*notice;/a \
    # Access control\
    if ($frontend_allowed = 0) {\
        return 403;\
    }' /home/groot/nginx/sites-available/qdrant.conf
        check_status "Added access control to qdrant.conf"
    fi
    
    # Add rate limiting if it doesn't exist
    if ! grep -q "limit_req zone=api_limit" /home/groot/nginx/sites-available/qdrant.conf; then
        echo "Adding rate limiting to qdrant.conf..."
        sed -i '/# Access control/a \
    # Rate limiting\
    limit_req zone=api_limit burst=10 nodelay;' /home/groot/nginx/sites-available/qdrant.conf
        check_status "Added rate limiting to qdrant.conf"
    fi
    
    # Fix upstream configuration for qdrant
    echo "Checking upstream configuration in qdrant.conf..."
    if ! grep -q "server 10.1.10.111:" /home/groot/nginx/sites-available/qdrant.conf; then
        echo "Updating upstream configuration in qdrant.conf to handle hostname resolution issues..."
        # Create a backup of the original file
        cp /home/groot/nginx/sites-available/qdrant.conf /home/groot/nginx/sites-available/qdrant.conf.bak
        
        # Replace the upstream block with a more robust version that uses IP addresses
        sed -i '/upstream qdrant_backend {/,/}/c\
# Upstream definition with multiple fallback options for qdrant\
upstream qdrant_backend {\
    # Use IP address directly (most reliable in rootless Docker)\
    server 10.1.10.111:6333 max_fails=3 fail_timeout=5s;\
    \
    # Final fallback for maintenance page\
    server 127.0.0.1:6333 backup;\
    \
    keepalive 32;\
}' /home/groot/nginx/sites-available/qdrant.conf
        check_status "Updated upstream configuration in qdrant.conf"
    fi
fi

# Ollama configuration
if [ ! -f "/home/groot/nginx/sites-available/ollama.conf" ]; then
    cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-ollama.conf /home/groot/nginx/sites-available/ollama.conf
    check_status "Copied updated ollama.conf to sites-available"
else
    echo "⚠️ ollama.conf already exists in sites-available. Checking for issues..."
    
    # Fix SSL certificate paths
    if grep -q "/home/groot/nginx/certs/nginx.crt" /home/groot/nginx/sites-available/ollama.conf; then
        echo "Updating SSL certificate paths in ollama.conf..."
        sed -i 's|ssl_certificate /home/groot/nginx/certs/nginx.crt;|ssl_certificate /etc/nginx/certs/nginx.crt;|g' /home/groot/nginx/sites-available/ollama.conf
        sed -i 's|ssl_certificate_key /home/groot/nginx/certs/nginx.key;|ssl_certificate_key /etc/nginx/certs/nginx.key;|g' /home/groot/nginx/sites-available/ollama.conf
        check_status "Updated SSL certificate paths in ollama.conf"
    fi
    
    # Fix log format
    if grep -q "access_log /var/log/nginx/ollama-access.log;" /home/groot/nginx/sites-available/ollama.conf; then
        echo "Updating log format in ollama.conf..."
        sed -i 's|access_log /var/log/nginx/ollama-access.log;|access_log /var/log/nginx/ollama-access.log unified_json;|g' /home/groot/nginx/sites-available/ollama.conf
        check_status "Updated log format in ollama.conf"
    fi
    
    # Add frontend_allowed check if it doesn't exist
    if ! grep -q "frontend_allowed" /home/groot/nginx/sites-available/ollama.conf; then
        echo "Adding access control to ollama.conf..."
        sed -i '/error_log .*notice;/a \
    # Access control\
    if ($frontend_allowed = 0) {\
        return 403;\
    }' /home/groot/nginx/sites-available/ollama.conf
        check_status "Added access control to ollama.conf"
    fi
    
    # Add rate limiting if it doesn't exist
    if ! grep -q "limit_req zone=api_limit" /home/groot/nginx/sites-available/ollama.conf; then
        echo "Adding rate limiting to ollama.conf..."
        sed -i '/# Access control/a \
    # Rate limiting\
    limit_req zone=api_limit burst=10 nodelay;' /home/groot/nginx/sites-available/ollama.conf
        check_status "Added rate limiting to ollama.conf"
    fi
    
    # Fix upstream configuration for ollama
    echo "Checking upstream configuration in ollama.conf..."
    if grep -q "server ollama:11434" /home/groot/nginx/sites-available/ollama.conf && ! grep -q "server 10.1.10.111:11434" /home/groot/nginx/sites-available/ollama.conf; then
        echo "Updating upstream configuration in ollama.conf to handle hostname resolution issues..."
        # Create a backup of the original file
        cp /home/groot/nginx/sites-available/ollama.conf /home/groot/nginx/sites-available/ollama.conf.bak
        
        # Replace the upstream block with a more robust version that uses IP addresses
        sed -i '/upstream ollama_backend {/,/}/c\
# Upstream definition with multiple fallback options for ollama\
upstream ollama_backend {\
    # Use IP address directly (most reliable in rootless Docker)\
    server 10.1.10.111:11434 max_fails=3 fail_timeout=5s;\
    \
    # Final fallback for maintenance page\
    server 127.0.0.1:11434 backup;\
    \
    keepalive 32;\
}' /home/groot/nginx/sites-available/ollama.conf
        check_status "Updated upstream configuration in ollama.conf"
    fi
fi

# Create symbolic links in sites-enabled
echo "Enabling AI service configurations..."
ln -sf /home/groot/nginx/sites-available/qdrant.conf /home/groot/nginx/sites-enabled/qdrant.conf
check_status "Created symbolic link for qdrant.conf in sites-enabled"

ln -sf /home/groot/nginx/sites-available/ollama.conf /home/groot/nginx/sites-enabled/ollama.conf
check_status "Created symbolic link for ollama.conf in sites-enabled"

# Ensure symbolic links exist in the container
echo "Ensuring symbolic links exist in the container..."
if ! docker exec -it core-nginx test -L /etc/nginx/sites-enabled/qdrant.conf; then
    docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled/qdrant.conf /etc/nginx/sites-enabled/qdrant.conf
    check_status "Created symbolic link for qdrant.conf in container"
else
    echo "✅ Symbolic link for qdrant.conf already exists in container"
fi

if ! docker exec -it core-nginx test -L /etc/nginx/sites-enabled/ollama.conf; then
    docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled/ollama.conf /etc/nginx/sites-enabled/ollama.conf
    check_status "Created symbolic link for ollama.conf in container"
else
    echo "✅ Symbolic link for ollama.conf already exists in container"
fi

# Ensure SSL certificates are properly linked
echo "Ensuring SSL certificates are properly linked..."
if ! docker exec -it core-nginx test -L /etc/nginx/certs/nginx.crt; then
    docker exec -it core-nginx ln -sf /home/groot/nginx/certs/nginx.crt /etc/nginx/certs/nginx.crt
    check_status "Created symbolic link for nginx.crt"
fi

if ! docker exec -it core-nginx test -L /etc/nginx/certs/nginx.key; then
    docker exec -it core-nginx ln -sf /home/groot/nginx/certs/nginx.key /etc/nginx/certs/nginx.key
    check_status "Created symbolic link for nginx.key"
fi

# Test nginx configuration before reloading
echo "Testing nginx configuration..."
if ! docker exec -it core-nginx nginx -t 2>/tmp/nginx_error.log; then
    echo "❌ Nginx configuration test failed. Error details:"
    cat /tmp/nginx_error.log
    
    # Check for common errors and try to fix them
    if grep -q "duplicate" /tmp/nginx_error.log; then
        echo "Detected duplicate directive error. Attempting to fix..."
        # Extract the duplicate directive name
        DUPLICATE_DIRECTIVE=$(grep "duplicate" /tmp/nginx_error.log | grep -o '"[^"]*"' | head -1 | tr -d '"')
        if [ -n "$DUPLICATE_DIRECTIVE" ]; then
            echo "Attempting to fix duplicate $DUPLICATE_DIRECTIVE directive..."
            # Use awk to remove duplicate directives in the file
            for conf_file in "/home/groot/nginx/sites-available/qdrant.conf" "/home/groot/nginx/sites-available/ollama.conf"; do
                if [ -f "$conf_file" ]; then
                    awk -v directive="$DUPLICATE_DIRECTIVE" '
                    BEGIN { in_location = 0; directive_count = 0; }
                    /location/ { in_location = 1; directive_count = 0; }
                    /}/ { if (in_location) in_location = 0; }
                    $1 == directive { 
                      if (in_location) {
                        directive_count++;
                        if (directive_count > 1) next;
                      }
                    }
                    { print }' "$conf_file" > "/tmp/$(basename "$conf_file").fixed"
                    
                    mv "/tmp/$(basename "$conf_file").fixed" "$conf_file"
                    echo "Fixed duplicate directives in $(basename "$conf_file")"
                fi
            done
            
            echo "Fixed duplicate directives. Retesting configuration..."
            
            # Test again
            if ! docker exec -it core-nginx nginx -t; then
                echo "❌ Nginx configuration still has errors after fix attempt. Please check manually."
                exit 1
            else
                echo "✅ Nginx configuration test passed after fixes"
            fi
        else
            echo "❌ Could not determine which directive is duplicate. Please fix manually."
            exit 1
        fi
    elif grep -q "host not found in upstream" /tmp/nginx_error.log; then
        echo "Detected host resolution error. Attempting to fix..."
        
        # Extract the problematic host
        PROBLEMATIC_HOST=$(grep "host not found in upstream" /tmp/nginx_error.log | grep -o '"[^"]*"' | head -1 | tr -d '"')
        if [ -n "$PROBLEMATIC_HOST" ]; then
            echo "Host '$PROBLEMATIC_HOST' cannot be resolved. Updating configuration..."
            
            # Determine which file contains the problematic host
            if grep -q "$PROBLEMATIC_HOST" /home/groot/nginx/sites-available/ollama.conf; then
                CONF_FILE="/home/groot/nginx/sites-available/ollama.conf"
                
                # Replace the upstream block with a more robust version that uses IP addresses
                sed -i '/upstream ollama_backend {/,/}/c\
# Upstream definition with multiple fallback options for ollama\
upstream ollama_backend {\
    # Use IP address directly (most reliable in rootless Docker)\
    server 10.1.10.111:11434 max_fails=3 fail_timeout=5s;\
    \
    # Final fallback for maintenance page\
    server 127.0.0.1:11434 backup;\
    \
    keepalive 32;\
}' "$CONF_FILE"
                echo "Updated upstream configuration in ollama.conf"
            elif grep -q "$PROBLEMATIC_HOST" /home/groot/nginx/sites-available/qdrant.conf; then
                CONF_FILE="/home/groot/nginx/sites-available/qdrant.conf"
                
                # Replace the upstream block with a more robust version that uses IP addresses
                sed -i '/upstream qdrant_backend {/,/}/c\
# Upstream definition with multiple fallback options for qdrant\
upstream qdrant_backend {\
    # Use IP address directly (most reliable in rootless Docker)\
    server 10.1.10.111:6333 max_fails=3 fail_timeout=5s;\
    \
    # Final fallback for maintenance page\
    server 127.0.0.1:6333 backup;\
    \
    keepalive 32;\
}' "$CONF_FILE"
                echo "Updated upstream configuration in qdrant.conf"
            fi
            
            # Test again
            if ! docker exec -it core-nginx nginx -t; then
                echo "❌ Nginx configuration still has errors after fix attempt. Please check manually."
                exit 1
            else
                echo "✅ Nginx configuration test passed after fixes"
            fi
        else
            echo "❌ Could not determine which host is problematic. Please fix manually."
            exit 1
        fi
    else
        echo "❌ Unknown nginx configuration error. Please fix manually."
        exit 1
    fi
else
    echo "✅ Nginx configuration test passed"
fi

# Reload nginx configuration
echo "Reloading nginx configuration..."
docker exec -it core-nginx nginx -s reload
check_status "Reloaded nginx configuration"

# Start AI services
echo "Starting Qdrant service..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d qdrant
check_status "Started Qdrant service"

# Start Ollama service based on hardware profile
echo "Starting Ollama with $HW_PROFILE profile..."
if [ "$HW_PROFILE" = "gpu-nvidia" ]; then
    docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d ollama-gpu ollama-pull-llama-gpu
    check_status "Started Ollama with NVIDIA GPU support"
    download_container="ollama-pull-llama"
elif [ "$HW_PROFILE" = "gpu-amd" ]; then
    docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d ollama-gpu-amd ollama-pull-llama-gpu-amd
    check_status "Started Ollama with AMD GPU support"
    download_container="ollama-pull-llama"
else
    docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d ollama-cpu ollama-pull-llama-cpu
    check_status "Started Ollama with CPU support"
    download_container="ollama-pull-llama"
fi

# Wait for model download to complete with better feedback
echo "Waiting for Llama model download to complete (this may take 6-7 minutes or longer)..."
sleep 5

# Initialize counter for time tracking
start_time=$(date +%s)

# Wait for the download to complete with progress updates
while docker ps | grep -q "$download_container"; do
    # Calculate elapsed time
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    elapsed_minutes=$((elapsed_time / 60))
    elapsed_seconds=$((elapsed_time % 60))
    
    # Get download progress if possible
    if docker logs "$download_container" 2>&1 | grep -q "downloading"; then
        progress=$(docker logs "$download_container" 2>&1 | grep "downloading" | tail -1)
        echo "[$elapsed_minutes m $elapsed_seconds s] Model download in progress: $progress"
    else
        echo "[$elapsed_minutes m $elapsed_seconds s] Model download in progress..."
    fi
    
    # Check if it's been too long (e.g., over 20 minutes)
    if [ $elapsed_time -gt 1200 ]; then
        echo "⚠️ Warning: Download has been running for over 20 minutes. This is unusual."
        echo "⚠️ You may want to check for issues with: docker logs $download_container"
        echo "⚠️ Continuing to wait, but you can press Ctrl+C to interrupt if needed."
    fi
    
    sleep 30  # Check progress every 30 seconds
done

# Check if model download completed successfully
if docker ps -a | grep -q "$download_container.*Exited (0)"; then
    # Calculate total download time
    end_time=$(date +%s)
    total_time=$((end_time - start_time))
    total_minutes=$((total_time / 60))
    total_seconds=$((total_time % 60))
    
    echo "✅ Llama model download completed successfully in $total_minutes minutes and $total_seconds seconds"
    
    # Remove the download container since it's no longer needed
    echo "Removing download container..."
    docker rm $download_container
    check_status "Removed download container"
else
    echo "⚠️ Warning: Llama model download may have failed. Check logs with: docker logs $download_container"
    docker logs "$download_container" | tail -20
    
    # Ask if user wants to continue despite download issues
    echo "Do you want to continue anyway? (y/n)"
    read -r continue_response
    if [[ ! "$continue_response" =~ ^[Yy]$ ]]; then
        echo "Exiting script due to model download issues."
        exit 1
    fi
fi

# Check if services are running with more detailed status
echo "Checking AI services status..."

# Check Qdrant status
if docker ps | grep -q "qdrant.*healthy"; then
    echo "✅ Qdrant is running and healthy"
elif docker ps | grep -q "qdrant"; then
    echo "⚠️ Qdrant is running but health status unknown"
else
    echo "❌ Qdrant failed to start"
fi

# Check Ollama status
ollama_service=""
if [ "$HW_PROFILE" = "gpu-nvidia" ]; then
    ollama_service="ollama"
elif [ "$HW_PROFILE" = "gpu-amd" ]; then
    ollama_service="ollama"
else
    ollama_service="ollama"
fi

if docker ps | grep -q "$ollama_service.*healthy"; then
    echo "✅ Ollama is running and healthy"
elif docker ps | grep -q "$ollama_service"; then
    echo "⚠️ Ollama is running but health status unknown"
else
    echo "❌ Ollama failed to start"
fi

# Test Ollama API if running
if docker ps | grep -q "$ollama_service"; then
    echo "Testing Ollama API..."
    if curl -s --max-time 5 http://ollama:11434/api/version > /dev/null; then
        echo "✅ Ollama API is responding"
    else
        echo "⚠️ Ollama API is not responding yet. This is normal if it just started."
    fi
fi

echo "AI services startup completed with $HW_PROFILE profile."
echo "Qdrant is accessible at: http://qdrant:6333"
echo "Ollama is accessible at: http://ollama:11434"