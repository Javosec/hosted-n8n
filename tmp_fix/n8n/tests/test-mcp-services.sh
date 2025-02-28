#!/bin/bash

# Test script for MCP services (mcp-memory and mcp-seqthinking)
# This script verifies that MCP services are running correctly
# and accessible through Nginx.

# Set colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set the base URL for services
NGINX_URL="http://localhost:8080"

# Function to print section header
print_header() {
    echo -e "\n${YELLOW}==== $1 ====${NC}\n"
}

# Function to check if a service is running
check_service_running() {
    local service_name=$1
    local container_name=$2
    
    echo -n "Checking if $service_name is running... "
    if docker ps | grep -q "$container_name"; then
        echo -e "${GREEN}Running${NC}"
        return 0
    else
        echo -e "${RED}Not running${NC}"
        return 1
    fi
}

# Function to test direct API access via Docker exec
test_direct_api() {
    local service_name=$1
    local container_name=$2
    local url=$3
    local endpoint=$4
    
    echo -n "Testing direct API access to $service_name... "
    if docker exec -it $container_name curl -s -o /dev/null -w "%{http_code}" "$url$endpoint" 2>/dev/null | grep -q "200\|404"; then
        echo -e "${GREEN}Success${NC}"
        return 0
    else
        echo -e "${RED}Failed${NC}"
        return 1
    fi
}

# Function to test Nginx proxy access
test_nginx_proxy() {
    local service_name=$1
    local host_header=$2
    local endpoint=$3
    
    echo -n "Testing Nginx proxy access to $service_name... "
    if curl -s -o /dev/null -w "%{http_code}" -H "Host: ${host_header}" "${NGINX_URL}${endpoint}" | grep -q "200\|404"; then
        echo -e "${GREEN}Success${NC}"
        return 0
    else
        echo -e "${RED}Failed${NC}"
        return 1
    fi
}

# Function to test MCP Memory
test_mcp_memory() {
    print_header "Testing MCP Memory"
    
    # Check if MCP Memory container is running
    check_service_running "MCP Memory" "mcp-memory"
    
    # Test direct API access using Docker exec
    test_direct_api "MCP Memory" "mcp-memory" "http://localhost:8000" "/health"
    
    # Test Nginx proxy access
    test_nginx_proxy "MCP Memory" "mcp-memory.mulder.local" "/health"
    
    # Test API endpoints
    echo -n "Testing MCP Memory API through Nginx... "
    if curl -s -H "Host: mcp-memory.mulder.local" "${NGINX_URL}/api/status" | grep -q "status"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
}

# Function to test MCP Seqthinking
test_mcp_seqthinking() {
    print_header "Testing MCP Seqthinking"
    
    # Check if MCP Seqthinking container is running
    check_service_running "MCP Seqthinking" "mcp-seqthinking"
    
    # Test direct API access using Docker exec
    test_direct_api "MCP Seqthinking" "mcp-seqthinking" "http://localhost:8001" "/health"
    
    # Test Nginx proxy access
    test_nginx_proxy "MCP Seqthinking" "mcp-seqthinking.mulder.local" "/health"
    
    # Test API endpoints
    echo -n "Testing MCP Seqthinking API through Nginx... "
    if curl -s -H "Host: mcp-seqthinking.mulder.local" "${NGINX_URL}/api/status" | grep -q "status"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
}

# Function to test Nginx configuration
test_nginx_config() {
    print_header "Testing Nginx Configuration"
    
    # Check if Nginx container is running
    check_service_running "Nginx" "core-nginx"
    
    # Test Nginx configuration
    echo -n "Testing Nginx configuration... "
    if docker exec -it core-nginx nginx -t 2>&1 | grep -q "successful"; then
        echo -e "${GREEN}Valid${NC}"
    else
        echo -e "${RED}Invalid${NC}"
    fi
    
    # Check if MCP service configurations are loaded
    echo -n "Checking if MCP Memory configuration is loaded... "
    if docker exec -it core-nginx ls /etc/nginx/sites-enabled/ | grep -q "mcp-memory.conf"; then
        echo -e "${GREEN}Loaded${NC}"
    else
        echo -e "${RED}Not loaded${NC}"
    fi
    
    echo -n "Checking if MCP Seqthinking configuration is loaded... "
    if docker exec -it core-nginx ls /etc/nginx/sites-enabled/ | grep -q "mcp-seqthinking.conf"; then
        echo -e "${GREEN}Loaded${NC}"
    else
        echo -e "${RED}Not loaded${NC}"
    fi
}

# Function to test cross-service communication
test_cross_service_communication() {
    print_header "Testing Cross-Service Communication"
    
    # Test MCP Memory to Qdrant
    echo -n "Testing MCP Memory to Qdrant communication... "
    if docker exec -it mcp-memory curl -s -o /dev/null -w "%{http_code}" "http://qdrant:6333/health" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Test MCP Memory to Ollama
    echo -n "Testing MCP Memory to Ollama communication... "
    if docker exec -it mcp-memory curl -s -o /dev/null -w "%{http_code}" "http://ollama:11434/api/version" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Test MCP Seqthinking to Qdrant
    echo -n "Testing MCP Seqthinking to Qdrant communication... "
    if docker exec -it mcp-seqthinking curl -s -o /dev/null -w "%{http_code}" "http://qdrant:6333/health" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Test MCP Seqthinking to Ollama
    echo -n "Testing MCP Seqthinking to Ollama communication... "
    if docker exec -it mcp-seqthinking curl -s -o /dev/null -w "%{http_code}" "http://ollama:11434/api/version" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}Success${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
}

# Main function
main() {
    print_header "MCP Services Test Script"
    
    # Test Nginx configuration
    test_nginx_config
    
    # Test MCP Memory
    test_mcp_memory
    
    # Test MCP Seqthinking
    test_mcp_seqthinking
    
    # Test cross-service communication
    test_cross_service_communication
    
    print_header "Test Summary"
    echo "This script tested the following:"
    echo "1. Nginx configuration for MCP services"
    echo "2. MCP Memory service availability and API access"
    echo "3. MCP Seqthinking service availability and API access"
    echo "4. Cross-service communication between MCP services and AI services"
    echo ""
    echo "If all tests passed, the MCP services are working correctly."
    echo "If any tests failed, check the logs for more information:"
    echo "  - docker logs core-nginx"
    echo "  - docker logs mcp-memory"
    echo "  - docker logs mcp-seqthinking"
}

# Run the main function
main 