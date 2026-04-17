#!/bin/bash

# Wake-on-LAN 唤醒并验证脚本
# 用法: ./wake_and_verify.sh <主机名>

set -e

# 主机配置 (格式: MAC|IP)
declare -A HOSTS=(
    ["esxi200"]="22:02:4d:07:5c:7a|192.168.0.200"
    ["xp"]="1C:83:41:8A:4E:7B|192.168.0.225"
    ["r3600"]="2C:F0:5D:3D:27:87|192.168.0.198"
)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${RED}错误: 请指定主机名${NC}"
    echo "可用的主机:"
    for host in "${!HOSTS[@]}"; do
        IFS='|' read -ra INFO <<< "${HOSTS[$host]}"
        echo "  - $host (${INFO[1]})"
    done
    exit 1
fi

HOSTNAME=$1

# 检查是否为 "all"
if [ "$HOSTNAME" == "all" ]; then
    echo -e "${YELLOW}唤醒所有主机...${NC}"
    for host in "${!HOSTS[@]}"; do
        IFS='|' read -ra INFO <<< "${HOSTS[$host]}"
        MAC="${INFO[0]}"
        IP="${INFO[1]}"
        echo "唤醒 $host ($MAC)"
        wakeonlan "$MAC" > /dev/null 2>&1
    done
    echo -e "${GREEN}✓ 所有主机的唤醒包已发送${NC}"
    echo "请等待 1-3 分钟让主机启动，然后使用以下命令验证:"
    for host in "${!HOSTS[@]}"; do
        IFS='|' read -ra INFO <<< "${HOSTS[$host]}"
        echo "  ping -c 1 ${INFO[1]}  # $host"
    done
    exit 0
fi

# 验证主机名
if [[ ! -v HOSTS[$HOSTNAME] ]]; then
    echo -e "${RED}❌ 未找到主机: $HOSTNAME${NC}"
    echo "可用的主机:"
    for host in "${!HOSTS[@]}"; do
        IFS='|' read -ra INFO <<< "${HOSTS[$host]}"
        echo "  - $host (${INFO[1]})"
    done
    echo ""
    echo "提示: 使用 'all' 唤醒所有主机"
    exit 1
fi

# 解析主机信息
IFS='|' read -ra INFO <<< "${HOSTS[$HOSTNAME]}"
MAC="${INFO[0]}"
IP="${INFO[1]}"

echo -e "${YELLOW}唤醒主机: $HOSTNAME${NC}"
echo "  MAC地址: $MAC"
echo "  IP地址: $IP"
echo ""

# 检查主机当前状态
echo "检查主机当前状态..."
if ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 主机 $HOSTNAME 已经在线！${NC}"
    exit 0
fi

# 发送唤醒包
echo "发送 Wake-on-LAN 魔术包..."
if ! wakeonlan "$MAC" > /dev/null 2>&1; then
    echo -e "${RED}✗ 发送唤醒包失败${NC}"
    echo "请检查 wakeonlan 是否已安装: sudo apt install wakeonlan"
    exit 1
fi

echo -e "${GREEN}✓ 唤醒包已发送${NC}"
echo ""

# 验证启动
echo "等待主机启动（最长 3 分钟）..."
MAX_WAIT=180  # 最长等待 3 分钟
INTERVAL=10   # 每 10 秒检查一次
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))

    printf "[$3ds] 检查主机状态..." "$ELAPSED"

    if ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
        echo -e " ${GREEN}在线${GREEN}"
        echo ""
        echo -e "${GREEN}✓ 主机 $HOSTNAME 已成功启动！${NC}"
        echo "  启动耗时: ${ELAPSED} 秒"
        echo "  IP地址: $IP"
        exit 0
    else
        echo -e " ${YELLOW}离线${NC}"
    fi
done

echo ""
echo -e "${RED}✗ 主机 $HOSTNAME 启动超时${NC}"
echo "可能的原因:"
echo "  1. 主机未配置 WOL"
echo "  2. 主机完全断电"
echo "  3. 网络问题"
echo "  4. 启动时间超过 3 分钟"
echo ""
echo "请手动检查主机状态: ping -c 1 $IP"
exit 1
