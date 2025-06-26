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
tar -xvf node_exporter-1.9.1.linux-amd64.tar.gz -C /root/

mv  /root/node_exporter-1.9.1.linux-amd64   /root/node_exporter
chown -R prometheus.prometheus /root/node_exporter/
sudo cp -a /root/node_exporter/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

mkdir -p /var/lib/node_exporter/textfile_collector/
touch /var/lib/node_exporter/textfile_collector/smartctl.prom
cat << EOF >/usr/lib/systemd/system/node_exporter.service 
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=:9101 \
    --collector.filesystem.ignored-mount-points="^/(sys|proc|dev|etc|run|boot|var/lib/docker/overlay2|run/docker/netns|var/lib/docker/aufs)($|/)" \
    --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable node_exporter.service
systemctl restart node_exporter.service


sudo tee /opt/nvme-smartctl.sh <<'EOF'
#!/usr/bin/env bash


#set -eu
#set -x    #debug mode

# Ensure predictable numeric / date formats, etc.
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Check if we are root
# if [ "$EUID" -ne 0 ]; then
#   echo "${0##*/}: Please run as root!" >&2
#   exit 1
# fi

output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP disk_" $1 " SMART metric " $1;
  if ($1 ~ /_total$/)
    print "# TYPE disk_" $1 " counter";
  else
    print "# TYPE disk_" $1 " gauge";
  v = $1
}
{print "disk_" $0}
OUTPUTAWK
)"

format_output() {
  sort | awk -F'{' "${output_format_awk}"
}

# Get devices
device_list="$(lsblk -d -n -o NAME | grep -E '^' | grep -v 'loop'|grep -v 'sd*')"

# Loop through the NVMe devices
for disk in ${device_list}; do
  device="/dev/${disk}"
  smartctl_output="$(smartctl -a -j ${device})"
  smartctl_health="$(smartctl -H ${device})"
  smartctl_output_capacity="$(smartctl -i ${device})"

  disk="${device##*/}"

  #-------------------------全局通用指标-------------------------
  value_device="$device"
  echo "device{device=\"${disk}\"} 1"

    #获取磁盘的model name
  value_model_name="$(echo "$smartctl_output" | jq -r  '.model_name')"
  model_name_value=1  #此处1无意义，只是单纯传输，以满足node-exporter采集的要求。
  echo "model_name{device=\"${disk}\", model_name=\"${value_model_name}\"} ${model_name_value}"

  #-------------------------全局通用指标-------------------------

  #-------------------------nvme设备指标-------------------------
  if [[ "$disk" == nvme* ]]; then
  # NVMe disk (nvme*)
  value_disk_health="$(echo "$smartctl_health" | grep 'result' | awk '{print $6}')"
    # 设置健康状态和对应的值
        if [[ "$value_disk_health" == "PASSED" ]]; then
        health_status="PASSED"
        health_value=1
        elif [[ "$value_disk_health" == "FAILED" ]]; then
        health_status="FAILED"
        health_value=0
        else
        health_status="UNKNOWN"
        health_value=0  # 其他情况也设为 0
        fi
    # 输出健康状态，使用字符串作为标签
  echo "nvme_health{device=\"${disk}\", status=\"${health_status}\"} ${health_value}"

  value_nvme_temperature="$(echo "$smartctl_output" | jq '.temperature.current')"
  echo "nvme_current_temperature{device=\"${disk}\"} ${value_nvme_temperature}"

  # #获取磁盘的容量
  value_User_Capacity="$(echo "$smartctl_output_capacity" | grep "Namespace 1 Size/Capacity"  | awk '{print $4}'| tr -d ',')"
  nvme_User_Capacity=1
  echo "User_Capacity{device=\"${disk}\", User_Capacity=\"${value_User_Capacity}\"} ${nvme_User_Capacity}"


  value_power_on_time="$(echo "$smartctl_output" | jq '.power_on_time.hours')"
  echo "nvme_disk_power_on_time{device=\"${disk}\"} ${value_power_on_time}"

  value_available_spare="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.available_spare / 100')"
  echo "nvme_available_spare_ratio{device=\"${disk}\"} ${value_available_spare}"

  value_available_spare_threshold="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.available_spare_threshold / 100')"
  echo "nvme_available_spare_threshold_ratio{device=\"${disk}\"} ${value_available_spare_threshold}"

  value_percentage_used="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.percentage_used / 100')"
  echo "nvme_percentage_used{device=\"${disk}\"} ${value_percentage_used}"

  value_critical_warning="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.critical_warning')"
  echo "nvme_critical_warning_total{device=\"${disk}\"} ${value_critical_warning}"

  value_media_errors="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.media_errors')"
  echo "nvme_media_errors_total{device=\"${disk}\"} ${value_media_errors}"

  value_num_err_log_entries="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.num_err_log_entries')"
  echo "nvme_num_err_log_entries_total{device=\"${disk}\"} ${value_num_err_log_entries}"

  value_power_cycles="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.power_cycles')"
  echo "nvme_power_cycles_total{device=\"${disk}\"} ${value_power_cycles}"

  value_power_on_hours="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.power_on_hours')"
  echo "nvme_power_on_hours_total{device=\"${disk}\"} ${value_power_on_hours}"

  value_controller_busy_time="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.controller_busy_time')"
  echo "nvme_controller_busy_time_seconds{device=\"${disk}\"} ${value_controller_busy_time}"

  value_data_units_written="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.data_units_written')"
  echo "nvme_data_units_written_total{device=\"${disk}\"} ${value_data_units_written}"

  value_data_units_read="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.data_units_read')"
  echo "nvme_data_units_read_total{device=\"${disk}\"} ${value_data_units_read}"

  value_host_read_commands="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.host_reads')"
  echo "nvme_host_read_commands_total{device=\"${disk}\"} ${value_host_read_commands}"

  value_host_write_commands="$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.host_writes')"
  echo "nvme_host_write_commands_total{device=\"${disk}\"} ${value_host_write_commands}"

  fi

done | format_output

EOF
chmod a+x /opt/nvme-smartctl.sh
bash /opt/nvme-smartctl.sh > /var/lib/node_exporter/textfile_collector/nvme-smartctl.prom
(crontab -l; echo "*/30 * * * * /opt/nvme-smartctl.sh > /var/lib/node_exporter/textfile_collector/nvme-smartctl.prom") | crontab -

systemctl status node_exporter.service