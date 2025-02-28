#!/bin/bash
# Improved start-n8n.sh script with better error handling and proper symbolic linking
# This script ensures n8n is properly configured and cleans up the import container

set -e

echo "Starting n8n services..."

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

# Check if core services are running
if ! docker ps | grep -q "core-postgres-1"; then
  echo "Core services aren't running. Starting core infrastructure first..."
  /home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-start-core-improved.sh
  check_status "Started core infrastructure"
  sleep 3
fi

# Prepare n8n nginx configuration
echo "Preparing n8n nginx configuration..."
if [ ! -f "/home/groot/nginx/sites-available/n8n.conf" ]; then
  echo "Creating n8n.conf in sites-available..."
  cat > /home/groot/nginx/sites-available/n8n.conf << 'EOF'
# Upstream definition with direct container references
upstream n8n_backend {
    # Primary server - direct container reference
    server n8n:5678 max_fails=3 fail_timeout=5s;
    
    # Fallback to IP address as backup
    server 10.1.10.111:5678 backup max_fails=3 fail_timeout=5s;
    
    # Final fallbacks for maintenance page
    server 127.0.0.1:5678 backup;
    server localhost:5678 backup;
    
    keepalive 32;
}

# N8N Server Block
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name n8n.mulder.local;

    # Service unavailable page - more robust implementation
    error_page 502 503 504 = @maintenance;
    
    # Maintenance location that doesn't depend on any external service
    location @maintenance {
        root /home/groot/nginx/html;
        try_files /maintenance.html /50x.html =502;
        internal;
    }

    # SSL configuration - using container paths
    ssl_certificate /etc/nginx/certs/nginx.crt;
    ssl_certificate_key /etc/nginx/certs/nginx.key;

    # Access and error logs
    access_log /var/log/nginx/n8n-access.log unified_json;
    error_log /var/log/nginx/n8n-error.log notice;

    # Access control
    if ($frontend_allowed = 0) {
        return 403;
    }

    # Rate limiting
    limit_req zone=api_limit burst=10 nodelay;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self' https://api.n8n.io https://api.github.com; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://*.githubusercontent.com; font-src 'self' data:; connect-src 'self' https://api.n8n.io https://api.github.com ws: wss:" always;

    # Health check that always succeeds regardless of upstream availability
    location /health {
        access_log off;
        return 200 'healthy\n';
    }

    # Assets location
    location /assets/ {
        # Enable error interception
        proxy_intercept_errors on;
        
        proxy_pass http://n8n_backend;
        proxy_http_version 1.1;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5;
        proxy_read_timeout 60;
        proxy_send_timeout 60;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Enable caching for assets
        proxy_cache_use_stale error timeout http_500 http_502 http_503 http_504;
        proxy_cache_valid 200 60m;
        expires 1h;
        add_header Cache-Control "public, no-transform";
    }

    # WebSocket support for push notifications
    location /rest/push {
        # Enable error interception
        proxy_intercept_errors on;
        
        proxy_pass http://n8n_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5;
        proxy_read_timeout 60;
        proxy_send_timeout 60;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Increase timeouts for long-running WebSocket connections
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location / {
        # Enable error interception
        proxy_intercept_errors on;

        # Proxy settings
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5;
        proxy_read_timeout 60;
        proxy_send_timeout 60;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Security
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
        proxy_hide_header X-AspNet-Version;
        proxy_hide_header X-AspNetMvc-Version;

        proxy_pass http://n8n_backend;
        
        # Specific settings for n8n
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        
        # Extended timeouts for long-running workflows
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_connect_timeout 600s;
    }
}
EOF
  check_status "Created n8n.conf in sites-available"
else
  echo "✅ n8n.conf already exists in sites-available"
  
  # Check if the existing n8n.conf uses host paths for SSL certificates
  if grep -q "/home/groot/nginx/certs/nginx.crt" /home/groot/nginx/sites-available/n8n.conf; then
    echo "Updating SSL certificate paths in existing n8n.conf..."
    # Use sed to replace the host paths with container paths
    sed -i 's|ssl_certificate /home/groot/nginx/certs/nginx.crt;|ssl_certificate /etc/nginx/certs/nginx.crt;|g' /home/groot/nginx/sites-available/n8n.conf
    sed -i 's|ssl_certificate_key /home/groot/nginx/certs/nginx.key;|ssl_certificate_key /etc/nginx/certs/nginx.key;|g' /home/groot/nginx/sites-available/n8n.conf
    check_status "Updated SSL certificate paths in n8n.conf"
    
    # Add frontend_allowed check if it doesn't exist
    if ! grep -q "frontend_allowed" /home/groot/nginx/sites-available/n8n.conf; then
      echo "Adding access control to n8n.conf..."
      sed -i '/error_log .*notice;/a \
    # Access control\
    if ($frontend_allowed = 0) {\
        return 403;\
    }' /home/groot/nginx/sites-available/n8n.conf
      check_status "Added access control to n8n.conf"
    fi
  fi
  
  # Check if the existing n8n.conf has invalid URL format in upstream block
  if grep -q "https://" /home/groot/nginx/sites-available/n8n.conf || grep -q "http://" /home/groot/nginx/sites-available/n8n.conf; then
    echo "Fixing invalid URL format in upstream block..."
    # Remove http:// and https:// from server directives
    sed -i 's|server https://|server |g' /home/groot/nginx/sites-available/n8n.conf
    sed -i 's|server http://|server |g' /home/groot/nginx/sites-available/n8n.conf
    check_status "Fixed invalid URL format in upstream block"
  fi
  
  # Simplify the upstream configuration to avoid hostname resolution issues
  if grep -q "n8n.mulder.local:5678" /home/groot/nginx/sites-available/n8n.conf; then
    echo "Simplifying upstream configuration to avoid hostname resolution issues..."
    # Remove the line with n8n.mulder.local
    sed -i '/server n8n.mulder.local:5678/d' /home/groot/nginx/sites-available/n8n.conf
    check_status "Simplified upstream configuration"
  fi
  
  # Check for duplicate proxy_read_timeout directives in the WebSocket location block
  if grep -A15 "location /rest/push" /home/groot/nginx/sites-available/n8n.conf | grep -c "proxy_read_timeout" | grep -q "2"; then
    echo "Fixing duplicate proxy_read_timeout directives in WebSocket location block..."
    # Use awk to remove the first occurrence of proxy_read_timeout in the /rest/push location block
    awk '/location \/rest\/push/,/}/ { if ($1 == "proxy_read_timeout" && !seen) { seen=1; next; } } { print }' /home/groot/nginx/sites-available/n8n.conf > /tmp/n8n.conf.fixed
    mv /tmp/n8n.conf.fixed /home/groot/nginx/sites-available/n8n.conf
    check_status "Fixed duplicate proxy_read_timeout directives"
  fi
  
  # Check for duplicate proxy_send_timeout directives in the WebSocket location block
  if grep -A15 "location /rest/push" /home/groot/nginx/sites-available/n8n.conf | grep -c "proxy_send_timeout" | grep -q "2"; then
    echo "Fixing duplicate proxy_send_timeout directives in WebSocket location block..."
    # Use awk to remove the first occurrence of proxy_send_timeout in the /rest/push location block
    awk '/location \/rest\/push/,/}/ { if ($1 == "proxy_send_timeout" && !seen) { seen=1; next; } } { print }' /home/groot/nginx/sites-available/n8n.conf > /tmp/n8n.conf.fixed
    mv /tmp/n8n.conf.fixed /home/groot/nginx/sites-available/n8n.conf
    check_status "Fixed duplicate proxy_send_timeout directives"
  fi
fi

# Start n8n services with the specified hardware profile
echo "Starting n8n services with $HW_PROFILE profile..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p n8n --profile n8n --profile $HW_PROFILE up -d n8n n8n-import
check_status "Started n8n services"

# Wait for n8n-import to complete
echo "Waiting for n8n-import to complete..."
while docker ps | grep -q "n8n-import"; do
  echo "n8n-import is still running..."
  sleep 5
done

# Check if n8n-import completed successfully
if docker ps -a | grep -q "n8n-import.*Exited (0)"; then
  echo "✅ n8n-import completed successfully"
  
  # Remove the n8n-import container since it's no longer needed
  echo "Removing n8n-import container..."
  docker rm n8n-import
  check_status "Removed n8n-import container"
else
  echo "⚠️ Warning: n8n-import may have failed. Check logs with: docker logs n8n-import"
  docker logs n8n-import
fi

# Wait for n8n to become healthy
echo "Waiting for n8n to become healthy..."
max_attempts=12
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if docker ps | grep -q "n8n.*healthy"; then
    echo "✅ n8n is healthy!"
    break
  fi
  
  if docker ps | grep -q "n8n.*unhealthy"; then
    echo "⚠️ n8n is reporting as unhealthy. Waiting for it to recover..."
  else
    echo "⏳ Waiting for n8n health check to pass..."
  fi
  
  attempt=$((attempt+1))
  if [ $attempt -eq $max_attempts ]; then
    echo "⚠️ Reached maximum wait time for n8n to become healthy."
    echo "⚠️ Continuing anyway, but n8n may not be fully operational yet."
    break
  fi
  
  sleep 10
done

# Enable n8n nginx configuration
echo "Enabling n8n nginx configuration..."
if [ ! -f "/home/groot/nginx/sites-enabled/n8n.conf" ]; then
  ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf
  check_status "Created symbolic link for n8n.conf in sites-enabled"
fi

# Reload nginx configuration in the container
echo "Reloading nginx configuration..."
if docker ps | grep -q "core-nginx"; then
  # Update the symbolic link in the container if it doesn't exist or points to a different file
  echo "Checking n8n.conf symbolic link in container..."
  if ! docker exec -it core-nginx test -L /etc/nginx/sites-enabled/n8n.conf; then
    echo "Creating symbolic link for n8n.conf in container..."
    docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled/n8n.conf /etc/nginx/sites-enabled/n8n.conf
    check_status "Created symbolic link for n8n.conf in container"
  else
    echo "✅ Symbolic link for n8n.conf already exists in container"
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
  
  if [ -f "/home/groot/nginx/certs/dhparam.pem" ] && ! docker exec -it core-nginx test -L /etc/nginx/certs/dhparam.pem; then
    docker exec -it core-nginx ln -sf /home/groot/nginx/certs/dhparam.pem /etc/nginx/certs/dhparam.pem
    check_status "Created symbolic link for dhparam.pem"
  fi
  
  # Test and reload nginx
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
        { print }' /home/groot/nginx/sites-available/n8n.conf > /tmp/n8n.conf.fixed
        
        mv /tmp/n8n.conf.fixed /home/groot/nginx/sites-available/n8n.conf
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
    else
      echo "❌ Unknown nginx configuration error. Please fix manually."
      exit 1
    fi
  else
    echo "✅ Nginx configuration test passed"
  fi
  
  echo "Reloading nginx configuration..."
  docker exec -it core-nginx nginx -s reload
  check_status "Reloaded nginx configuration"
else
  echo "❌ Error: core-nginx container is not running. Cannot reload nginx configuration."
  exit 1
fi

# Display n8n status
echo "N8N deployment status:"
docker ps | grep "n8n"

echo "N8N is now accessible at: https://n8n.mulder.local"
echo "N8N deployment completed successfully." 