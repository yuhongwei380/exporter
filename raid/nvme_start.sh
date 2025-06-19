#!/bin/bash
sudo apt install jq  smartmontools -y  # nvme-cli
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chmod a+x /opt/exporter/*.sh
sudo touch /var/lib/node_exporter/textfile_collector/smartctl.prom
(sudo crontab -l; echo "*/30 * * * * /opt/exporter/nvme.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom") | sudo crontab -
bash /opt/exporter/nvme.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom
