# Temporary Fixes for N8N and Core Infrastructure

This directory contains improved scripts and configurations for the hosted-n8n environment. These scripts address various issues with the original deployment and provide a more robust approach to managing the infrastructure.

## Directory Structure

```
tmp_fix/n8n/
├── README.md                 # This file
├── start-core-improved.sh    # Improved script for starting core infrastructure
├── start-n8n-improved.sh     # Improved script for starting N8N services
├── start-ai-improved.sh      # Improved script for starting AI services
├── minimal.conf              # Minimal Nginx configuration for initial startup
├── n8n.conf                  # Nginx configuration for N8N
├── qdrant.conf               # Nginx configuration for Qdrant
├── ollama.conf               # Nginx configuration for Ollama
└── tests/                    # Test scripts
    ├── test-nginx-config.sh  # Script to test Nginx configuration
    └── test-ai-services.sh   # Script to test AI services
```

## Scripts

### start-core-improved.sh

This script starts the core infrastructure services (Nginx and PostgreSQL) with improved error handling and health checks.

**Key Features:**
- Creates necessary directories for Nginx configuration
- Sets up a minimal Nginx configuration to ensure it starts without dependencies
- Fixes the Nginx configuration path issue by creating symbolic links
- Starts PostgreSQL and verifies it's healthy
- Starts Nginx and verifies it's healthy

**Usage:**
```bash
./start-core-improved.sh
```

### start-n8n-improved.sh

This script starts the N8N services after ensuring the core infrastructure is running.

**Key Features:**
- Checks if core infrastructure is running
- Starts N8N services with the appropriate profile
- Configures Nginx for N8N access
- Verifies N8N is healthy

**Usage:**
```bash
./start-n8n-improved.sh
```

### start-ai-improved.sh

This script starts the AI services (Qdrant and Ollama) after ensuring the core infrastructure is running.

**Key Features:**
- Checks if core infrastructure is running
- Starts Qdrant and Ollama services with the appropriate profile
- Configures Nginx for Qdrant and Ollama access
- Verifies services are healthy

**Usage:**
```bash
./start-ai-improved.sh
```

## Nginx Configurations

### minimal.conf

A minimal Nginx configuration that allows Nginx to start without dependencies on other services. This is used during the initial startup to ensure Nginx can run independently.

### n8n.conf

Nginx configuration for the N8N service with multiple fallback mechanisms:
- Tries project-namespaced container name first
- Falls back to hostname defined in host file
- Falls back to IP address
- Final fallback to maintenance page

### qdrant.conf

Nginx configuration for the Qdrant service with similar fallback mechanisms as n8n.conf.

### ollama.conf

Nginx configuration for the Ollama service with similar fallback mechanisms as n8n.conf.

## Test Scripts

### test-nginx-config.sh

This script tests the Nginx configuration to ensure it's valid and properly set up.

**Key Features:**
- Checks if Nginx is running
- Verifies the Nginx configuration is valid
- Checks if service configurations are loaded
- Tests path configurations

**Usage:**
```bash
./tests/test-nginx-config.sh
```

### test-ai-services.sh

This script tests the AI services (Qdrant and Ollama) to ensure they're running and accessible.

**Key Features:**
- Checks if services are running
- Tests direct API access to services
- Tests Nginx proxy access to services
- Performs detailed API tests

**Usage:**
```bash
./tests/test-ai-services.sh
```

## Common Issues and Solutions

### Nginx Restart Loop

**Issue:** Nginx container repeatedly restarts due to dependencies on unavailable services.

**Solution:**
1. Use the minimal.conf to allow Nginx to start without dependencies
2. Fix the path issue by creating symbolic links from `/etc/nginx/sites-enabled/` to `/home/groot/nginx/sites-enabled/*`
3. Implement proper fallback mechanisms in upstream directives

### Rootless Docker Environment Issues

**Issue:** Script commands using sudo may cause permission problems in rootless Docker.

**Solution:**
1. Remove sudo commands from scripts
2. Modify scripts to work with appropriate permissions
3. Implement alternative approaches for configuration management

### Service Communication Across Projects

**Issue:** Services in different project namespaces may have trouble communicating.

**Solution:**
1. Implement multiple fallback mechanisms in upstream directives
2. Add support for both project-prefixed and service names
3. Leverage SAN entries in host file for consistent hostname resolution

## Migration Status

These scripts and configurations are part of the ongoing migration to a profile-based Docker Compose setup. See the migration plan document at `docs/project/03-plans/02-migration/01-profile-compose-migration.md` for more details on the overall migration process.

## Usage Recommendations

1. Start with the core infrastructure:
   ```bash
   ./start-core-improved.sh
   ```

2. Then start the N8N services:
   ```bash
   ./start-n8n-improved.sh
   ```

3. Finally, start the AI services:
   ```bash
   ./start-ai-improved.sh
   ```

4. Verify everything is working:
   ```bash
   ./tests/test-nginx-config.sh
   ./tests/test-ai-services.sh
   ```

## Future Improvements

1. Integrate these improvements into the main scripts in the `scripts/` directory
2. Add support for MCP services
3. Add support for utility services
4. Implement more comprehensive health checks
5. Add automated rollback mechanisms 