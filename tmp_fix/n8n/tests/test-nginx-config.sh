#!/bin/bash
# Test script to verify nginx configuration
# This script checks if nginx is properly configured and can access the services

set -e

echo "Testing nginx configuration..."

# Create directory if it doesn't exist
mkdir -p /home/groot/nginx/tests/results

# Function to test a service
test_service() {
  local service_name=$1
  local host_header=$2
  local endpoint=$3
  local expected_status=$4
  
  echo "Testing $service_name at $endpoint (expected status: $expected_status)..."
  
  # Make the request and capture the status code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host_header" "http://localhost:8080$endpoint")
  
  # Check if the status code matches the expected status
  if [ "$status_code" -eq "$expected_status" ]; then
    echo "✅ $service_name test passed! Status code: $status_code"
    return 0
  else
    echo "❌ $service_name test failed! Expected status code $expected_status but got $status_code"
    return 1
  fi
}

# Function to test nginx configuration
test_nginx_config() {
  echo "Testing nginx configuration..."
  docker exec -it core-nginx nginx -t
  if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration test passed!"
    return 0
  else
    echo "❌ Nginx configuration test failed!"
    return 1
  fi
}

# Function to check if a service is running
check_service_running() {
  local service_name=$1
  
  echo "Checking if $service_name is running..."
  if docker ps | grep -q "$service_name"; then
    echo "✅ $service_name is running!"
    return 0
  else
    echo "❌ $service_name is not running!"
    return 1
  fi
}

# Function to check nginx path configuration
check_nginx_paths() {
  echo "Checking nginx path configuration..."
  
  # Check if /etc/nginx/sites-enabled exists in the container
  if docker exec -it core-nginx ls -la /etc/nginx/sites-enabled/ > /dev/null 2>&1; then
    echo "✅ /etc/nginx/sites-enabled/ exists in the container!"
    
    # Check if the symbolic links are correct
    docker exec -it core-nginx ls -la /etc/nginx/sites-enabled/ > /home/groot/nginx/tests/results/sites-enabled.txt
    echo "Symbolic links in /etc/nginx/sites-enabled/:"
    cat /home/groot/nginx/tests/results/sites-enabled.txt
    
    return 0
  else
    echo "❌ /etc/nginx/sites-enabled/ does not exist in the container!"
    return 1
  fi
}

# Main test function
main() {
  echo "Starting nginx configuration tests..."
  
  # Check if core services are running
  check_service_running "core-nginx"
  check_service_running "core-postgres-1"
  
  # Check nginx configuration
  test_nginx_config
  
  # Check nginx path configuration
  check_nginx_paths
  
  # Test default endpoint
  test_service "Default" "localhost" "/" 200
  
  # Test n8n endpoint if n8n is running
  if check_service_running "n8n"; then
    test_service "N8N" "n8n.mulder.local" "/" 200
  fi
  
  # Test qdrant endpoint if qdrant is running
  if check_service_running "qdrant"; then
    test_service "Qdrant" "qdrant.mulder.local" "/" 200
  fi
  
  # Test ollama endpoint if ollama is running
  if check_service_running "ollama"; then
    test_service "Ollama" "ollama.mulder.local" "/" 200
  fi
  
  echo "All tests completed!"
}

# Run the main test function
main 