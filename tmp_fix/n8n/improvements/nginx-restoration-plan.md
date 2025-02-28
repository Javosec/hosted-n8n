# Comprehensive Plan to Restore Original Nginx Configuration Approach

## Phase 1: Assessment and Preparation

### 1.1 Identify All Required Files and Directories
- [x] Confirm the structure of `/home/groot/nginx/` directory
- [x] Identify all configuration files in `/home/groot/nginx/sites-available/`
- [x] Identify all symbolic links in `/home/groot/nginx/sites-enabled/`
- [x] Identify the AI's changes in `/etc/nginx/conf.d/ai-services.conf`

### 1.2 Backup Current Configuration
- [x] Create a backup of the current Nginx configuration
  ```bash
  mkdir -p /home/groot/nginx/backup/$(date +%Y%m%d)
  cp -r /home/groot/nginx/sites-available/ /home/groot/nginx/backup/$(date +%Y%m%d)/
  cp -r /home/groot/nginx/sites-enabled/ /home/groot/nginx/backup/$(date +%Y%m%d)/
  docker exec core-nginx cp /etc/nginx/conf.d/ai-services.conf /home/groot/nginx/backup/$(date +%Y%m%d)/
  ```

### 1.3 Extract AI's Fixes
- [x] Extract the correct health endpoint for Qdrant (`/healthz` instead of `/health`)
- [x] Extract the fixed upstream server definitions (without protocol prefixes)
- [x] Document any other improvements made by the AI

## Phase 2: Fix Core Infrastructure Scripts

### 2.1 Update start-core-improved.sh
- [x] Modify the script to create proper directory structure in the container
- [x] Update the symbolic linking approach to link directories, not files
- [x] Ensure nginx.conf includes sites-enabled directory
- [x] Add proper error handling and validation

```bash
# Fix nginx configuration paths - UPDATED SECTION
echo "Fixing nginx configuration paths..."
# Create necessary directories in container
docker exec -it core-nginx mkdir -p /etc/nginx/sites-enabled
docker exec -it core-nginx mkdir -p /etc/nginx/sites-available
docker exec -it core-nginx mkdir -p /etc/nginx/certs

# Create proper symbolic links for directories
docker exec -it core-nginx ln -sf /home/groot/nginx/sites-available /etc/nginx/sites-available
docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled /etc/nginx/sites-enabled
docker exec -it core-nginx ln -sf /home/groot/nginx/certs /etc/nginx/certs

# Ensure nginx.conf includes sites-enabled
docker exec -it core-nginx bash -c "grep -q 'include /etc/nginx/sites-enabled/\*;' /etc/nginx/nginx.conf || sed -i '/include .*conf.d.*/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf"

# Reload nginx to apply changes
docker exec -it core-nginx nginx -s reload
```

### 2.2 Update nginx.conf in the Container
- [x] Create a template for nginx.conf that includes both conf.d and sites-enabled
- [x] Implement a mechanism to update nginx.conf during container startup

```bash
# Template for nginx.conf with both includes
cat > /home/groot/nginx/nginx.conf.template << 'EOF'
user nginx;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Include configuration files
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
```

## Phase 3: Update AI Service Configurations

### 3.1 Create Updated Qdrant Configuration
- [x] Create an updated qdrant.conf in sites-available with the correct health endpoint
- [x] Remove protocol prefixes from upstream server definitions
- [x] Incorporate other improvements from the AI's configuration

File location: `/home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-qdrant.conf`

### 3.2 Create Updated Ollama Configuration
- [x] Create an updated ollama.conf in sites-available
- [x] Remove protocol prefixes from upstream server definitions
- [x] Incorporate other improvements from the AI's configuration

File location: `/home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-ollama.conf`

## Phase 4: Update Service Management Scripts

### 4.1 Update start-ai-improved.sh
- [x] Modify the script to use symbolic links instead of copying files
- [x] Ensure it properly enables the AI services

File location: `/home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-start-ai-improved.sh`

### 4.2 Update down-ai.sh
- [x] Modify the script to remove symbolic links instead of deleting files
- [x] Ensure it properly disables the AI services

File location: `/home/groot/Github/hosted-n8n/tmp_fix/n8n/improvements/updated-down-ai.sh`

## Phase 5: Testing and Deployment

### 5.1 Test Core Infrastructure
- [ ] Test the updated start-core-improved.sh script
- [ ] Verify that the Nginx configuration is properly loaded
- [ ] Confirm that the symbolic links are correctly established

### 5.2 Test AI Services
- [ ] Test the updated start-ai-improved.sh script
- [ ] Verify that the AI services are properly started
- [ ] Confirm that the Nginx configurations are correctly enabled
- [ ] Test the updated down-ai.sh script
- [ ] Verify that the AI services are properly stopped
- [ ] Confirm that the Nginx configurations are correctly disabled

### 5.3 Deploy to Production
- [ ] Back up all production configurations
- [ ] Deploy the updated scripts and configurations
- [ ] Verify that everything works as expected in production

## Phase 6: Clean Up conf.d Directory

### 6.1 Remove AI's Configuration from conf.d
- [ ] After confirming the sites-enabled approach works, remove the AI's configuration from conf.d
- [ ] Ensure no duplicate configurations exist

```bash
# Remove AI's configuration from conf.d
docker exec -it core-nginx rm -f /etc/nginx/conf.d/ai-services.conf
docker exec -it core-nginx nginx -s reload
```

## Phase 7: Update Docker Compose Files

### 7.1 Review Docker Compose Volume Mounts
- [ ] Confirm that the volume mounts in docker-compose.profile.yml are correct
- [ ] Ensure the Nginx container has the necessary mounts

```yaml
# Example docker-compose volume mount section
volumes:
  - /home/groot/nginx:/home/groot/nginx:ro  # Read-only mount for security
  - /home/groot/logs/nginx:/var/log/nginx   # For logs
```

### 7.2 Add Container Initialization Script
- [ ] Create an entrypoint script for the Nginx container to set up symbolic links
- [ ] Update the Docker Compose file to use this entrypoint

```bash
# Create nginx-entrypoint.sh
cat > /home/groot/nginx/nginx-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Create necessary directories
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/certs

# Create symbolic links
ln -sf /home/groot/nginx/sites-available /etc/nginx/sites-available
ln -sf /home/groot/nginx/sites-enabled /etc/nginx/sites-enabled
ln -sf /home/groot/nginx/certs /etc/nginx/certs

# Ensure nginx.conf includes sites-enabled
grep -q 'include /etc/nginx/sites-enabled/\*;' /etc/nginx/nginx.conf || \
  sed -i '/include .*conf.d.*/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf

# Start nginx
exec nginx -g 'daemon off;'
EOF

chmod +x /home/groot/nginx/nginx-entrypoint.sh
```

## Phase 8: Documentation and Knowledge Transfer

### 8.1 Update Documentation
- [ ] Document the correct Nginx configuration structure
- [ ] Document the symbolic linking approach
- [ ] Document the health endpoints for all services

### 8.2 Create a README for Future Maintenance
- [ ] Create a README explaining the Nginx configuration approach
- [ ] Include troubleshooting steps for common issues
- [ ] Document the process for adding new services

## Implementation Sequence

1. **Backup**: Perform all backup steps first
2. **Core Infrastructure**: Update start-core-improved.sh and nginx.conf
3. **Service Configurations**: Update qdrant.conf and ollama.conf
4. **Service Management**: Update start-ai-improved.sh and down-ai.sh
5. **Docker Compose**: Update Docker Compose files and create entrypoint script
6. **Testing**: Run test scripts to validate changes
7. **Cleanup**: Remove AI's configuration from conf.d
8. **Documentation**: Update documentation and create README 