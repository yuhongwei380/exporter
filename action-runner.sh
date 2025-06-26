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
