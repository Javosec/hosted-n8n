#!/bin/bash
# Improved start-ai.sh script for deploying AI services (qdrant and ollama)
# This script works in a rootless Docker environment

set -e

# Default to GPU-NVIDIA profile if not specified
HW_PROFILE="${1:-gpu-nvidia}"
echo "Starting AI services with hardware profile: $HW_PROFILE"

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

# Start qdrant service
echo "Starting qdrant service..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d --no-deps qdrant

# Wait for qdrant to initialize
echo "Waiting for qdrant to initialize..."
sleep 5

# Start ollama service based on hardware profile
echo "Starting ollama service with $HW_PROFILE profile..."
if [[ "$HW_PROFILE" == "cpu" ]]; then
  docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d --no-deps ollama-cpu
  OLLAMA_CONTAINER="ollama-cpu"
elif [[ "$HW_PROFILE" == "gpu-amd" ]]; then
  docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d --no-deps ollama-gpu-amd
  OLLAMA_CONTAINER="ollama-gpu-amd"
else
  docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p ai --profile ai --profile $HW_PROFILE up -d --no-deps ollama-gpu
  OLLAMA_CONTAINER="ollama-gpu"
fi

# Wait for ollama to initialize
echo "Waiting for ollama to initialize..."
sleep 10

# Check if services started successfully
if docker ps | grep -q "qdrant" && docker ps | grep -q "$OLLAMA_CONTAINER"; then
  echo "AI services started successfully!"
  
  # Copy the qdrant.conf file
  echo "Copying qdrant nginx configuration..."
  cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/qdrant.conf /home/groot/nginx/sites-available/qdrant.conf
  
  # Create symlink for qdrant.conf
  echo "Creating symlink for qdrant.conf..."
  ln -sf /home/groot/nginx/sites-available/qdrant.conf /home/groot/nginx/sites-enabled/qdrant.conf
  
  # Copy the ollama.conf file
  echo "Copying ollama nginx configuration..."
  cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/ollama.conf /home/groot/nginx/sites-available/ollama.conf
  
  # Create symlink for ollama.conf
  echo "Creating symlink for ollama.conf..."
  ln -sf /home/groot/nginx/sites-available/ollama.conf /home/groot/nginx/sites-enabled/ollama.conf
  
  # Fix nginx configuration paths
  echo "Fixing nginx configuration paths..."
  docker exec -it core-nginx mkdir -p /etc/nginx/sites-enabled
  docker exec -it core-nginx ln -sf /home/groot/nginx/sites-enabled/* /etc/nginx/sites-enabled/
  
  # Restart nginx container
  echo "Restarting nginx to apply new configuration..."
  docker restart core-nginx
  
  echo "AI services deployment completed successfully."
else
  echo "Warning: Some AI services may have issues starting. Check logs with: docker logs qdrant or docker logs $OLLAMA_CONTAINER"
  echo "Not enabling nginx configuration for AI services since they are not running properly."
fi 