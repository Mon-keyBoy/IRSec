#!/bin/bash

# Ensure a user was provided as an argument
if [ -z "$1" ]; then
  echo "No user provided. Please provide a username as a parameter."
  echo "Usage: sudo ./your_script.sh username"
  exit 1
fi

  # Set the user to the provided parameter
USER_NAME="$1"

initial_downloads_and_redownloads(){
 # Check if the script is being run as root or with sudo
  if [ "$EUID" -ne 0 ]; then
    echo "The script must be run with sudo, not directly as root."
    exit
  fi

  # Check if the script is being run with sudo
  if [ -z "$SUDO_USER" ]; then
    echo "This script must be run with sudo."
    exit 1
  else
    echo "Script is running with sudo by user: $SUDO_USER"
    # You can place the rest of your script here
  fi

  # Verify if the user exists
  if ! id "$USER_NAME" &>/dev/null; then
    echo "User $USER_NAME does not exist. Exiting."
    exit 1
  fi

  echo "Script is running with sudo by user: $SUDO_USER for target user: $USER_NAME"

  # Update and upgrade the system
  echo "Updating and upgrading the system..."
  apt-get update && apt-get upgrade -y

  #ND-- what other packages do we want??
  # Install important tools 
  echo "Installing important packages..."
  apt-get install -y vim #add more packages needed and wanted

  # Create the directory to store the original copies of binaries on the provided user's Desktop
  mkdir -p /home/$USER_NAME/Desktop/initial_binaries_copies

  #ND-- is that list complete and correct??
  # Reinstall essential system binaries
  # This ensures that any malicious binaries are replaced with clean versions from trusted sources
  echo "Reinstalling essential system binaries to ensure integrity..."

  essential_packages=( # List of essential packages to reinstall (can be customized based on competition needs)

    "coreutils"         # Basic file, shell, and text manipulation utilities
    "bash"              # The Bourne Again Shell
    "sudo"              # Allows users to run commands as root
    "openssl"           # Cryptographic toolkit
    "openssh-server"    # SSH server for remote access
    "gnupg"             # GnuPG for signing and encryption
    "util-linux"        # System utilities (fdisk, mount, etc.)
    "procps"            # Utilities related to processes (ps, top, etc.)
    "net-tools"         # Network tools (ifconfig, netstat, etc.)
    "iptables"          # Firewall management tool
    "passwd"            # Password management utility

  )

  # For each package, copy the binaries, remove executability, and then reinstall
  for package in "${essential_packages[@]}"; do

    # Get the list of files installed by the package
    package_files=$(dpkg -L "$package" 2>/dev/null)
    
    # Create a subdirectory for each package
    mkdir -p /home/$USER_NAME/Desktop/initial_binaries_copies/"$package"

    # Copy binaries to the directory and remove executability BEFORE reinstalling
    for file in $package_files; do
      if [ -f "$file" ] && [ -x "$file" ]; then
        echo "Copying $file and removing executability..."
        cp "$file" /home/$USER_NAME/Desktop/initial_binaries_copies/"$package"
        chmod a-x,a+r /home/$USER_NAME/Desktop/initial_binaries_copies/$(basename "$file")
      fi
    done

    echo "Reinstalling $package and its dependencies..."
    # Reinstall the package 
    apt-get install --reinstall -y "$package"

  done

  echo "Reinstallation of essential system binaries complete."

  # install webin, a convineint GUI for iptables and other things, this is for use during the comp not for initial hardening
  echo "Starting Webmin installation..."
  # Add the Webmin repository and GPG key
  echo "deb http://download.webmin.com/download/repository sarge contrib" | sudo tee /etc/apt/sources.list.d/webmin.list
  wget -qO - http://www.webmin.com/jcameron-key.asc | sudo apt-key add -
  # Update the package list to include the Webmin repository
  sudo apt update
  # Install Webmin
  sudo apt install -y webmin --install-recommends
  echo "Webmin installation complete."
  rm debian_script.sh
}


#call function
initial_downloads_and_redownloads
