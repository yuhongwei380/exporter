#!/bin/bash
# must run as root role 
# judge the OS version 
if [ -f /etc/redhat-release ]; then
    echo "Detected CentOS/RHEL, installing wget jq with yum..."
    sudo yum install -y wget jq
elif [ -f /etc/debian_version ]; then
    echo "Detected Ubuntu/Debian, installing wget jq with apt..."
    sudo apt update
    sudo apt install -y wget jq
else
    echo "Unsupported OS! Only CentOS/RHEL/Ubuntu/Debian are supported."
    exit 1
fi

#install node exporter for ARM64
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-arm64.tar.gz
tar -xvf node_exporter-1.10.2.linux-arm64.tar.gz -C /root/

mv /root/node_exporter-1.10.2.linux-arm64 /root/node_exporter
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

# 清理可能遗留的 smartctl 相关文件和定时任务
rm -f /opt/smartctl.sh
rm -rf /var/lib/node_exporter/textfile_collector
crontab -l 2>/dev/null | grep -v "/opt/smartctl.sh" | crontab - 2>/dev/null || true

systemctl status node_exporter.service
