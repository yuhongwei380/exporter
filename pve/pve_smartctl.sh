#!/bin/bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
  data_percent=$(echo "$data_percent" | xargs | sed 's/%//')  # 移除百分号
  lv_size=$(echo "$lv_size" | xargs)
  
  # 提取纯数字（支持小数）
  size_value=$(echo "$lv_size" | grep -oE '[0-9.]+')
  
  # 检查是否成功提取数字
  if [ -z "$size_value" ]; then
    echo "错误：无法从 '$lv_size' 解析数字" >&2
    continue
  fi

  # 转换为字节（TB→字节）
  size_bytes=$(echo "$size_value * 1000000000000" | bc -l 2>/dev/null)
  
  # 检查计算是否成功
  if [ -z "$size_bytes" ]; then
    echo "错误：计算失败 '$size_value * 1000000000000'" >&2
    continue
  fi

  # 格式化为 Prometheus 指标格式
  echo "lvm_data_percent{lv_name=\"$lv_name\",lv_size=\"$size_bytes\"} $data_percent" > "$output_file"
done
