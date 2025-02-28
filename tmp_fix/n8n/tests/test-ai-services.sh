#!/bin/bash

# Test script for AI services (Qdrant and Ollama)
# This script verifies that Qdrant and Ollama services are running correctly
# and accessible through Nginx.

# Set colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${YELLOW}==== $1 ====${NC}\n"
}

# Function to check if a service is running
check_service_running() {
    local service_name=$1
    echo -e "\n${YELLOW}Checking if $service_name is running...${NC}"
    
    if docker ps | grep -q $service_name; then
        echo -e "${GREEN}✓ $service_name is running${NC}"
        return 0
    else
        echo -e "${RED}✗ $service_name is not running${NC}"
        return 1
    fi
}

# Function to check if Nginx is running
check_nginx_running() {
    echo -e "\n${YELLOW}Checking if Nginx is running...${NC}"
    
    if docker ps | grep -q core-nginx; then
        echo -e "${GREEN}✓ Nginx is running${NC}"
        return 0
    else
        echo -e "${RED}✗ Nginx is not running${NC}"
        return 1
    fi
}

# Function to check if Nginx configuration is valid
check_nginx_config() {
    echo -e "\n${YELLOW}Checking if Nginx configuration is valid...${NC}"
    
    if docker exec core-nginx nginx -t 2>/dev/null; then
        echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Nginx configuration is invalid${NC}"
        return 1
    fi
}

# Function to check if Nginx has the service configuration loaded
check_nginx_service_config() {
    local service_name=$1
    echo -e "\n${YELLOW}Checking if Nginx has $service_name configuration loaded...${NC}"
    
    if docker exec core-nginx ls /etc/nginx/sites-enabled/ | grep -q "$service_name.conf"; then
        echo -e "${GREEN}✓ $service_name configuration is loaded${NC}"
        return 0
    else
        echo -e "${RED}✗ $service_name configuration is not loaded${NC}"
        return 1
    fi
}

# Function to test direct API access to a service from the host
test_direct_api() {
    local service_name=$1
    local endpoint=$2
    local port=$3
    
    echo -e "\n${YELLOW}Testing direct API access to $service_name...${NC}"
    
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$endpoint" | grep -q "200\|201"; then
        echo -e "${GREEN}✓ Direct API access to $service_name is working${NC}"
        return 0
    else
        echo -e "${RED}✗ Direct API access to $service_name failed${NC}"
        return 1
    fi
}

# Function to test Nginx container access to a service
test_nginx_container_access() {
    local service_name=$1
    local container_name=$2
    local endpoint=$3
    
    echo -e "\n${YELLOW}Testing Nginx container access to $service_name...${NC}"
    
    if docker exec core-nginx wget -q -O - "http://$container_name$endpoint" > /dev/null; then
        echo -e "${GREEN}✓ Nginx container can access $service_name${NC}"
        return 0
    else
        echo -e "${RED}✗ Nginx container cannot access $service_name${NC}"
        return 1
    fi
}

# Function to test Nginx proxy access to a service
test_nginx_proxy() {
    local service_name=$1
    local host_header=$2
    local endpoint=$3
    
    echo -e "\n${YELLOW}Testing Nginx proxy access to $service_name...${NC}"
    
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host_header" "http://localhost:8080$endpoint")
    echo -e "Status code: $status_code"
    
    if [[ "$status_code" == "200" || "$status_code" == "201" ]]; then
        echo -e "${GREEN}✓ Nginx proxy access to $service_name is working${NC}"
        return 0
    else
        echo -e "${RED}✗ Nginx proxy access to $service_name failed${NC}"
        return 1
    fi
}

# Function to test Qdrant collections API
test_qdrant_collections() {
    echo -e "\n${YELLOW}Testing Qdrant collections API...${NC}"
    
    local response=$(curl -s -H "Host: qdrant.mulder.local" "http://localhost:8080/collections")
    if [[ "$response" == *"result"* ]]; then
        echo -e "${GREEN}✓ Qdrant collections API is working${NC}"
        echo -e "Response: $response"
        return 0
    else
        echo -e "${RED}✗ Qdrant collections API failed${NC}"
        echo -e "Response: $response"
        return 1
    fi
}

# Function to test Ollama models API
test_ollama_models() {
    echo -e "\n${YELLOW}Testing Ollama models API...${NC}"
    
    local response=$(curl -s -H "Host: ollama.mulder.local" "http://localhost:8080/api/tags")
    if [[ "$response" == *"[]"* ]]; then
        echo -e "${GREEN}✓ Ollama models API is working${NC}"
        echo -e "Response: $response"
        return 0
    else
        echo -e "${RED}✗ Ollama models API failed${NC}"
        echo -e "Response: $response"
        return 1
    fi
}

# Main function
main() {
    print_header "AI Services Test Script"
    
    # Test Nginx configuration
    check_nginx_running
    check_nginx_config
    check_nginx_service_config "qdrant"
    check_nginx_service_config "ollama"
    
    # Test Qdrant
    print_header "Testing Qdrant Service"
    check_service_running "qdrant"
    test_direct_api "qdrant" "/healthz" "6333"
    test_nginx_container_access "qdrant" "qdrant:6333" "/healthz"
    test_nginx_proxy "qdrant" "qdrant.mulder.local" "/healthz"
    test_qdrant_collections
    
    # Test Ollama
    print_header "Testing Ollama Service"
    check_service_running "ollama"
    test_direct_api "ollama" "/api/version" "11434"
    test_nginx_container_access "ollama" "ollama:11434" "/api/version"
    test_nginx_proxy "ollama" "ollama.mulder.local" "/api/version"
    test_ollama_models
    
    print_header "Test Summary"
    echo "This script tested the following:"
    echo "1. Nginx configuration for AI services"
    echo "2. Qdrant service availability and API access"
    echo "3. Ollama service availability and API access"
    echo ""
    echo "If all tests passed, the AI services are working correctly."
    echo "If any tests failed, check the logs for more information:"
    echo "  - docker logs core-nginx"
    echo "  - docker logs qdrant"
    echo "  - docker logs ollama"
}

# Run the main function
main 