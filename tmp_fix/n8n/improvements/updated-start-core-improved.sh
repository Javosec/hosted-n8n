#!/bin/bash
# Improved start-core.sh script with better error handling and proper symbolic linking
# This script ensures nginx is properly configured to use sites-enabled and sites-available

set -e

echo "Starting core infrastructure services..."

# Function to check if a command succeeded and provide feedback
check_status() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        exit 1
    fi
}

# Ensure host directories exist and are properly set up
echo "Setting up nginx configuration directories on host..."
mkdir -p /home/groot/nginx/html
check_status "Created /home/groot/nginx/html directory"

mkdir -p /home/groot/nginx/sites-enabled
check_status "Created /home/groot/nginx/sites-enabled directory"

mkdir -p /home/groot/nginx/sites-available
check_status "Created /home/groot/nginx/sites-available directory"

mkdir -p /home/groot/nginx/certs
check_status "Created /home/groot/nginx/certs directory"

# Create a simple maintenance page if it doesn't exist
if [ ! -f "/home/groot/nginx/html/maintenance.html" ]; then
  echo "Creating maintenance page..."
  cat > /home/groot/nginx/html/maintenance.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Service Maintenance</title>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 650px; margin: 0 auto; padding: 20px; }
    h1 { color: #e74c3c; }
    .container { background: #f9f9f9; border: 1px solid #ddd; padding: 20px; border-radius: 5px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Service Currently Unavailable</h1>
    <p>The requested service is currently unavailable or in maintenance mode. Please try again later.</p>
    <p>If this issue persists, please contact your system administrator.</p>
  </div>
</body>
</html>
EOF
  check_status "Created maintenance page"
fi

# Create nginx.conf template if it doesn't exist
echo "Creating nginx.conf template..."
cat > /home/groot/nginx/nginx.conf.template << 'EOF'
user nginx;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Unified logging format
    log_format unified_json escape=json '{'
        '"timestamp": "$time_iso8601",'
        '"client_ip": "$remote_addr",'
        '"request": {'
            '"method": "$request_method",'
            '"uri": "$request_uri",'
            '"protocol": "$server_protocol",'
            '"host": "$host"'
        '},'
        '"status": "$status",'
        '"bytes_sent": "$body_bytes_sent",'
        '"referrer": "$http_referer",'
        '"user_agent": "$http_user_agent",'
        '"request_time": "$request_time",'
        '"upstream_time": "$upstream_response_time",'
        '"forwarded_for": "$http_x_forwarded_for",'
        '"ssl_protocol": "$ssl_protocol",'
        '"ssl_cipher": "$ssl_cipher"'
    '}';
    
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 100M;

    # Proxy cache settings
    proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=assets_cache:10m max_size=10g inactive=60m use_temp_path=off;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    proxy_cache_valid 200 60m;
    proxy_cache_use_stale error timeout http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    proxy_cache_lock on;

    # Network security policies
    limit_req_zone $binary_remote_addr zone=frontend_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=20r/s;
    limit_req_zone $binary_remote_addr zone=mcp_memory_limit:10m rate=15r/s;

    # Frontend access restrictions
    geo $frontend_allowed {
        default 0;
        10.1.10.0/24 1;  # Local network
        127.0.0.1 1;     # Localhost
        172.18.0.0/16 1; # Docker network
        172.19.0.0/16 1; # Docker network
        172.20.0.0/16 1; # Docker network
    }

    # Backend access restrictions
    geo $backend_allowed {
        default 0;
        172.20.1.0/24 1;  # Backend network
    }

    # Rate limiting and security headers
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # Gzip Settings
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Default access and error log paths
    access_log /var/log/nginx/access.log unified_json;
    error_log /var/log/nginx/error.log notice;

    # Global SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_dhparam /etc/nginx/certs/dhparam.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self' https://api.n8n.io https://api.github.com; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://*.githubusercontent.com; font-src 'self' data:; connect-src 'self' https://api.n8n.io https://api.github.com ws: wss:" always;
    
    # Include configuration files
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
check_status "Created nginx.conf template"

# Start with a minimal configuration to ensure nginx can start
echo "Setting up minimal nginx configuration..."
if [ ! -f "/home/groot/nginx/sites-available/default.conf" ]; then
  cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/default.conf /home/groot/nginx/sites-available/default.conf
  check_status "Copied default.conf to sites-available"
fi

# Create symbolic link for default.conf if it doesn't exist
if [ ! -f "/home/groot/nginx/sites-enabled/default.conf" ]; then
  ln -sf /home/groot/nginx/sites-available/default.conf /home/groot/nginx/sites-enabled/default.conf
  check_status "Created symbolic link for default.conf in sites-enabled"
fi

# Start postgres first
echo "Starting postgres..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p core --profile core up -d postgres
check_status "Started postgres container"

# Wait for postgres to initialize
echo "Waiting for postgres to initialize..."
sleep 3

# Check if postgres is healthy
echo "Checking postgres health..."
if docker exec -it core-postgres-1 pg_isready -q; then
  echo "✅ Postgres is healthy!"
else
  echo "⚠️ Warning: Postgres may not be fully initialized yet"
fi

# Start nginx independently with minimal configuration
echo "Starting nginx with minimal configuration..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p core --profile core up -d core-nginx
check_status "Started nginx container"

# Wait for nginx to start
echo "Waiting for nginx to start..."
sleep 3

# Fix nginx configuration paths
echo "Fixing nginx configuration paths..."

# Remove directory if it exists
echo "Removing sites-enabled directory from container..."
docker exec -it core-nginx rm -rf /etc/nginx/sites-enabled
check_status "Removed sites-enabled directory from container"

docker exec -it core-nginx mkdir -p /etc/nginx/sites-available
check_status "Created sites-available directory in container"

docker exec -it core-nginx mkdir -p /etc/nginx/certs
check_status "Created /etc/nginx/certs directory in container"

# Create proper symbolic links for directories (not individual files)
echo "Creating symbolic links for directories..."
docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled /etc/nginx/sites-enabled
check_status "Created symbolic link for sites-enabled directory"

# Create symbolic links for certificate files
echo "Creating symbolic links for SSL certificates..."
docker exec -it core-nginx ln -sf /home/groot/nginx/certs/nginx.crt /etc/nginx/certs/nginx.crt
check_status "Created symbolic link for nginx.crt"

docker exec -it core-nginx ln -sf /home/groot/nginx/certs/nginx.key /etc/nginx/certs/nginx.key
check_status "Created symbolic link for nginx.key"

if [ -f "/home/groot/nginx/certs/dhparam.pem" ]; then
  docker exec -it core-nginx ln -sf /home/groot/nginx/certs/dhparam.pem /etc/nginx/certs/dhparam.pem
  check_status "Created symbolic link for dhparam.pem"
fi

# Update nginx.conf with our template
echo "Updating nginx.conf with our template..."
docker exec -it core-nginx sh -c "cat /home/groot/nginx/nginx.conf.template > /etc/nginx/nginx.conf"
check_status "Updated nginx.conf with our template"

# Verify the nginx configuration
echo "Verifying nginx configuration..."
docker exec -it core-nginx nginx -t
check_status "Nginx configuration test"

# Reload nginx to apply changes
echo "Reloading nginx to apply changes..."
docker exec -it core-nginx nginx -s reload
check_status "Nginx reload"

# Check if nginx started successfully
echo "Checking nginx status..."
if docker ps | grep -q "core-nginx" && ! docker ps | grep -q "core-nginx.*Restarting"; then
  echo "✅ Nginx started successfully!"
else
  echo "❌ Warning: Nginx may have issues starting. Check logs with: docker logs core-nginx"
  docker logs core-nginx
fi

# Display the current nginx configuration
echo "Current nginx configuration includes:"
docker exec -it core-nginx grep -n "include" /etc/nginx/nginx.conf
check_status "Displayed nginx includes"

echo "Symbolic links in nginx container:"
docker exec -it core-nginx ls -la /etc/nginx/sites-available
docker exec -it core-nginx ls -la /etc/nginx/sites-enabled
docker exec -it core-nginx ls -la /etc/nginx/certs

echo "Core infrastructure startup completed." 