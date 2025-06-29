#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
NODE_NAME="node-1"
CERT_DIR="/etc/wazuh-indexer/certs"

# Update system
echo "[+] Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo "[+] Installing dependencies..."
sudo apt install curl apt-transport-https lsb-release gnupg2 software-properties-common unzip -y

# Add Wazuh GPG key and repository
echo "[+] Adding Wazuh GPG key and repository..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update

# Install Wazuh components
echo "[+] Installing Wazuh components..."
sudo apt install wazuh-manager wazuh-indexer wazuh-dashboard filebeat -y

# Download Wazuh SSL cert tool and config
echo "[+] Downloading certificate generation tool..."
curl -sO https://packages.wazuh.com/4.12/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.12/config.yml
chmod +x wazuh-certs-tool.sh

# Generate SSL certificates
echo "[+] Generating SSL certificates..."
./wazuh-certs-tool.sh -A
tar -cvf wazuh-certificates.tar -C ./wazuh-certificates/ .
rm -rf ./wazuh-certificates

# Deploy certificates for Wazuh Indexer
echo "[+] Deploying certificates for Wazuh Indexer..."
sudo mkdir -p $CERT_DIR
sudo tar -xf wazuh-certificates.tar -C $CERT_DIR ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./admin.pem ./admin-key.pem ./root-ca.pem
sudo mv -n $CERT_DIR/$NODE_NAME.pem $CERT_DIR/indexer.pem
sudo mv -n $CERT_DIR/$NODE_NAME-key.pem $CERT_DIR/indexer-key.pem
sudo chmod 500 $CERT_DIR
sudo chmod 400 $CERT_DIR/*
sudo chown -R wazuh-indexer:wazuh-indexer $CERT_DIR

# Copy predefined config files (must exist in configuration/ directory)
echo "[+] Deploying configuration files..."
sudo cp ../configuration/manager.yml /var/ossec/etc/ossec.conf
sudo cp ../configuration/agent.yml /var/ossec/etc/shared/agent.conf
# Add additional cp commands for indexer, dashboard, and filebeat configs if available

# Enable and start services
echo "[+] Enabling and starting Wazuh services..."
sudo systemctl daemon-reexec
sudo systemctl enable wazuh-indexer wazuh-manager wazuh-dashboard filebeat
sudo systemctl start wazuh-indexer wazuh-manager wazuh-dashboard filebeat

# Final message
echo "[✓] Wazuh installation and setup completed!"
echo "[→] Access Wazuh Dashboard at: https://<your-server-ip> (Default: admin/admin)"
echo "[!] Update <your-server-ip> with actual IP address of the machine."

# Clean up temporary files
rm -f wazuh-certificates.tar wazuh-certs-tool.sh config.yml
