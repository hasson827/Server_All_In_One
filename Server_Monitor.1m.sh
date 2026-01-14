#!/bin/bash

# ================= 配置区域 =================
HOST="user@your_server_ip"
PORT="your_server_port"
ID_FILE="Your rsa file"
# ===========================================

SSH_CMD="/usr/bin/ssh -p $PORT -i $ID_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=5"

# 颜色定义
COLOR_GREEN=""
COLOR_YELLOW=" | color=#FFD60A"
COLOR_RED=" | color=red"

# 状态统计
OVERALL_STATUS="green"
STATUS_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0

# 执行远程命令并获取所有数据
REMOTE_OUTPUT=$($SSH_CMD $HOST "
# CPU信息
echo '===CPU==='
top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - \$1}'
echo '===LOAD==='
cat /proc/loadavg
echo '===RAM==='
free -m
echo '===GPU==='
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.free,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 'NO_GPU'
echo '===DISK==='
df -h | grep -E '^/dev/' | head -5
iostat -d 1 2 2>/dev/null | tail -n +4 | head -5 || echo 'NO_IOSTAT'
" 2>&1)

# 检查连接是否成功
if [ $? -ne 0 ] || [ -z "$REMOTE_OUTPUT" ]; then
  echo "🔴 Server: Offline | color=red"
  echo "---"
  echo "❌ Error: ${REMOTE_OUTPUT:0:100}..."
  echo "---"
  echo "🔄 Refresh All | refresh=true"
  echo "🖥️ Open Terminal | shell=ssh terminal=true"
  exit 0
fi

# 解析数据
parse_section() {
  echo "$REMOTE_OUTPUT" | sed -n "/^===${1}===/,/^===/p" | tail -n +2 | sed '$d'
}

# ========== CPU模块 ==========
parse_cpu() {
  CPU_USAGE=$(parse_section "CPU" | head -n 1)
  LOAD_INFO=$(parse_section "LOAD" | head -n 1)
  
  # 解析负载
  LOAD_1M=$(echo $LOAD_INFO | awk '{print $1}')
  LOAD_5M=$(echo $LOAD_INFO | awk '{print $2}')
  LOAD_15M=$(echo $LOAD_INFO | awk '{print $3}')
  
  # 状态判定 - 使用整数比较避免bc依赖
  CPU_USAGE=${CPU_USAGE:-0}
  CPU_USAGE_INT=${CPU_USAGE%.*}  # 取整数部分
  
  if [ -z "$CPU_USAGE_INT" ]; then
    CPU_USAGE_INT=0
  fi
  
  if [ "$CPU_USAGE_INT" -lt 50 ]; then
    CPU_STATUS="green"
    CPU_ICON="🟢"
    CPU_COLOR=$COLOR_GREEN
  elif [ "$CPU_USAGE_INT" -lt 80 ]; then
    CPU_STATUS="yellow"
    CPU_ICON="🟡"
    CPU_COLOR=$COLOR_YELLOW
    ((WARNING_COUNT++))
  else
    CPU_STATUS="red"
    CPU_ICON="🔴"
    CPU_COLOR=$COLOR_RED
    ((ERROR_COUNT++))
  fi
  ((STATUS_COUNT++))
  
  # 更新总体状态
  if [ "$CPU_STATUS" = "red" ] && [ "$OVERALL_STATUS" != "red" ]; then
    OVERALL_STATUS="red"
  elif [ "$CPU_STATUS" = "yellow" ] && [ "$OVERALL_STATUS" = "green" ]; then
    OVERALL_STATUS="yellow"
  fi
}

# ========== RAM模块 ==========
parse_ram() {
  RAM_DATA=$(parse_section "RAM" | grep "^Mem:")
  TOTAL=$(echo "$RAM_DATA" | awk '{print $2}')
  USED=$(echo "$RAM_DATA" | awk '{print $3}')
  AVAILABLE=$(echo "$RAM_DATA" | awk '{print $7}')
  
  # 检查数据有效性
  if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ]; then
    TOTAL=1
    USED=0
    AVAILABLE=0
  fi
  
  USAGE_PERCENT=$(( USED * 100 / TOTAL ))
  
  if [ $USAGE_PERCENT -lt 70 ]; then
    RAM_STATUS="green"
    RAM_ICON="🟢"
    RAM_COLOR=$COLOR_GREEN
  elif [ $USAGE_PERCENT -lt 90 ]; then
    RAM_STATUS="yellow"
    RAM_ICON="🟡"
    RAM_COLOR=$COLOR_YELLOW
    ((WARNING_COUNT++))
  else
    RAM_STATUS="red"
    RAM_ICON="🔴"
    RAM_COLOR=$COLOR_RED
    ((ERROR_COUNT++))
  fi
  ((STATUS_COUNT++))
  
  # 更新总体状态
  if [ "$RAM_STATUS" = "red" ] && [ "$OVERALL_STATUS" != "red" ]; then
    OVERALL_STATUS="red"
  elif [ "$RAM_STATUS" = "yellow" ] && [ "$OVERALL_STATUS" = "green" ]; then
    OVERALL_STATUS="yellow"
  fi
}

# ========== GPU模块 ==========
parse_gpu() {
  GPU_DATA=$(parse_section "GPU")
  
  if echo "$GPU_DATA" | grep -q "NO_GPU" || [ -z "$GPU_DATA" ]; then
    GPU_STATUS="gray"
    GPU_ICON="⚪"
    GPU_COLOR=" | color=gray"
    GPU_FREE_COUNT=0
    GPU_TOTAL_COUNT=0
  else
    GPU_COUNT=$(echo "$GPU_DATA" | wc -l | xargs)
    GPU_TOTAL_COUNT=$GPU_COUNT
    GPU_FREE_COUNT=0
    
    while IFS= read -r line; do
      UTIL=$(echo "$line" | awk -F', ' '{print $3}')
      MEM_FREE=$(echo "$line" | awk -F', ' '{print $4}')
      
      # 确保数值有效
      UTIL=${UTIL:-0}
      MEM_FREE=${MEM_FREE:-0}
      
      if [ "$UTIL" -lt 5 ] && [ "$MEM_FREE" -gt 4000 ]; then
        ((GPU_FREE_COUNT++))
      fi
    done <<< "$GPU_DATA"
    
    if [ $GPU_FREE_COUNT -eq $GPU_TOTAL_COUNT ]; then
      GPU_STATUS="green"
      GPU_ICON="🟢"
      GPU_COLOR=$COLOR_GREEN
    elif [ $GPU_FREE_COUNT -gt 0 ]; then
      GPU_STATUS="yellow"
      GPU_ICON="🟡"
      GPU_COLOR=$COLOR_YELLOW
      ((WARNING_COUNT++))
    else
      GPU_STATUS="red"
      GPU_ICON="🔴"
      GPU_COLOR=$COLOR_RED
      ((ERROR_COUNT++))
    fi
    ((STATUS_COUNT++))
    
    # 更新总体状态
    if [ "$GPU_STATUS" = "red" ] && [ "$OVERALL_STATUS" != "red" ]; then
      OVERALL_STATUS="red"
    elif [ "$GPU_STATUS" = "yellow" ] && [ "$OVERALL_STATUS" = "green" ]; then
      OVERALL_STATUS="yellow"
    fi
  fi
}

# ========== 磁盘模块 ==========
parse_disk() {
  DISK_DATA=$(parse_section "DISK" | grep -E '^/dev/')
  MAX_USAGE=0
  
  while IFS= read -r line; do
    USAGE_PERCENT=$(echo "$line" | awk '{print $5}' | sed 's/%//')
    if [ $USAGE_PERCENT -gt $MAX_USAGE ]; then
      MAX_USAGE=$USAGE_PERCENT
    fi
  done <<< "$DISK_DATA"
  
  if [ $MAX_USAGE -lt 70 ]; then
    DISK_STATUS="green"
    DISK_ICON="🟢"
    DISK_COLOR=$COLOR_GREEN
  elif [ $MAX_USAGE -lt 90 ]; then
    DISK_STATUS="yellow"
    DISK_ICON="🟡"
    DISK_COLOR=$COLOR_YELLOW
    ((WARNING_COUNT++))
  else
    DISK_STATUS="red"
    DISK_ICON="🔴"
    DISK_COLOR=$COLOR_RED
    ((ERROR_COUNT++))
  fi
  ((STATUS_COUNT++))
  
  # 更新总体状态
  if [ "$DISK_STATUS" = "red" ] && [ "$OVERALL_STATUS" != "red" ]; then
    OVERALL_STATUS="red"
  elif [ "$DISK_STATUS" = "yellow" ] && [ "$OVERALL_STATUS" = "green" ]; then
    OVERALL_STATUS="yellow"
  fi
}


# 执行所有解析
parse_cpu
parse_ram
parse_gpu
parse_disk

# 确定顶部栏图标
if [ "$OVERALL_STATUS" = "red" ]; then
  OVERALL_ICON="🔴"
elif [ "$OVERALL_STATUS" = "yellow" ]; then
  OVERALL_ICON="🟡"
else
  OVERALL_ICON="🟢"
fi

# ========== 生成顶部栏 ==========
echo "$OVERALL_ICON Server"

# ========== 生成多级菜单 ==========
echo "---"

# CPU - 可展开的一级菜单
echo "🖥️ CPU: ${CPU_USAGE}${CPU_COLOR}"
echo "--"
echo "📊 Usage: ${CPU_USAGE}% | font=Menlo size=12 refresh=true"
echo "📈 Load 1m: ${LOAD_1M} | font=Menlo size=12 refresh=true"
echo "📈 Load 5m: ${LOAD_5M} | font=Menlo size=12 refresh=true"
echo "📈 Load 15m: ${LOAD_15M} | font=Menlo size=12 refresh=true"

# RAM - 可展开的一级菜单
echo "💾 RAM: ${USAGE_PERCENT}%${RAM_COLOR}"
echo "--"
echo "💾 Total: $((TOTAL/1024)) GB | font=Menlo size=12 refresh=true"
echo "💾 Used: $((USED/1024)) GB | font=Menlo size=12 refresh=true"
echo "✅ Available: $((AVAILABLE/1024)) GB | font=Menlo size=12 refresh=true"

# GPU - 可展开的一级菜单
if [ "$GPU_STATUS" = "gray" ]; then
  echo "🎮 GPU: No GPU detected | color=gray"
else
  echo "🎮 GPU: ${GPU_FREE_COUNT}/${GPU_TOTAL_COUNT} Free${GPU_COLOR}"
  echo "--"
  while IFS= read -r line; do
    IDX=$(echo "$line" | awk -F', ' '{print $1}')
    NAME=$(echo "$line" | awk -F', ' '{print $2}' | sed 's/NVIDIA //')
    UTIL=$(echo "$line" | awk -F', ' '{print $3}')
    MEM_FREE=$(echo "$line" | awk -F', ' '{print $4}')
    MEM_TOTAL=$(echo "$line" | awk -F', ' '{print $5}')
    TEMP=$(echo "$line" | awk -F', ' '{print $6}')
    
    # 跳过空行
    [ -z "$IDX" ] && continue
    
    # 确保数值有效
    UTIL=${UTIL:-0}
    MEM_FREE=${MEM_FREE:-0}
    MEM_TOTAL=${MEM_TOTAL:-0}
    TEMP=${TEMP:-0}
    
    if [ "$UTIL" -lt 5 ] && [ "$MEM_FREE" -gt 4000 ]; then
      LINE_ICON="🟢"
      LINE_COLOR=""
    else
      LINE_ICON="🔴"
      LINE_COLOR=" | color=#FF453A"
    fi
    
    echo "$LINE_ICON [$IDX] ${NAME}: ${UTIL}% ${TEMP}°C ${MEM_FREE}MB/${MEM_TOTAL}MB | font=Menlo size=11 refresh=true${LINE_COLOR}"
  done <<< "$GPU_DATA"
fi

# Disk - 可展开的一级菜单
echo "💿 Disk: ${MAX_USAGE}%${DISK_COLOR}"
echo "--"
while IFS= read -r line; do
  DEVICE=$(echo "$line" | awk '{print $1}')
  TOTAL=$(echo "$line" | awk '{print $2}')
  USED=$(echo "$line" | awk '{print $3}')
  USAGE=$(echo "$line" | awk '{print $5}')
  MOUNT=$(echo "$line" | awk '{print $6}')
  
  # 跳过空行
  [ -z "$DEVICE" ] && continue
  
  USAGE_NUM=$(echo "$USAGE" | sed 's/%//')
  USAGE_NUM=${USAGE_NUM:-0}
  
  if [ $USAGE_NUM -lt 70 ]; then
    LINE_COLOR=""
  elif [ $USAGE_NUM -lt 90 ]; then
    LINE_COLOR=" | color=#FFD60A"
  else
    LINE_COLOR=" | color=red"
  fi
  
  echo "💿 $MOUNT: ${USED}/${TOTAL} (${USAGE})${LINE_COLOR} | font=Menlo size=11 refresh=true"
done <<< "$DISK_DATA"

# 底部操作
echo "---"
echo "� Refresh All | refresh=true"
echo "🖥️ Open Terminal | shell=ssh param1=$HOST terminal=true"
