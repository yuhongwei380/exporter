#!/usr/bin/env bash

#set -eu
#set -x    #debug mode

# Ensure predictable numeric / date formats, etc.
export LC_ALL=C

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

# Get NVMe devices
device_list=$(lsblk -d -n -o NAME | grep -E '^nvme')

# Loop through the NVMe devices
for disk in ${device_list}; do
  device="/dev/${disk}"
  smartctl_output=$(smartctl -a -j "${device}") || { echo "Failed to get smartctl output for ${device}"; continue; }
  smartctl_health=$(smartctl -H "${device}") || { echo "Failed to get smartctl health for ${device}"; continue; }
  smartctl_output_capacity=$(smartctl -i "${device}") || { echo "Failed to get smartctl capacity for ${device}"; continue; }

  disk="${device##*/}"

  #-------------------------全局通用指标-------------------------
  echo "device{device=\"${disk}\"} 1"

  # 获取磁盘的 model name
  value_model_name=$(echo "$smartctl_output" | jq -r '.model_name')
  if [ -z "$value_model_name" ]; then
    value_model_name="unknown"
  fi
  echo "model_name{device=\"${disk}\", model_name=\"${value_model_name}\"} 1"

  #-------------------------nvme设备指标-------------------------
  # NVMe disk (nvme*)
  value_disk_health=$(echo "$smartctl_health" | grep 'result' | awk '{print $6}')
  if [[ "$value_disk_health" == "PASSED" ]]; then
    health_status="PASSED"
    health_value=1
  elif [[ "$value_disk_health" == "FAILED" ]]; then
    health_status="FAILED"
    health_value=0
  else
    health_status="UNKNOWN"
    health_value=0
  fi
  echo "nvme_health{device=\"${disk}\", status=\"${health_status}\"} ${health_value}"

  value_nvme_temperature=$(echo "$smartctl_output" | jq '.temperature.current')
  if [ -n "$value_nvme_temperature" ]; then
    echo "nvme_current_temperature{device=\"${disk}\"} ${value_nvme_temperature}"
  fi

  # 获取磁盘的容量
  value_User_Capacity=$(echo "$smartctl_output_capacity" | grep "Namespace 1 Size/Capacity" | awk '{print $4}' | tr -d ',')
  if [ -z "$value_User_Capacity" ]; then
    value_User_Capacity="unknown"
  fi
  echo "User_Capacity{device=\"${disk}\", User_Capacity=\"${value_User_Capacity}\"} 1"

  value_power_on_time=$(echo "$smartctl_output" | jq '.power_on_time.hours')
  if [ -n "$value_power_on_time" ]; then
    echo "nvme_disk_power_on_time{device=\"${disk}\"} ${value_power_on_time}"
  fi

  value_available_spare=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.available_spare / 100')
  if [ -n "$value_available_spare" ]; then
    echo "nvme_available_spare_ratio{device=\"${disk}\"} ${value_available_spare}"
  fi

  value_available_spare_threshold=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.available_spare_threshold / 100')
  if [ -n "$value_available_spare_threshold" ]; then
    echo "nvme_available_spare_threshold_ratio{device=\"${disk}\"} ${value_available_spare_threshold}"
  fi

  value_percentage_used=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.percentage_used / 100')
  if [ -n "$value_percentage_used" ]; then
    echo "nvme_percentage_used{device=\"${disk}\"} ${value_percentage_used}"
  fi

  value_critical_warning=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.critical_warning')
  if [ -n "$value_critical_warning" ]; then
    echo "nvme_critical_warning_total{device=\"${disk}\"} ${value_critical_warning}"
  fi

  value_media_errors=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.media_errors')
  if [ -n "$value_media_errors" ]; then
    echo "nvme_media_errors_total{device=\"${disk}\"} ${value_media_errors}"
  fi

  value_num_err_log_entries=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.num_err_log_entries')
  if [ -n "$value_num_err_log_entries" ]; then
    echo "nvme_num_err_log_entries_total{device=\"${disk}\"} ${value_num_err_log_entries}"
  fi

  value_power_cycles=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.power_cycles')
  if [ -n "$value_power_cycles" ]; then
    echo "nvme_power_cycles_total{device=\"${disk}\"} ${value_power_cycles}"
  fi

  value_power_on_hours=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.power_on_hours')
  if [ -n "$value_power_on_hours" ]; then
    echo "nvme_power_on_hours_total{device=\"${disk}\"} ${value_power_on_hours}"
  fi

  value_controller_busy_time=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.controller_busy_time')
  if [ -n "$value_controller_busy_time" ]; then
    echo "nvme_controller_busy_time_seconds{device=\"${disk}\"} ${value_controller_busy_time}"
  fi

  value_data_units_written=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.data_units_written')
  if [ -n "$value_data_units_written" ]; then
    echo "nvme_data_units_written_total{device=\"${disk}\"} ${value_data_units_written}"
  fi

  value_data_units_read=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.data_units_read')
  if [ -n "$value_data_units_read" ]; then
    echo "nvme_data_units_read_total{device=\"${disk}\"} ${value_data_units_read}"
  fi

  value_host_read_commands=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.host_reads')
  if [ -n "$value_host_read_commands" ]; then
    echo "nvme_host_read_commands_total{device=\"${disk}\"} ${value_host_read_commands}"
  fi

  value_host_write_commands=$(echo "$smartctl_output" | jq '.nvme_smart_health_information_log.host_writes')
  if [ -n "$value_host_write_commands" ]; then
    echo "nvme_host_write_commands_total{device=\"${disk}\"} ${value_host_write_commands}"
  fi

done | format_output
