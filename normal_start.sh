#!/bin/bash

# 检测操作系统类型
OS=$(uname -s)

# 根据操作系统类型执行不同的安装命令
if [ "$OS" = "Linux" ]; then
    # 检测发行版
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu 系列
        sudo apt update
        sudo apt install -y jq smartmontools
    elif [ -f /etc/redhat-release ]; then
        # RedHat/CentOS 系列
        sudo yum install -y epel-release
        sudo yum install -y jq smartmontools
    else
        echo "Unsupported Linux distribution"
        exit 1
    fi
else
    echo "Unsupported OS"
    exit 1
fi

# 创建目录和设置权限
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chmod a+x /opt/exporter/*.sh

# 创建 Prometheus 文件
sudo touch /var/lib/node_exporter/textfile_collector/smartctl.prom

# 设置定时任务
(sudo crontab -l; echo "*/30 * * * * /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom") | sudo crontab -

# 立即运行脚本
bash /opt/exporter/smartctl.sh > /var/lib/node_exporter/textfile_collector/smartctl.prom
