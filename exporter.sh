#!/bin/bash
# must run as root role 
# judge the OS version 
if [ -f /etc/redhat-release ]; then
    echo "Detected CentOS/RHEL, installing wget jq git with yum..."
    sudo yum install -y wget jq git
elif [ -f /etc/debian_version ]; then
    echo "Detected Ubuntu/Debian, installing wget jq git with apt..."
    sudo apt update
    sudo apt install -y wget jq git
else
    echo "Unsupported OS! Only CentOS/RHEL/Ubuntu/Debian are supported."
    exit 1
fi
#install node exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
mv node_exporter-1.9.1.linux-amd64.tar.gz  node_exporter.tar.gz
tar -xvf node_exporter.tar.gz -C /usr/local/
mv  /usr/local/node_exporter-1.9.1.linux-amd64   /usr/local/node_exporter
chown -R prometheus.prometheus /usr/local/node_exporter/
git clone https://github.com/yuhongwei380/exporter.git    /opt/exporter/
mkdir -p /var/lib/node_exporter/textfile_collector/
touch /var/lib/node_exporter/textfile_collector/smartctl.prom
mkdir /opt/exporter/
cat << EOF >/usr/lib/systemd/system/node_exporter.service 
[Unit]
Description=node_export
Documentation=https://github.com/prometheus/node_exporter
After=network.target
[Service]
Type=simple
User=prometheus
ExecStart=/usr/local/node_exporter/node_exporter \
    --web.listen-address=:9101 \
    --collector.textfile.directory="/var/lib/node_exporter/textfile_collector" 
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable node_exporter.service
systemctl restart node_exporter.service

bash /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom
(crontab -l; echo "*/30 * * * * /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom") | crontab -

systemctl status node_exporter.service