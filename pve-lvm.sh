#!/bin/bash

# 提取逻辑卷名称、Data% 和 Size 字段
output=$(lvs --noheadings --separator ',' -o lv_name,data_percent,lv_size | grep "vm-data")

# 指定输出文件路径
output_file="/var/lib/node_exporter/textfile_collector/pve-lvm.prom"

# 清空输出文件
> "$output_file"

# 逐行处理输出
echo "$output" | while IFS=',' read -r lv_name data_percent lv_size; do
  # 去掉前后的空格
  lv_name=$(echo "$lv_name" | xargs)
  data_percent=$(echo "$data_percent" | xargs)
  lv_size=$(echo "$lv_size" | xargs)
  size_value=$(echo "$lv_size" | sed 's/t//g')
  size_value=$(echo "$size_value * 1000000000000" | bc)

  # 格式化为 Prometheus 指标格式
  echo "lvm_data_percent{lv_name=\"$lv_name\",lv_size=\"$size_value\"} $data_percent" >> "$output_file"
done
