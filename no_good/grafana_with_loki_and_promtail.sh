#!/bin/bash

# Ensure a bot token and chat ID are provided as arguments
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: sudo ./your_script.sh <bot_token> <chat_id>"
  exit 1
fi

# Set the bot token and chat ID from provided parameters
BOT_TOKEN="$1"
CHAT_ID="$2"

# Update the system and install necessary packages
sudo apt-get update && sudo apt-get install -y curl wget git prometheus prometheus-node-exporter auditd 
# get grafana
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O /usr/share/keyrings/grafana-archive-keyring.gpg https://packages.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl start grafana-server

# get alertmanager
mkdir -p ~/alertmanager && cd ~/alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz 
tar -xvf alertmanager-0.26.0.linux-amd64.tar.gz 
sudo mv alertmanager-0.26.0.linux-amd64/alertmanager /usr/local/bin/
sudo mv alertmanager-0.26.0.linux-amd64/amtool /usr/local/bin/

# Create Alertmanager configuration file before starting the service
sudo mkdir -p /etc/alertmanager
cat <<EOF | sudo tee /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: 'telegram'

receivers:
  - name: 'telegram'
    telegram_configs:
    - bot_token: '${BOT_TOKEN}'
      chat_id: '${CHAT_ID}'
      send_resolved: true
EOF

# Create Alertmanager service file
sudo tee /etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Prometheus Alertmanager
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable/start Alertmanager
sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager

# Ensure Prometheus is enabled and running
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Ensure Node Exporter is enabled and running
sudo systemctl enable prometheus-node-exporter
sudo systemctl start prometheus-node-exporter

# Configure Prometheus to scrape Node Exporter and Loki
echo "Configuring Prometheus..."
cat <<EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']
EOF

# Restart Prometheus to apply new configuration
sudo systemctl restart prometheus

# Ensure Auditd is enabled and running
sudo systemctl enable auditd
sudo systemctl start auditd

# Configure Auditd rules to monitor user creation, SSH changes, sudoers, cron jobs
cat <<EOF | sudo tee /etc/audit/rules.d/audit.rules
-w /etc/passwd -p wa -k user_creation
-w /etc/ssh/sshd_config -p wa -k ssh_config_change
-w /etc/sudoers -p wa -k sudo_priv_escalation
-w /etc/crontab -p wa -k cron_jobs
EOF

# Restart Auditd to apply rules
sudo systemctl restart auditd

# Configure Grafana Provisioning for Dashboards and Alerts
mkdir -p /etc/grafana/provisioning/dashboards

# Create Grafana provisioning file
cat <<EOF | sudo tee /etc/grafana/provisioning/dashboards/default.yaml
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOF

# Add dashboard and alert rules (e.g., CPU usage, SSH failures, etc.)
mkdir -p /var/lib/grafana/dashboards

cat <<EOF | sudo tee /var/lib/grafana/dashboards/alerts.json
{
  "dashboard": {
    "panels": [
      {
        "type": "graph",
        "title": "SSH Login Attempts",
        "targets": [
          {
            "expr": "increase(sshd_failed_logins_total[1m]) > 3",
            "legendFormat": "SSH Login Failures"
          }
        ]
      },
      {
        "type": "graph",
        "title": "CPU Usage",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{job='node',mode='idle'}[5m])) * 100)",
            "legendFormat": "CPU Usage (%)"
          }
        ]
      }
    ]
  }
}
EOF

# Restart Grafana
sudo systemctl restart grafana-server

# Final message
echo "Monitoring setup is complete! Prometheus, Node Exporter, Auditd, Grafana, and Alertmanager are configured and running."
