#!/bin/bash
# Improved start-mcp.sh script for deploying MCP services
# This script works in a rootless Docker environment

set -e

# Default to GPU-NVIDIA profile if not specified
HW_PROFILE="${1:-gpu-nvidia}"
echo "Starting MCP services with hardware profile: $HW_PROFILE"

# Validate hardware profile
if [[ ! "$HW_PROFILE" =~ ^(cpu|gpu-nvidia|gpu-amd)$ ]]; then
  echo "Error: Invalid hardware profile. Must be one of: cpu, gpu-nvidia, gpu-amd"
  exit 1
fi

# Check if core services are running
if ! docker ps | grep -q "core-nginx"; then
  echo "Core services aren't running. Starting core infrastructure first..."
  /home/groot/Github/hosted-n8n/tmp_fix/n8n/start-core-improved.sh
  sleep 3
fi

# Check if AI services are running (MCP depends on them)
if ! docker ps | grep -q "qdrant" || ! docker ps | grep -q "ollama"; then
  echo "AI services aren't running. Starting AI services first..."
  /home/groot/Github/hosted-n8n/tmp_fix/n8n/start-ai-improved.sh
  sleep 3
fi

# Start mcp-memory service
echo "Starting mcp-memory service..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p mcp --profile mcp --profile $HW_PROFILE up -d --no-deps mcp-memory

# Wait for mcp-memory to initialize
echo "Waiting for mcp-memory to initialize..."
sleep 5

# Start mcp-seqthinking service
echo "Starting mcp-seqthinking service..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p mcp --profile mcp --profile $HW_PROFILE up -d --no-deps mcp-seqthinking

# Wait for mcp-seqthinking to initialize
echo "Waiting for mcp-seqthinking to initialize..."
sleep 5

# Check if services started successfully
if docker ps | grep -q "mcp-memory" && docker ps | grep -q "mcp-seqthinking"; then
  echo "MCP services started successfully!"
  
  # Create mcp-memory.conf file if it doesn't exist
  if [ ! -f "/home/groot/nginx/sites-available/mcp-memory.conf" ]; then
    echo "Creating mcp-memory nginx configuration..."
    cat > /home/groot/nginx/sites-available/mcp-memory.conf << EOF
# Upstream definition with multiple fallback options for mcp-memory
upstream mcp_memory_backend {
    # Try project-namespaced container name first (most reliable for multi-project setup)
    server mcp-memory:8000 max_fails=3 fail_timeout=5s;
    
    # Fallback to hostname defined in host file via SAN entries
    server mcp-memory.mulder.local:8000 backup max_fails=3 fail_timeout=5s;

    # Fallback to IP address
    server 10.1.10.111:8000 backup max_fails=3 fail_timeout=5s;
    
    # Final fallback for maintenance page
    server 127.0.0.1:8000 backup;
    
    keepalive 32;
}

# MCP Memory Server Block
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name mcp-memory.mulder.local;

    # Service unavailable page - more robust implementation
    error_page 502 503 504 = @maintenance;
    
    # Maintenance location that doesn't depend on any external service
    location @maintenance {
        root /home/groot/nginx/html;
        try_files /maintenance.html /50x.html =502;
        internal;
    }

    ssl_certificate /home/groot/nginx/certs/nginx.crt;
    ssl_certificate_key /home/groot/nginx/certs/nginx.key;

    access_log /var/log/nginx/mcp-memory-access.log;
    error_log /var/log/nginx/mcp-memory-error.log notice;

    # Rate limiting
    limit_req zone=api_limit burst=10 nodelay;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Health check that always succeeds regardless of upstream availability
    location /health {
        access_log off;
        return 200 'healthy\n';
    }

    location / {
        # Enable error interception
        proxy_intercept_errors on;

        # Proxy settings
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 5;
        proxy_read_timeout 60;
        proxy_send_timeout 60;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Security
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;

        proxy_pass http://mcp_memory_backend;
        
        # Extended timeouts for long-running operations
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 300s;
    }
}
EOF
  fi
  
  # Create mcp-seqthinking.conf file if it doesn't exist
  if [ ! -f "/home/groot/nginx/sites-available/mcp-seqthinking.conf" ]; then
    echo "Creating mcp-seqthinking nginx configuration..."
    cat > /home/groot/nginx/sites-available/mcp-seqthinking.conf << EOF
# Upstream definition with multiple fallback options for mcp-seqthinking
upstream mcp_seqthinking_backend {
    # Try project-namespaced container name first (most reliable for multi-project setup)
    server mcp-seqthinking:8001 max_fails=3 fail_timeout=5s;
    
    # Fallback to hostname defined in host file via SAN entries
    server mcp-seqthinking.mulder.local:8001 backup max_fails=3 fail_timeout=5s;

    # Fallback to IP address
    server 10.1.10.111:8001 backup max_fails=3 fail_timeout=5s;
    
    # Final fallback for maintenance page
    server 127.0.0.1:8001 backup;
    
    keepalive 32;
}

# MCP Seqthinking Server Block
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name mcp-seqthinking.mulder.local;

    # Service unavailable page - more robust implementation
    error_page 502 503 504 = @maintenance;
    
    # Maintenance location that doesn't depend on any external service
    location @maintenance {
        root /home/groot/nginx/html;
        try_files /maintenance.html /50x.html =502;
        internal;
    }

    ssl_certificate /home/groot/nginx/certs/nginx.crt;
    ssl_certificate_key /home/groot/nginx/certs/nginx.key;

    access_log /var/log/nginx/mcp-seqthinking-access.log;
    error_log /var/log/nginx/mcp-seqthinking-error.log notice;

    # Rate limiting
    limit_req zone=api_limit burst=10 nodelay;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Health check that always succeeds regardless of upstream availability
    location /health {
        access_log off;
        return 200 'healthy\n';
    }

    location / {
        # Enable error interception
        proxy_intercept_errors on;

        # Proxy settings
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 5;
        proxy_read_timeout 60;
        proxy_send_timeout 60;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Security
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;

        proxy_pass http://mcp_seqthinking_backend;
        
        # Extended timeouts for long-running operations
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 300s;
    }
}
EOF
  fi
  
  # Create symlinks for MCP configurations
  echo "Creating symlinks for MCP nginx configurations..."
  ln -sf /home/groot/nginx/sites-available/mcp-memory.conf /home/groot/nginx/sites-enabled/mcp-memory.conf
  ln -sf /home/groot/nginx/sites-available/mcp-seqthinking.conf /home/groot/nginx/sites-enabled/mcp-seqthinking.conf
  
  # Fix nginx configuration paths
  echo "Fixing nginx configuration paths..."
  docker exec -it core-nginx mkdir -p /etc/nginx/sites-enabled
  docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled/* /etc/nginx/sites-enabled/
  
  # Restart nginx container
  echo "Restarting nginx to apply new configuration..."
  docker restart core-nginx
  
  echo "MCP services deployment completed successfully."
else
  echo "Warning: Some MCP services may have issues starting. Check logs with: docker logs mcp-memory or docker logs mcp-seqthinking"
  echo "Not enabling nginx configuration for MCP services since they are not running properly."
fi 