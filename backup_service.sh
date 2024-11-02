#!/bin/bash

# Check if the service name is provided as a parameter
if [ -z "$1" ]; then
  echo "Usage: $0 <service-name>"
  exit 1
fi

SERVICE_NAME="$1"
BACKUP_DIR="/backup/path/${SERVICE_NAME}-backup-$(date +%Y%m%d)"

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

echo "Backup completed for $SERVICE_NAME at $BACKUP_DIR"

