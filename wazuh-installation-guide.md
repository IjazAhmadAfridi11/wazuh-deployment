
##  Wazuh Installation Guide


##  Table of Contents:


* [Wazuh Installation Guide](#wazuh-installation-guide)
* [Prerequisites](#prerequisites)
* [Step 1: Update the System & Install Required Packages](#step-1-update-the-system-install-required-packages)
* [Step 2: Add Wazuh GPG Key & Repository](#step-2-add-wazuh-gpg-key-repository)
* [Step 3: Generate SSL Certificates](#step-3-generate-ssl-certificates)
* [step 4: Install Wazuh Indexer](#step-4-install-wazuh-indexer)
* [Step 5: Install Wazuh Manager](#step-5-install-wazuh-manager)
* [Step 6: Install Filebeat](#step-6-install-filebeat)
* [Step 7: Install Wazuh Dashboard](#step-7-install-wazuh-dashboard)
* [Step 8: Configure Wazuh API Connection](#step-8-configure-wazuh-api-connection)
* [Step 9 (Optional): Add Wazuh Agent on Another System](#step-9-optional-add-wazuh-agent-on-another-system)
* [Author](#author)



This guide provides step-by-step instructions to install and configure the **Wazuh SIEM** on an Ubuntu/Debian-based system. It is part of a full open-source SIEM deployment using Wazuh.

---

##  Prerequisites

- OS: Ubuntu 20.04+ / Debian 11+
- Root or sudo privileges
- Internet access
- Minimum 4 GB RAM (for testing); 8 GB recommended for production

---


##  Step 1: Update the System & Install Required Packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl apt-transport-https lsb-release gnupg2 -y
```

---



##  Step 2: Add Wazuh GPG Key & Repository

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | \
sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update
```

---



##  Step 3: Generate SSL Certificates

This step ensures secure communication between Wazuh components.

Download the Wazuh cert tool and default config:

```bash
curl -sO https://packages.wazuh.com/4.12/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.12/config.yml
```

Make the script executable and generate certificates:

```bash
chmod +x wazuh-certs-tool.sh
./wazuh-certs-tool.sh
```

> This creates a `wazuh-certificates.tar` archive containing the required keys and certs.


Edit config.yml to update node names and IPs for Wazuh Manager, Indexer, and Dashboard. Add more node entries as needed.

Generate certificates using ./wazuh-certs-tool.sh -A, compress them, and copy wazuh-certificates.tar to all nodes (Manager, Indexer, Dashboard) using scp.

```bash
./wazuh-certs-tool.sh -A
tar -cvf wazuh-certificates.tar -C ./wazuh-certificates/ .
rm -rf ./wazuh-certificates
```


 Copy to other nodes (replace user@ip with actual values)
``` bash

scp wazuh-certificates.tar user@<wazuh-node-ip>:/path/to/destination
```

---


##  Step 4: Install Wazuh Indexer

Wazuh Indexer stores and searches security event data. It's a required component for the dashboard and advanced features.

```bash
sudo apt install wazuh-indexer -y  #Debian-based Linux distributions
sudo yum install coreutils         #RHEL-based Linux distributions
```
Configure Wazuh Indexer:

 Edit /etc/wazuh-indexer/opensearch.yml and update:

network.host: <node-ip-or-hostname>
node.name: <node-name>          # e.g., node-1

```bash
NODE_NAME=<INDEXER_NODE_NAME>  # e.g., node-1

mkdir -p /etc/wazuh-indexer/certs

tar -xf ./wazuh-certificates.tar -C /etc/wazuh-indexer/certs/ ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./admin.pem ./admin-key.pem ./root-ca.pem

mv -n /etc/wazuh-indexer/certs/$NODE_NAME.pem /etc/wazuh-indexer/certs/indexer.pem
mv -n /etc/wazuh-indexer/certs/$NODE_NAME-key.pem /etc/wazuh-indexer/certs/indexer-key.pem

chmod 500 /etc/wazuh-indexer/certs
chmod 400 /etc/wazuh-indexer/certs/*

chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs

 Optional: remove cert archive if no other components on this node
rm -f ./wazuh-certificates.tar
```

After installation, enable and start the service:

```bash
sudo systemctl daemon-reexec
sudo systemctl enable wazuh-indexer --now
sudo systemctl status wazuh-indexer.services
```

> Make sure port 9200 is open if accessing remotely.
```bash
sudo ss -tuln | grep 9200
sudo lsof -i :9200
```
If output shows something like LISTEN on 0.0.0.0:9200 or 127.0.0.1:9200, the port is active.

---


##  Step 5: Install Wazuh Manager

```bash
sudo apt install wazuh-manager -y
```


 Enable and Start Wazuh Manager

```bash
sudo systemctl daemon-reexec
sudo systemctl enable wazuh-manager --now
sudo systemctl status wazuh-manager.services
```


 Verify Installation

```bash
sudo tail -f /var/ossec/logs/ossec.log
```

---



##  Step 6: Install Filebeat

```bash
sudo apt-get -y install filebeat
```

 Configure Filebeat
```bash
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.12/tpl/wazuh/filebeat/filebeat.yml
```

Edit /etc/filebeat/filebeat.yml — update hosts under output.elasticsearch:
hosts: ["10.0.0.1:9200"]  # Replace with your Wazuh indexer IP(s)
protocol: https
username: ${username}
password: ${password}

 Create keystore and add credentials
filebeat keystore create
```bash
echo admin | filebeat keystore add username --stdin --force
echo admin | filebeat keystore add password --stdin --force
```

Download alerts template and set permissions
```bash
curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.12.0/extensions/elasticsearch/7.x/wazuh-template.json
chmod go+r /etc/filebeat/wazuh-template.json
```

  Install Wazuh Filebeat module
```bash
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | tar -xvz -C /usr/share/filebeat/module
```
 

 Deploy certificates

Make sure wazuh-certificates.tar is in your working directory. Replace <SERVER_NODE_NAME> with your node name:
```bash
NODE_NAME=<SERVER_NODE_NAME>

mkdir -p /etc/filebeat/certs

tar -xf wazuh-certificates.tar -C /etc/filebeat/certs/ ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./root-ca.pem

mv -n /etc/filebeat/certs/$NODE_NAME.pem /etc/filebeat/certs/filebeat.pem
mv -n /etc/filebeat/certs/$NODE_NAME-key.pem /etc/filebeat/certs/filebeat-key.pem

chmod 500 /etc/filebeat/certs
chmod 400 /etc/filebeat/certs/*

chown -R root:root /etc/filebeat/certs
```

  Start and verify Filebeat
```bash
sudo systemctl daemon-reexec
sudo systemctl enable filebeat
sudo systemctl start filebeat
```

Test the output
```bash
test filebeat output
```
Look for connection... OK and version: 7.x to confirm successful setup.


---

##  Step 7: Install Wazuh Dashboard
```bash
sudo apt-get -y install wazuh-dashboard
```

 Configure /etc/wazuh-dashboard/opensearch_dashboards.yml
server.host: 0.0.0.0                  # Allow external access
server.port: 443
opensearch.hosts: ["https://10.0.0.2:9200", "https://10.0.0.3:9200"]
opensearch.ssl.verificationMode: certificate


 Deploy Certificates
```bash
NODE_NAME=<DASHBOARD_NODE_NAME>

mkdir -p /etc/wazuh-dashboard/certs

tar -xf wazuh-certificates.tar -C /etc/wazuh-dashboard/certs/ ./$NODE_NAME.pem ./$NODE_NAME-key.pem ./root-ca.pem

mv -n /etc/wazuh-dashboard/certs/$NODE_NAME.pem /etc/wazuh-dashboard/certs/dashboard.pem
mv -n /etc/wazuh-dashboard/certs/$NODE_NAME-key.pem /etc/wazuh-dashboard/certs/dashboard-key.pem

chmod 500 /etc/wazuh-dashboard/certs
chmod 400 /etc/wazuh-dashboard/certs/*
chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs
```


 Start Dashboard Service
```bash
systemctl daemon-reexec
systemctl enable wazuh-dashboard
systemctl start wazuh-dashboard
```


## Step 8: Configure Wazuh API Connection

Edit /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
hosts:
  - default:
      url: https://<WAZUH_SERVER_IP_ADDRESS>
      port: 55000
      username: wazuh-wui
      password: wazuh-wui
      run_as: false

To test Wazuh API
```bash
curl -k https://<wazuh-ip>:55000
```

 Access the Dashboard 
URL: https://<DASHBOARD_IP>
```
Username: admin
Password: admin
```
 
---



##  Step 9 (Optional): Add Wazuh Agent on Another System

 Install Wazuh Agent on Windows

   1. Requires administrator privileges.
   2. Download the installer:
   3. Get the .msi package from the official Wazuh site.

Install via CLI (replace 10.0.0.2 with your Wazuh Manager IP):

CMD:
```
wazuh-agent-4.12.0-1.msi /q WAZUH_MANAGER="10.0.0.2"
```
PowerShell:
```
.\wazuh-agent-4.12.0-1.msi /q WAZUH_MANAGER="10.0.0.2"
```
 Optional variables: WAZUH_AGENT_NAME, WAZUH_AGENT_GROUP, WAZUH_REGISTRATION_PASSWORD

Start the agent:
```
NET START Wazuh
```
The agent will auto-enroll with the manager.

 Installed path:
C:\Program Files (x86)\ossec-agent


 Install Wazuh Agent on Linux

    Requires root/sudo privileges.

 Add Wazuh Repository
```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list

apt-get update
```
 Install Agent (replace IP):
```bash
WAZUH_MANAGER="10.0.0.2" apt-get install wazuh-agent
```
 Optional vars: WAZUH_AGENT_NAME, WAZUH_AGENT_GROUP, WAZUH_REGISTRATION_PASSWORD

Start Agent
```bash
systemctl daemon-reexec
systemctl enable wazuh-agent
systemctl start wazuh-agent
```

 Install Wazuh Agent on macOS

   1. Requires root privileges.

   2. Download Installer (based on your system):

   3. Intel: wazuh-agent-4.12.0-1.intel64.pkg (macOS Sierra+)

   4. Apple Silicon: wazuh-agent-4.12.0-1.arm64.pkg (macOS Big Sur+)

 Install via CLI (replace IP):
```
echo "WAZUH_MANAGER='10.0.0.2'" > /tmp/wazuh_envs
sudo installer -pkg wazuh-agent-4.12.0-1.intel64.pkg -target /
```
 Optional: Add WAZUH_AGENT_NAME, WAZUH_AGENT_GROUP, WAZUH_REGISTRATION_PASSWORD

 Start Agent

launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist

 Default path: /Library/Ossec/

---




##  Author

**Ijaz Ahmad**  
Cybersecurity Engineer  
📂 GitHub: [your-github-link]  
🔗 LinkedIn: [your-linkedin-link]
