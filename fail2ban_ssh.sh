#!/bin/bash

# Update package lists and install Fail2ban
echo "Updating package lists and installing Fail2ban..."
sudo apt update
sudo apt install -y fail2ban

# Create a custom Fail2ban configuration file for SSH
echo "Creating Fail2ban configuration for SSH..."

# Ensure the local jail configuration directory exists
sudo mkdir -p /etc/fail2ban/jail.d

# Create the SSH jail configuration
sudo tee /etc/fail2ban/jail.d/ssh-jail.local > /dev/null <<EOL
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
maxretry = 3
findtime = 7m
bantime = 100h

# Custom rule for failed login attempts
[sshd-fail-login]
enabled = true
port    = ssh
logpath = %(sshd_log)s
maxretry = 4
findtime = 7m
bantime = 100h
EOL

# Restart Fail2ban to apply the new configuration
echo "Restarting Fail2ban to apply the configuration..."
sudo systemctl restart fail2ban

# Confirming Fail2ban is running
echo "Checking Fail2ban status..."
sudo systemctl status fail2ban | grep "active (running)"

echo "Fail2ban has been installed and configured to block IPs with:"
echo " - 3 or more SSH connection attempts in 10 minutes"
echo " - 4 or more failed SSH login attempts in 10 minutes"
echo "Banned IPs will be blocked for 1 hour."
