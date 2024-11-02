#!/bin/bash

# Check if the service name is provided as a parameter
if [ -z "$1" ]; then
  echo "Usage: $0 <service-name>"
  exit 1
fi

SERVICE_NAME="$1"
BACKUP_DIR="~/Desktop/${SERVICE_NAME}-backup-$(date +%Y%m%d)"

# Create the backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup configuration files, binaries, and data if they exist
if [ -d "/etc/$SERVICE_NAME" ]; then
  sudo cp -r "/etc/$SERVICE_NAME" "$BACKUP_DIR/"
fi

if [ -d "/var/lib/$SERVICE_NAME" ]; then
  sudo cp -r "/var/lib/$SERVICE_NAME" "$BACKUP_DIR/"
fi

if [ -d "/var/log/$SERVICE_NAME" ]; then
	sudo cp -r "/var/log/$SERVICE_NAME" "$BACKUP_DIR/"
fi

# Optional: Backup systemd unit file if the service is managed by systemd
if [ -f "/lib/systemd/system/$SERVICE_NAME.service" ]; then
  echo "Backing up systemd unit file for $SERVICE_NAME..."
  sudo cp "/lib/systemd/system/$SERVICE_NAME.service" "$BACKUP_DIR/"
fi

# Docker-specific backup if Docker is the service
if [ "$SERVICE_NAME" = "docker" ]; then
  echo "Backing up Docker-specific files..."
  # Additional Docker files and directories if required
  sudo cp -r /etc/docker "$BACKUP_DIR/"
  # You can add more Docker-specific files here if needed
fi

echo "Backup completed for $SERVICE_NAME at $BACKUP_DIR"

