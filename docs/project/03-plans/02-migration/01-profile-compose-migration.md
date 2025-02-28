# Profile-Based Docker Compose Migration Plan

**Version:** 1.4  
**Date:** Feb 27, 2025  
**Author:** System Administrator  
**Status:** In Progress - Phase 1 Completed, Phase 2 Starting  

## Table of Contents
1. [Introduction](#introduction)
2. [Current State](#current-state)
3. [Folder Structure](#folder-structure)
4. [Architectural Considerations](#architectural-considerations)
5. [Network Configuration](#network-configuration)
6. [Migration Goals](#migration-goals)
7. [Implementation Timeline](#implementation-timeline)
8. [Migration Plan](#migration-plan)
   - [Phase 1: Initial Deployment Testing](#phase-1-initial-deployment-testing)
   - [Phase a: Resolve Current Issues](#phase-a-resolve-current-issues-new)
   - [Phase 2: Cross-Service Communication Verification](#phase-2-cross-service-communication-verification)
   - [Phase 3: GPU Resource Verification](#phase-3-gpu-resource-verification)
   - [Phase 4: Full System Test](#phase-4-full-system-test)
   - [Phase 5: Contingency Plan](#phase-5-contingency-plan)
   - [Phase 6: Implementation](#phase-6-implementation)
9. [Current Issues and Resolutions](#current-issues-and-resolutions)
10. [Go/No-Go Decision Points](#gono-go-decision-points)
11. [Risk Assessment](#risk-assessment)
12. [Post-Migration Tasks](#post-migration-tasks)

## Introduction

This document outlines the precise steps for migrating the hosted-n8n environment from the current Docker Compose configuration to a profile-based approach with project names. The profile-based approach provides better organization, enhanced UI visibility in Docker, and more granular control over service groups.

## Current State

- The existing infrastructure uses a single docker-compose.yml file with hardware profiles (cpu, gpu-nvidia, gpu-amd)
- Services are currently started with `docker compose --profile gpu-nvidia up -d`
- All services appear in a single Docker project namespace
- We have created a new profile-based configuration (docker-compose.profile.yml)
- Helper scripts have been developed in the scripts/ directory
- A rollback mechanism has been implemented
- **New Observation**: Docker is running in rootless mode - containers don't have root access
- **New Finding**: Nginx configuration path issue has been resolved by creating symbolic links from `/etc/nginx/sites-enabled/` to `/home/groot/nginx/sites-enabled/*`
- **Historical Context**: Nginx proxy was originally part of the n8n deployment but has been separated to be a core infrastructure service
- **Current Status**: Core services (nginx, postgres) and n8n are running successfully with no errors

## Folder Structure

### Current File Structure
```
/hosted-n8n/
├── docker-compose.yml               				 # Original docker-compose file with hardware profiles
├── docker-compose.yml.bak           				 # Backup of the original file
├── docker-compose.profile.yml       				 # New profile-based configuration
├── scripts/                         				 # Helper scripts directory
│   ├── README.md                    				 # Documentation for scripts
│   ├── down-all.sh                  				 # Script to stop all containers
│   ├── rollback.sh                  				 # Script to revert to original configuration
│   ├── start-ai.sh                  				 # Script to start AI services
│   ├── start-all.sh                 				 # Script to start all services
│   ├── start-core.sh                				 # Script to start core infrastructure
│   ├── start-mcp.sh                 				 # Script to start MCP services
│   ├── start-n8n.sh                 				 # Script to start N8N services
│   └── start-utility.sh             				 # Script to start utility services
├── tmp_fix/                         				 # Temporary fixes directory
│   └── n8n/                         				 # N8N fixes
│       ├── start-core-improved.sh   				 # Improved core startup script
│       ├── start-n8n-improved.sh    				 # Improved n8n startup script
│       ├── start-ai-improved.sh     				 # Improved AI services startup script
│       ├── minimal.conf             				 # Minimal nginx configuration
│       ├── n8n.conf                 				 # N8N nginx configuration
│       ├── qdrant.conf              				 # Qdrant nginx configuration
│       ├── ollama.conf              				 # Ollama nginx configuration
│       └── tests/                   				 # Test scripts
│           └── test-nginx-config.sh 				 # Nginx configuration test script
├── docs/                            				 # Documentation directory
│   ├── profile_based_migration_plan.md 			 # Original migration plan
│   └── project/                     				 # Project documentation
│       └── 03-plans/                				 # Plans documentation
│           └── 02-migration/        				 # Migration plans
│               └── 01-profile-compose-migration.md  # This document
├── mcp/                             				 # MCP service directory
├── n8n/                             				 # N8N service directory
│   └── backup/                      				 # N8N backup directory
├── crawl4ai/                        				 # Crawl4AI service directory
├── shared/                          				 # Shared data directory
└── .env                             				 # Environment variables
```

### Expected File Structure After Migration
```
/hosted-n8n/
├── docker-compose.yml               	 			 # Profile-based configuration (renamed from docker-compose.profile.yml)
├── docker-compose.yml.bak           	 			 # Backup of the original file
├── scripts/                         	 			 # Helper scripts directory
│   ├── README.md                    	 			 # Documentation for scripts
│   ├── down-all.sh                  	 			 # Script to stop all containers
│   ├── rollback.sh                  	 			 # Script to revert to original configuration
│   ├── start-ai.sh                  	 			 # Script to start AI services
│   ├── start-all.sh                 	 			 # Script to start all services
│   ├── start-core.sh                	 			 # Script to start core infrastructure
│   ├── start-mcp.sh                 	 			 # Script to start MCP services
│   ├── start-n8n.sh                 	 			 # Script to start N8N services
│   └── start-utility.sh             	 			 # Script to start utility services
├── docs/                            	 			 # Documentation directory
│   ├── profile_based_migration_plan.md  			 # Original migration plan
│   └── project/                     	 			 # Project documentation
│       └── 03-plans/                	 			 # Plans documentation
│           └── 02-migration/        	 			 # Migration plans
│               └── 01-profile-compose-migration.md  # This document
├── mcp/                             	 			 # MCP service directory
├── n8n/                             	 			 # N8N service directory
│   └── backup/                      	 			 # N8N backup directory
├── crawl4ai/                        	 			 # Crawl4AI service directory
├── shared/                          	 			 # Shared data directory
└── .env                             	 			 # Environment variables
```

### Docker Projects Structure
In addition to the file system changes, the Docker project structure will change:

**Current Docker Project Structure:**
- Single project namespace (default or unnamed)
- All containers visible together in Docker UI
- Containers differentiated only by name

**Expected Docker Project Structure After Migration:**
- Multiple project namespaces based on service function:
  - `core` - Core infrastructure services (nginx, postgres)
  - `n8n` - N8N workflow services
  - `mcp` - MCP services
  - `ai` - AI/ML services (ollama, qdrant)
  - `utility` - Utility services (crawl4ai)
- Each project appears separately in Docker UI
- Clearer visual separation of service components
- Ability to start/stop entire functional groups

## Architectural Considerations

Before proceeding with the migration, it's important to understand the architectural principles that should guide our implementation:

### Core Infrastructure Independence

1. **Nginx as Gateway**:
   - Nginx serves as the primary reverse proxy/gateway for the entire system
   - It should start independently of application services
   - Located at `/home/groot/nginx/` outside the project directory
   - Used to access container UIs via web browser from secured network
   - **Critical Requirement**: Nginx must be 100% agnostic to other containers and operate independently
   - **Historical Context**: Originally deployed as part of n8n, now separated as a core function with no dependencies
   - **Current Challenge**: Legacy configuration elements still reflect the previous tight integration with application services
   - **Resolution**: Implemented a minimal.conf that allows nginx to start without dependencies and fixed the path issue by creating symbolic links from `/etc/nginx/sites-enabled/` to `/home/groot/nginx/sites-enabled/*`

2. **Database Independence**:
   - Postgres database is a foundational service
   - Should not depend on application services

3. **Service Layering**:
   - Core infrastructure (nginx, postgres) forms the foundation
   - Application services (n8n, mcp, ai, utility) build on top of core
   - Each layer should be able to start independently

### Dependency Management

1. **Avoiding Circular Dependencies**:
   - Core services should not depend on application services
   - Application services may depend on core services
   - Services within the same layer may have interdependencies

2. **Health Checks**:
   - Health checks should be implemented at the service level
   - Nginx should handle routing based on service availability
   - Docker health checks should be used for container orchestration

### Profile Organization

1. **Functional Profiles**:
   - Services are grouped by function (core, n8n, mcp, ai, utility)
   - Each profile represents a logical group of services

2. **Hardware Profiles**:
   - Hardware profiles (cpu, gpu-nvidia, gpu-amd) are orthogonal to functional profiles
   - Services may belong to multiple profiles

3. **Rootless Docker Considerations**:
   - The system is running in rootless Docker mode
   - This impacts permission management and container access
   - Helper scripts must account for rootless constraints
   - Sudo commands in scripts may cause permission issues

## Network Configuration

The system operates across three distinct network types that must be considered for proper service communication. See [Network Configuration Summary](../../01-analysis/00-tracking/00-initial/00-review/01-pcm-network.md) for detailed documentation.

### Network Types

1. **Secure Private Network (External)**:
   - Server and clients on same secure network (10.1.10.0/24)
   - Server IP: 10.1.10.111
   - Primary access method for clients

2. **Local Server Network**:
   - Server's internal network interfaces
   - Host file contains SAN entries for service discovery

3. **Docker Networks**:
   - Primary shared network: `hosted-n8n_lab` (external)
   - Project-specific networks: `core_default`, `n8n_default`, etc.
   - Cross-project communication relies on the shared network

### SAN Configuration Impact

The server's host file contains Subject Alternative Name (SAN) entries that are critical for cross-service communication:

```
# Service Cross-Communication 
10.1.10.111 postgres
10.1.10.111 n8n
10.1.10.111 mcp-memory
10.1.10.111 mcp-seqthinking
10.1.10.111 qdrant
10.1.10.111 ollama
```

These entries help bridge the gap between different project namespaces by providing consistent hostname resolution.

### Network-Aware Nginx Configuration

To make nginx truly agnostic to other services, its configuration must leverage both project-aware hostnames and SAN entries in the host file:

```nginx
# Example improved upstream configuration
upstream n8n_backend {
    # Try project-namespaced name first
    server n8n:5678 max_fails=3 fail_timeout=5s;
    # Fallback to hostname defined in host file
    server n8n.mulder.local:5678 backup max_fails=3 fail_timeout=5s;
    # Fallback to IP address
    server 10.1.10.111:5678 backup max_fails=3 fail_timeout=5s;
    # Final fallback for maintenance page
    server 127.0.0.1:5678 backup;
}
```

This approach provides multiple fallback mechanisms for service resolution.

## Migration Goals

1. Implement functional service grouping using Docker Compose profiles
2. Organize services into separate project namespaces for better Docker UI visibility
3. Maintain hardware profile capabilities (cpu, gpu-nvidia, gpu-amd)
4. Ensure all services function properly in the new configuration
5. Provide simple helper scripts for common operations
6. Document the new approach thoroughly
7. **New Goal**: Make nginx completely independent of application services
8. **New Goal**: Address permission management in rootless Docker environment
9. **New Goal**: Ensure proper network connectivity across three network types with correct SAN configuration
10. **New Goal**: Implement robust fallback mechanisms for service unavailability

## Implementation Timeline

| Phase | Description | Estimated Time | Status |
|-------|-------------|----------------|--------|
| Preparation | File creation and script development | Completed | ✅ |
| Testing | Phased testing of all components | 1-2 days | 🔄 In Progress |
| Implementation | Final implementation | 0.5 day | 📅 Pending |
| Documentation | Update documentation | 0.5 day | 📅 Pending |
| **Nginx Fixes** | Fix nginx configuration issues | 1 day | ✅ |
| **Total** | | **3-4 days** | 🔄 In Progress |

## Migration Plan

### Phase 1: Initial Deployment Testing

#### 1.1. Update Docker Compose Configuration

```bash
# Remove inappropriate dependencies from nginx
# Ensure core services can start independently
```
**Status: COMPLETED** - Dependencies removed from nginx service in docker-compose.profile.yml


#### 1.2. Deploy Core Infrastructure
```bash
# Start postgres database
docker compose -f docker-compose.profile.yml -p core --profile core up -d postgres

# Start nginx independently
docker compose -f docker-compose.profile.yml -p core --profile core up -d nginx
```
**Status: COMPLETED** - Core infrastructure deployment successful with improved scripts

#### 1.3. Verification Checklist for Core Infrastructure
- [x] Confirm postgres is running: `docker ps | grep postgres`
- [x] Verify postgres is healthy: `docker exec -it core-postgres-1 pg_isready`
- [x] Confirm nginx is running stably: `docker ps | grep nginx`
- [x] Verify nginx configuration: `docker exec -it nginx-proxy nginx -t`
- [x] Check nginx can serve basic responses

#### 1.4. Deploy N8N Services
```bash
docker compose -f docker-compose.profile.yml -p n8n --profile n8n --profile gpu-nvidia up -d
```
**Status: COMPLETED** - N8N services started and healthy

#### 1.5. Verification Checklist for N8N Services
- [x] Confirm n8n containers are running: `docker ps | grep n8n`
- [x] Verify n8n can connect to postgres
- [x] Check n8n is accessible through nginx: `curl -I -H "Host: n8n.mulder.local" http://localhost:8080/`

#### 1.6. Deploy MCP Services
```bash
docker compose -f docker-compose.profile.yml -p mcp --profile mcp --profile gpu-nvidia up -d
```
**Status: NOT STARTED** - Pending completion of AI services deployment

#### 1.7. Verification Checklist for MCP Services
- [ ] Confirm containers are running: `docker ps | grep mcp`
- [ ] Check container logs for errors
- [ ] Verify services are accessible through their endpoints

#### 1.8. Deploy AI Services
```bash
docker compose -f docker-compose.profile.yml -p ai --profile ai --profile gpu-nvidia up -d
```
**Status: COMPLETED** - AI services (Qdrant and Ollama) deployed successfully

#### 1.9. Verification Checklist for AI Services
- [x] Confirm containers are running: `docker ps | grep -E 'qdrant|ollama'`
- [x] Check ollama is functioning: `curl -H "Host: ollama.mulder.local" http://localhost:8080/api/version`
- [x] Verify qdrant is accessible: `curl -H "Host: qdrant.mulder.local" http://localhost:8080/healthz`

#### 1.10. Deploy Utility Services
```bash
docker compose -f docker-compose.profile.yml -p utility --profile utility --profile gpu-nvidia up -d
```
**Status: NOT STARTED** - Pending completion of AI services deployment

#### 1.11. Verification Checklist for Utility Services
- [ ] Confirm containers are running: `docker ps | grep utility`
- [ ] Check crawl4ai service logs for errors

### Phase a: Resolve Current Issues (NEW)

Before proceeding with the remaining phases, we needed to address the current issues discovered during initial testing:

#### a.1. Fix Nginx Restart Loop
```bash
# Fix nginx configuration to make it truly independent
# Steps:
# 1. Examine current nginx logs to identify the precise error
docker logs core-nginx-1
# 2. Modify nginx configuration files to handle missing services gracefully
```
**Status: COMPLETED** - Implemented default.conf and fixed path issues

#### a.2. Update Nginx Configuration Templates
```bash
# Create improved templates for service-specific configurations
# Example for n8n.conf:
cat > /home/groot/nginx/sites-available/n8n.conf <<EOF
upstream n8n_backend {
    # Try project-namespaced name first
    server n8n:5678 max_fails=3 fail_timeout=5s;
    # Fallback to hostname defined in host file
    server n8n.mulder.local:5678 backup max_fails=3 fail_timeout=5s;
    # Fallback to IP address
    server 10.1.10.111:5678 backup max_fails=3 fail_timeout=5s;
    # Final fallback for maintenance page
    server 127.0.0.1:5678 backup;
}

server {
    listen 443 ssl;
    server_name n8n.mulder.local;
    
    # Enable error interception
    proxy_intercept_errors on;
    
    # Handle service unavailable with custom page
    error_page 502 503 504 = @maintenance;
    
    location / {
        proxy_pass http://n8n_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location @maintenance {
        root /usr/share/nginx/html;
        try_files /maintenance.html =502;
    }
}
EOF
```
**Status: COMPLETED** - Created improved configuration templates for n8n, qdrant, and ollama

#### a.3. Address Helper Script Issues for Rootless Environment
```bash
# Modify helper scripts to avoid sudo commands
# Example modification for start-n8n.sh:
if [ $? -eq 0 ]; then
  echo "Enabling nginx configuration for n8n..."
  # Use permissions that don't require sudo
  ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf
  docker restart core-nginx-1
fi
```
**Status: COMPLETED** - Updated scripts to work in rootless environment

#### a.4. Complete MCP Configuration Separation
```bash
# Separate mcp-seqthinking configuration from mcp.conf
# Create dedicated configuration files for each MCP service
```
**Status: PLANNED** - To be implemented

#### a.5. Verify SAN Configuration in Host File
```bash
# Ensure host file has proper SAN entries for all services
cat /etc/hosts | grep -E '(postgres|n8n|mcp|qdrant|ollama)'

# Verify DNS resolution works from nginx container
docker exec -it core-nginx-1 getent hosts postgres
docker exec -it core-nginx-1 getent hosts n8n
```
**Status: PLANNED** - To be implemented

### Phase 2: Cross-Service Communication Verification

#### 2.1. Test Nginx Proxy to N8N
- [x] Verify nginx properly routes to n8n service
- [x] Check nginx configuration and logs
- [x] Test access through the configured endpoints

#### 2.2. Test N8N to Database
- [x] Verify n8n can read/write to postgres database
- [ ] Check n8n workflows that interact with the database
- [ ] Verify credentials import/export functionality

#### 2.3. Test MCP to AI Services
- [ ] Verify MCP services can communicate with AI services like qdrant and ollama
- [ ] Check for any networking issues in container logs
- [ ] Test API calls between services

#### 2.4. Test External Access
- [ ] Verify that external clients can access services through nginx
- [ ] Test authentication mechanisms still work
- [ ] Verify SSL/TLS if configured

#### 2.5. Verify Network Resolution Across Project Namespaces
- [ ] Test hostname resolution from containers in different projects
- [ ] Verify that SAN entries in the host file are working correctly
- [ ] Confirm services can be accessed by both project-prefixed names and service names

### Phase 3: GPU Resource Verification

#### 3.1. Check GPU Allocation
```bash
docker exec -it ollama-gpu nvidia-smi
```
- [ ] Verify GPU resources are properly allocated
- [ ] Check for any resource contention issues

#### 3.2. Test GPU Performance
- [ ] Run a simple benchmark to verify GPU performance
- [ ] Compare performance to the original configuration
- [ ] Verify all GPU-dependent services can access the GPU

#### 3.3. Monitor GPU Usage
- [ ] Check GPU usage across different services
- [ ] Verify that services are properly utilizing GPU resources
- [ ] Look for any anomalies in GPU utilization

### Phase 4: Full System Test

#### 4.1. Test End-to-End Workflows
- [ ] Execute common workflows that span multiple services
- [ ] Verify all functionality works as expected
- [ ] Test under normal load conditions

#### 4.2. Performance Testing
- [ ] Compare performance metrics with the original configuration
- [ ] Check for any degradation in performance
- [ ] Verify resource utilization is optimal

#### 4.3. Resilience Testing
- [ ] Test service recovery after failure
- [ ] Verify that dependent services handle failures gracefully
- [ ] Test restarting individual services

### Phase 5: Contingency Plan (If Issues Arise)

#### 5.1. Stop All Profile-Based Containers
```bash
./scripts/down-all.sh
```

#### 5.2. Restore Original Configuration
```bash
./scripts/rollback.sh
```

#### 5.3. Verify Original Configuration Restored
- [ ] Check containers are running with original configuration
- [ ] Verify functionality is restored
- [ ] Document any issues encountered

### Phase 6: Implementation (If Testing Successful)

#### 6.1. Replace Original Docker Compose File
```bash
mv docker-compose.profile.yml docker-compose.yml
```

#### 6.2. Update Documentation
- [ ] Update main README with new profile-based approach
- [ ] Document use of helper scripts
- [ ] Create troubleshooting guide for common issues

#### 6.3. User Training
- [ ] Train team members on the new setup
- [ ] Provide examples of common operations
- [ ] Address any questions or concerns

## Current Issues and Resolutions

Based on our review and testing, the following issues have been identified and addressed:

### 1. Nginx Restart Loop

**Issue**: Nginx container was repeatedly restarting, likely due to dependencies on unavailable services.

**Root Cause**: 
- Legacy upstream directives that expect services to be available
- Improper error handling when services are unavailable
- Historical tight coupling with n8n and other application services
- Nginx configuration path issue - nginx was looking for configuration files in `/etc/nginx/sites-enabled/` but the mount was to `/home/groot/nginx`

**Resolution**:
- Created a minimal.conf file that allows nginx to start without dependencies
- Implemented proper error handling with maintenance pages
- Fixed the path issue by creating symbolic links from `/etc/nginx/sites-enabled/` to `/home/groot/nginx/sites-enabled/*`
- Added multiple fallback mechanisms in upstream directives

### 2. Rootless Docker Environment Issues

**Issue**: Script commands using sudo may cause permission problems in rootless Docker.

**Root Cause**:
- Docker is running in rootless mode
- Helper scripts use sudo for managing symbolic links
- Rootless containers have limited permissions

**Resolution**:
- Removed sudo commands from scripts
- Modified scripts to work with appropriate permissions
- Implemented alternative approaches for configuration management
- Tested all scripts in the rootless environment

### 3. MCP Configuration Separation

**Issue**: MCP services' nginx configuration is not fully separated.

**Root Cause**:
- `mcp.conf` was originally designed for both MCP services
- Only mcp-memory has been separated so far

**Resolution Plan**:
- Complete the separation of mcp-seqthinking configuration
- Create dedicated configuration files for each service
- Test each service with its own configuration
- Update scripts to handle the separate configurations

### 4. Service Communication Across Projects

**Issue**: Services in different project namespaces may have trouble communicating.

**Root Cause**:
- Container names include project prefixes (e.g., core-postgres-1)
- Environment variables still reference original hostnames
- Current nginx configuration doesn't account for project-prefixed container names

**Resolution**:
- Implemented multiple fallback mechanisms in upstream directives
- Added support for both project-prefixed and service names
- Leveraged SAN entries in host file for consistent hostname resolution
- Updated nginx configuration to handle service unavailability gracefully

### 5. SAN Configuration for Service Discovery

**Issue**: Cross-service communication relies on proper SAN configuration in the host file.

**Root Cause**:
- Split services across project namespaces changes DNS resolution
- Original configuration assumed all services in same namespace

**Resolution Plan**:
- Verify current SAN entries in the host file
- Ensure all required service names are properly mapped
- Test hostname resolution from different containers
- Update nginx configuration to use both project-aware names and SAN entries

### Deprecated

The following issues have been resolved and are no longer relevant:

- **N8N Service Health Issues**: The n8n container was previously marked as unhealthy, but this has been resolved.
- **Container Naming Conflicts**: The conflicts between containers started with different project names have been resolved by using consistent naming conventions.

## Go/No-Go Decision Points

Each phase includes critical decision points:

1. **After Phase a:** 
   - ✅ Nginx is stable and running independently of application services
   - ✅ Helper scripts work properly in the rootless environment
   - ✅ These critical issues have been resolved

2. **After Phase 1:** 
   - ✅ Core services start successfully in their respective project namespaces
   - ✅ N8N services start successfully in their respective project namespaces
   - ✅ AI services start successfully in their respective project namespaces
   - 📅 MCP services need to be tested
   - 📅 Utility services need to be tested

3. **After Phase 2:** 
   - 🔄 Cross-service communication needs to be fully tested
   - 📅 If any communication issues are detected, roll back and investigate

4. **After Phase 3:** 
   - 📅 GPU resources must be properly allocated and utilized
   - 📅 If GPU issues are detected, roll back and investigate

5. **After Phase 4:** 
   - 📅 All end-to-end workflows must function as expected
   - 📅 Performance must be equal or better than the original configuration
   - 📅 If any functional or performance issues are detected, roll back and investigate

## Risk Assessment

| Risk | Probability | Impact | Mitigation | Status |
|------|------------|--------|------------|--------|
| Service communication failure | Medium | High | Ensure network configuration is preserved; test thoroughly before full implementation | 🔄 In Progress |
| GPU resource contention | Medium | Medium | Monitor GPU usage; adjust resource allocation if needed | 📅 Pending |
| Container name conflicts | Low | Medium | Use unique container names; use project namespaces | ✅ Resolved |
| Data loss | Low | High | No data volumes will be affected by this change; backups are still recommended | ✅ Verified |
| Performance degradation | Low | Medium | Compare performance metrics; rollback if significant degradation | 📅 Pending |
| Nginx configuration failures | High | High | Redesign configuration to be service-agnostic; implement robust fallback mechanisms | ✅ Resolved |
| Rootless Docker permission issues | Medium | Medium | Adjust scripts to work without sudo; modify permissions on configuration directories | ✅ Resolved |
| Hostname resolution failures | High | High | Verify SAN configuration; implement multiple resolution methods in nginx | 🔄 In Progress |

## Post-Migration Tasks

1. **Documentation Updates**
   - Update all documentation to reflect the new configuration
   - Create new troubleshooting guides as needed
   - Add section on nginx configuration best practices

2. **Monitoring Setup**
   - Ensure monitoring tools are aware of the new project structure
   - Update dashboards if necessary
   - Add specific monitoring for nginx to detect configuration issues

3. **Automation Updates**
   - Update any CI/CD pipelines that interact with the environment
   - Update maintenance scripts
   - Implement improved automation for nginx configuration management

4. **Training**
   - Provide team training on the new helper scripts
   - Document common operations
   - Include specific training on nginx configuration management

5. **Performance Optimization**
   - Analyze performance data and optimize as needed
   - Consider further refinement of profiles based on usage patterns
   - Review nginx performance with the new configuration

6. **Rootless Docker Best Practices**
   - Document lessons learned from running in rootless mode
   - Create best practices for future development
   - Implement consistent permission management approach 