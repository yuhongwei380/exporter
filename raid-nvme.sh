#!/usr/bin/env bash

# Ensure predictable numeric / date formats, etc.
export LC_ALL=C

# 定义解析 smartctl 属性的 awk 脚本
parse_smartctl_attributes_awk="$(
  cat <<'SMARTCTLAWK'
$1 ~ /^ *[0-9]+$/ && $2 ~ /^[a-zA-Z0-9_-]+$/ {
  gsub(/-/, "_");
  printf "%s_value{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $4
  printf "%s_worst{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $5
  printf "%s_threshold{%s,smart_id=\"%s\"} %d\n", $2, labels, $1, $6
  printf "%s_raw_value{%s,smart_id=\"%s\"} %e\n", $2, labels, $1, $10
}
SMARTCTLAWK
)"

# 定义 SMART 属性列表
smartmon_attrs="$(
  cat <<'SMARTMONATTRS'
airflow_temperature_cel
command_timeout
current_pending_sector
end_to_end_error
erase_fail_count
g_sense_error_rate
hardware_ecc_recovered
host_reads_32mib
host_reads_mib
host_writes_32mib
host_writes_mib
load_cycle_count
media_wearout_indicator
nand_writes_1gib
offline_uncorrectable
power_cycle_count
power_on_hours
program_fail_cnt_total
program_fail_count
raw_read_error_rate
reallocated_event_count
reallocated_sector_ct
reported_uncorrect
runtime_bad_block
sata_downshift_count
seek_error_rate
spin_retry_count
spin_up_time
start_stop_count
temperature_case
temperature_celsius
temperature_internal
total_lbas_read
total_lbas_written
udma_crc_error_count
unsafe_shutdown_count
unused_rsvd_blk_cnt_tot
wear_leveling_count
workld_host_reads_perc
workld_media_wear_indic
workload_minutes
SMARTMONATTRS
)"
smartmon_attrs="$(echo "${smartmon_attrs}" | xargs | tr ' ' '|')"

# 解析 smartctl 属性
parse_smartctl_attributes() {
  local disk="$1"
  local disk_type="$2"
  local labels="disk=\"${disk}\",type=\"${disk_type}\""
  sed 's/^ \+//g' |
    awk -v labels="${labels}" "${parse_smartctl_attributes_awk}" 2>/dev/null |
    tr '[:upper:]' '[:lower:]' |
    grep -E "(${smartmon_attrs})"
}

# 解析 SCSI 属性
parse_smartctl_scsi_attributes() {
  local disk="$1"
  local disk_type="$2"
  local labels="disk=\"${disk}\",type=\"${disk_type}\""
  while read -r line; do
    attr_type="$(echo "${line}" | tr '=' ':' | cut -f1 -d: | sed 's/^ \+//g' | tr ' ' '_')"
    attr_value="$(echo "${line}" | tr '=' ':' | cut -f2 -d: | sed 's/^ \+//g')"
    case "${attr_type}" in
    number_of_hours_powered_up_) power_on="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Current_Drive_Temperature) temp_cel="$(echo "${attr_value}" | cut -f1 -d' ' | awk '{ printf "%e\n", $1 }')" ;;
    Blocks_sent_to_initiator_) lbas_read="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Blocks_received_from_initiator_) lbas_written="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Accumulated_start-stop_cycles) power_cycle="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    Elements_in_grown_defect_list) grown_defects="$(echo "${attr_value}" | awk '{ printf "%e\n", $1 }')" ;;
    esac
  done
  [ -n "$power_on" ] && echo "power_on_hours_raw_value{${labels},smart_id=\"9\"} ${power_on}"
  [ -n "$temp_cel" ] && echo "temperature_celsius_raw_value{${labels},smart_id=\"194\"} ${temp_cel}"
  [ -n "$lbas_read" ] && echo "total_lbas_read_raw_value{${labels},smart_id=\"242\"} ${lbas_read}"
  [ -n "$lbas_written" ] && echo "total_lbas_written_raw_value{${labels},smart_id=\"241\"} ${lbas_written}"
  [ -n "$power_cycle" ] && echo "power_cycle_count_raw_value{${labels},smart_id=\"12\"} ${power_cycle}"
  [ -n "$grown_defects" ] && echo "grown_defects_count_raw_value{${labels},smart_id=\"-1\"} ${grown_defects}"
}

# 解析 smartctl 信息
parse_smartctl_info() {
  local -i smart_available=0 smart_enabled=0 smart_healthy=
  local disk="$1" disk_type="$2"
  local model_family='' device_model='' serial_number='' fw_version='' vendor='' product='' revision='' lun_id=''
  while read -r line; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/"/\\"/')"
    case "${info_type}" in
    Model_Family) model_family="${info_value}" ;;
    Device_Model) device_model="${info_value}" ;;
    Serial_Number|Serial_number) serial_number="${info_value}" ;;
    Firmware_Version) fw_version="${info_value}" ;;
    Vendor) vendor="${info_value}" ;;
    Product) product="${info_value}" ;;
    Revision) revision="${info_value}" ;;
    Logical_Unit_id) lun_id="${info_value}" ;;
    esac
    if [[ "${info_type}" == 'SMART_support_is' ]]; then
      case "${info_value:0:7}" in
      Enabled) smart_available=1; smart_enabled=1 ;;
      Availab) smart_available=1; smart_enabled=0 ;;
      Unavail) smart_available=0; smart_enabled=0 ;;
      esac
    fi
    if [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]]; then
      case "${info_value:0:6}" in
      PASSED) smart_healthy=1 ;;
      *) smart_healthy=0 ;;
      esac
    elif [[ "${info_type}" == 'SMART_Health_Status' ]]; then
      case "${info_value:0:2}" in
      OK) smart_healthy=1 ;;
      *) smart_healthy=0 ;;
      esac
    fi
  done
  echo "device_info{disk=\"${disk}\",type=\"${disk_type}\",vendor=\"${vendor}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",model_family=\"${model_family}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",firmware_version=\"${fw_version}\"} 1"
  echo "device_smart_available{disk=\"${disk}\",type=\"${disk_type}\"} ${smart_available}"
  echo "device_smart_enabled{disk=\"${disk}\",type=\"${disk_type}\"} ${smart_enabled}"
  [[ "${smart_healthy}" != "" ]] && echo "device_smart_healthy{disk=\"${disk}\",type=\"${disk_type}\"} ${smart_healthy}"
}

# 格式化输出的 awk 脚本
output_format_awk="$(
  cat <<'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP disk_" $1 " SMART metric " $1;
  print "# TYPE disk_" $1 " gauge";
  v = $1
}
{print "disk_" $0}
OUTPUTAWK
)"

format_output() {
  sort |
    awk -F'{' "${output_format_awk}"
}

# 获取 smartctl 版本
smartctl_version="$(/usr/sbin/smartctl -V | head -n1 | awk '$1 == "smartctl" {print $2}')"

echo "smartctl_version{version=\"${smartctl_version}\"} 1" | format_output

if [[ "$(expr "${smartctl_version}" : '\([0-9]*\)\..*')" -lt 6 ]]; then
  exit
fi

# 获取设备列表
device_list="$(/usr/sbin/smartctl --scan-open | awk '/^\/dev/{print $1 "|" $3}')"

for device in ${device_list}; do
  disk="$(echo "${device}" | cut -f1 -d'|')"
  type="$(echo "${device}" | cut -f2 -d'|')"
  active=1
  echo "smartctl_run{disk=\"${disk}\",type=\"${type}\"}" "$(TZ=UTC date '+%s')"
  # 检查设备是否处于低功耗模式
  /usr/sbin/smartctl -n standby -d "${type}" "${disk}" > /dev/null || active=0
  echo "device_active{disk=\"${disk}\",type=\"${type}\"}" "${active}"
  # 跳过进一步的指标以防止磁盘旋转
  test ${active} -eq 0 && continue
  # 获取 SMART 信息和健康状态
  /usr/sbin/smartctl -i -H -d "${type}" "${disk}" | parse_smartctl_info "${disk}" "${type}"
  # 获取 SMART 属性
  case ${type} in
  sat) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" ;;
  sat+megaraid*) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" ;;
  scsi) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${disk}" "${type}" ;;
  megaraid*) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_scsi_attributes "${disk}" "${type}" ;;
  nvme*)
    
    smartctl_output="$(smartctl -a -j ${disk})"
    smartctl_health="$(smartctl -H ${disk})"
    smartctl_output_capacity="$(smartctl -i ${disk})"

    #-------------------------全局通用指标-------------------------
    value_device="$disk"
    echo "device{device=\"${disk}\"} 1"

    #获取磁盘的model name
    value_model_name="$(echo "$smartctl_output" | jq -r  '.model_name')"
    model_name_value=1  #此处1无意义，只是单纯传输，以满足node-exporter采集的要求。
    echo "model_name{device=\"${disk}\", model_name=\"${value_model_name}\"} ${model_name_value}"

    #-------------------------全局通用指标-------------------------

    #-------------------------nvme设备指标-------------------------
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

    # 获取磁盘的容量
    value_User_Capacity="$(echo "$smartctl_output_capacity" | grep -E "Total NVM Capacity"  | awk '{print $4}'| tr -d ',')"
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
    ;;
  usbprolific) /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}" ;;
  *)
    (>&2 echo "disk type is not sat, scsi, nvme or megaraid but ${type}")
    exit
    ;;
  esac
done | format_output
