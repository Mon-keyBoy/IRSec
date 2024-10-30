#!/bin/bash

# Be in desktop and run with sudo

# Ensure a user was provided as an argument
if [ -z "$1" ]; then
  echo "No user provided. Please provide a username as a parameter."
  echo "Usage: sudo ./restore_binaries.sh username"
  exit 1
fi

# Set the user to the provided parameter
USER_NAME="$1"

# The directory where the original binaries were backed up
BACKUP_DIR="/home/$USER_NAME/Desktop/initial_binaries_copies"

# Restore each package
for package in $(ls "$BACKUP_DIR"); do
  echo "Restoring package: $package"

  # Iterate over each file in the package backup directory
  for file in "$BACKUP_DIR/$package"/*; do
    original_path=$(dpkg -L "$package" | grep "$(basename "$file")")

    if [ -n "$original_path" ]; then
      echo "Restoring $file to $original_path..."

      # Copy the file back to its original location
      cp "$file" "$original_path"

      # Restore the file permissions if saved
      if [ -f "$file.permissions" ]; then
        original_perms=$(cat "$file.permissions")
        chmod "$original_perms" "$original_path"
        echo "Restored permissions for $original_path to $original_perms"
      else
        echo "No permissions file found for $file, using default permissions."
        chmod +x "$original_path"  # Restore executable permissions by default
      fi
    else
      echo "Original path for $(basename "$file") not found."
    fi
  done
done

echo "Restoration of binaries complete."