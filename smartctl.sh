#!/usr/bin/env bash
#
# Dependencies: nvme-cli, jq (packages)
# Based on code from
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/smartmon.sh
# - https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/mellanox_hca_temp
# - https://github.com/vorlon/check_nvme/blob/master/check_nvme.sh
#
# Author: Henk <henk@wearespindle.com>

set -eu
#set -x    #debug mode

# Ensure predictable numeric / date formats, etc.
export LC_ALL=C

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
device_list="$(lsblk -d -n -o NAME | grep -E '^' | grep -v 'loop')"

# Loop through the NVMe devices
for disk in ${device_list}; do
  device="/dev/${disk}"
  smartctl_output="$(smartctl -a -j ${device})"
  smartctl_health="$(smartctl -H ${device})"
  smartctl_output_capacity="$(smartctl -i ${device})"

  disk="${device##*/}"


  if [[ "$disk" == sd* ]]; then
  # Mechanical disk (sd*)
  # Parse JSON output from smartctl
  value_temperature="$(echo "$smartctl_output" | jq '.temperature.current')"
  echo "sata_current_temperature{device=\"${disk}\"} ${value_temperature}"

  # 获取硬盘健康状态
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
  echo "sata_health{device=\"${disk}\", status=\"${health_status}\"} ${health_value}"

  #获取磁盘的model name
  value_model_name="$(echo "$smartctl_output" | jq -r  '.model_name')"
  model_name=1
  echo "sata_model_name{device=\"${disk}\", model_name=\"${value_model_name}\"} ${model_name}"
  
  #获取磁盘的容量
  value_User_Capacity="$(echo "$smartctl_output_capacity" | grep "User Capacity" | awk '{print $3}')"
  echo "sata_User_Capacity{device=\"${disk}\"} ${value_User_Capacity}"

  value_disk_Power_On_Hours="$(echo "$smartctl_output" | jq '.ata_smart_attributes.table[] | select(.id == 9) | .raw.value')"
  echo "sata_Power_On_Hours{device=\"${disk}\"} ${value_disk_Power_On_Hours}"
  
  #Reallocated_Sector_Ct：这是已经重新分配的扇区的数量。如果该值不为0，则磁盘存在坏扇区。正常情况的RAW_VALUE为0
  value_disk_Reallocated_Sector_Ct="$(echo "$smartctl_output" | jq '.ata_smart_attributes.table[] | select(.id == 5) | .raw.value')"
  echo "sata_Reallocated_Sector_Ct{device=\"${disk}\"} ${value_disk_Reallocated_Sector_Ct}"

  value_disk_Offline_Uncorrectable="$(echo "$smartctl_output" | jq '.ata_smart_attributes.table[] | select(.id == 198) | .raw.value')"
  echo "sata_Offline_Uncorrectable{device=\"${disk}\"} ${value_disk_Offline_Uncorrectable}"


  elif [[ "$disk" == nvme* ]]; then
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

  #获取磁盘的model name
  value_nvme_model_name="$(echo "$smartctl_output" | jq -r  '.model_name')"
  nvme_model_name=1
  echo "nvme_model_name{device=\"${disk}\", model_name=\"${value_nvme_model_name}\"} ${nvme_model_name}"

  #获取磁盘的容量
  value_nvme_User_Capacity="$(echo "$smartctl_output_capacity" | grep "Total NVM Capacity"  | awk '{print $4}')"
  echo "nvme_User_Capacity{device=\"${disk}\"} ${value_nvme_User_Capacity}"

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
