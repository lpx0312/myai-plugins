#!/bin/sh

KEYWORD="$1"
SNAPSHOT_NAME="$2"

if [ -z "$KEYWORD" ]; then
  echo "Usage: $0 <IP or VM_NAME> [SNAPSHOT_NAME]"
  exit 1
fi

# 如果快照名称为空，使用时间戳
if [ -z "$SNAPSHOT_NAME" ]; then
  SNAPSHOT_NAME=$(date +"%Y%m%d_%H%M%S")
  echo ">>> 未指定快照名称，使用时间戳: $SNAPSHOT_NAME"
fi

echo ">>> 为虚拟机 [$KEYWORD] 创建快照 [$SNAPSHOT_NAME]"

# 获取 VMID
VM_LINE=$(vim-cmd vmsvc/getallvms | grep -w "$KEYWORD")

if [ -z "$VM_LINE" ]; then
  echo ">>> 未找到虚拟机: $KEYWORD"
  exit 1
fi

VMID=$(echo "$VM_LINE" | awk '{print $1}')

echo ">>> VMID: $VMID"

# 创建快照
# vim-cmd vmsvc/snapshot.create <vmid> <snapshot_name> <description> <memory> <quiesce>
vim-cmd vmsvc/snapshot.create $VMID "$SNAPSHOT_NAME" "Auto snapshot at $(date '+%Y-%m-%d %H:%M:%S')" 0 0

if [ $? -eq 0 ]; then
  echo ">>> 快照 [$SNAPSHOT_NAME] 创建成功"
else
  echo ">>> 快照创建失败"
  exit 1
fi
