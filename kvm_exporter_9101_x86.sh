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
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar -xvf node_exporter-1.10.2.linux-amd64.tar.gz -C /root/

mv  /root/node_exporter-1.10.2.linux-amd64   /root/node_exporter
chown -R prometheus.prometheus /root/node_exporter/
sudo cp -a /root/node_exporter/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

cat << EOF >/usr/lib/systemd/system/node_exporter.service 
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=:9101 \
    --collector.filesystem.ignored-mount-points="^/(sys|proc|dev|etc|run|boot|var/lib/docker/overlay2|run/docker/netns|var/lib/docker/aufs)($|/)"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter.service
systemctl restart node_exporter.service

systemctl status node_exporter.service
