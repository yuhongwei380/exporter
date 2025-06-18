#!/bin/bash
# must run as root role 
apt install -y wget jq git 
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
systemctl enable node_exporter.service
systemctl restart node_exporter.service
#systemctl status node_exporter.service
systemctl daemon-reload

bash /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom
(crontab -l; echo "*/30 * * * * /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom") | crontab -
