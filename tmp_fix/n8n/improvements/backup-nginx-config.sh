#!/bin/bash
# Script to backup the current Nginx configuration
# Part of Phase 1.2 of the Nginx Restoration Plan

set -e

echo "Creating backup of current Nginx configuration..."

# Create backup directory with today's date
BACKUP_DIR="/home/groot/nginx/backup/$(date +%Y%m%d)"
echo "Creating backup directory: $BACKUP_DIR"
mkdir -p $BACKUP_DIR

# Backup sites-available directory
echo "Backing up sites-available directory..."
if [ -d "/home/groot/nginx/sites-available" ]; then
  cp -r /home/groot/nginx/sites-available/ $BACKUP_DIR/
  echo "✅ sites-available directory backed up successfully"
else
  echo "⚠️ sites-available directory not found, skipping"
fi

# Backup sites-enabled directory
echo "Backing up sites-enabled directory..."
if [ -d "/home/groot/nginx/sites-enabled" ]; then
  cp -r /home/groot/nginx/sites-enabled/ $BACKUP_DIR/
  echo "✅ sites-enabled directory backed up successfully"
else
  echo "⚠️ sites-enabled directory not found, skipping"
fi

# Backup AI's configuration from conf.d
echo "Backing up AI's configuration from conf.d..."
if docker ps | grep -q "core-nginx"; then
  # Check if the file exists in the container
  if docker exec core-nginx test -f /etc/nginx/conf.d/ai-services.conf; then
    docker exec core-nginx cat /etc/nginx/conf.d/ai-services.conf > $BACKUP_DIR/ai-services.conf
    echo "✅ ai-services.conf backed up successfully"
  else
    echo "⚠️ ai-services.conf not found in container, skipping"
  fi
else
  echo "⚠️ core-nginx container not running, skipping ai-services.conf backup"
fi

# Backup nginx.conf
echo "Backing up nginx.conf..."
if docker ps | grep -q "core-nginx"; then
  docker exec core-nginx cat /etc/nginx/nginx.conf > $BACKUP_DIR/nginx.conf
  echo "✅ nginx.conf backed up successfully"
else
  echo "⚠️ core-nginx container not running, skipping nginx.conf backup"
fi

echo "Backup completed successfully to $BACKUP_DIR"
echo "Marking Phase 1.2 as complete in the plan..."

# List all backed up files
echo "Files backed up:"
ls -la $BACKUP_DIR 