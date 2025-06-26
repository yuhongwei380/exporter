#!/bin/bash
# must run as root role 
# Only use in th Github Action CI
touch /var/lib/node_exporter/textfile_collector/action-runner.prom

sudo tee /opt/action-runner.sh <<'EOF'
#!/bin/bash

# 进入工作目录
cd /home/vesoft/actions-runner || exit 1

# 执行状态检查（根据实际输出判断）
status=$(sudo ./svc.sh status)

# 如果你想调试，可以取消下面这行的注释：
# echo "$status"

if echo "$status" | grep -q "running"; then
    echo "action_runner_status{status=\"running\"} 1"
else
    echo "action_runner_status{status=\"dead\"} 0"
fi
EOF


chmod a+x /opt/action-runner.sh
bash /opt/action-runner.sh > /var/lib/node_exporter/textfile_collector/action-runner.prom
(crontab -l; echo "*/5 * * * * /opt/action-runner.sh > /var/lib/node_exporter/textfile_collector/action-runner.prom") | crontab -
