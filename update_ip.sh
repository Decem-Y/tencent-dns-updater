#!/bin/bash

# 腾讯云DNSPOD自动更新公网IP脚本

# 默认配置信息
DOMAIN="example.com"      # 你的主域名
SUB_DOMAIN="@"            # 子域名，如www
SECRET_ID="your-secret-id-here"  # 腾讯云API密钥ID
SECRET_KEY="your-secret-key-here" # 腾讯云API密钥
TTL=600                     # TTL值，单位秒

# 配置文件路径
CONFIG_FILE="$HOME/.config/tencent-dns-updater/config"

# 如果配置文件存在，则从配置文件加载设置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 脚本路径
API_SCRIPT="$HOME/tencent-dns-updater/dnspod_api.py"

# 导出API密钥为环境变量，供Python脚本使用
export DNSPOD_SECRET_ID="$SECRET_ID"
export DNSPOD_SECRET_KEY="$SECRET_KEY"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查依赖
if ! command -v curl &> /dev/null; then
    log "Error: curl未安装，请运行 'apt-get install -y curl' 或 'yum install -y curl' 安装"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log "Error: jq未安装，请运行 'apt-get install -y jq' 或 'yum install -y jq' 安装"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    log "Error: python3未安装，请运行 'apt-get install -y python3' 或 'yum install -y python3' 安装"
    exit 1
fi

if [ ! -f "$API_SCRIPT" ]; then
    log "Error: API辅助脚本不存在: $API_SCRIPT"
    exit 1
fi

# 确保API脚本有执行权限
chmod +x "$API_SCRIPT"

# 获取当前公网IP
get_current_ip() {
    # 尝试多个IP获取服务，增加可靠性
    # 使用 --noproxy '*' 绕过代理，确保获取的是服务器真实公网IP而非代理IP
    IP=$(curl -s --noproxy '*' https://api.ipify.org || 
         curl -s --noproxy '*' https://icanhazip.com || 
         curl -s --noproxy '*' https://ifconfig.me)
    
    if [[ -z "$IP" ]]; then
        log "Error: 无法获取公网IP地址"
        exit 1
    fi
    
    echo "$IP"
}

# 获取DNSPOD域名记录
get_record_info() {
    local params="{\"Domain\":\"$DOMAIN\",\"Subdomain\":\"$SUB_DOMAIN\",\"RecordType\":\"A\"}"
    
    # 调用API获取记录信息
    response=$(python3 "$API_SCRIPT" "DescribeRecordList" "$params")
    
    echo "$response"
}

# 更新DNS记录
update_record() {
    local record_id=$1
    local new_ip=$2
    
    local params="{\"Domain\":\"$DOMAIN\",\"RecordId\":$record_id,\"RecordType\":\"A\",\"RecordLine\":\"默认\",\"Value\":\"$new_ip\",\"TTL\":$TTL,\"SubDomain\":\"$SUB_DOMAIN\"}"
    
    # 调用API更新记录
    response=$(python3 "$API_SCRIPT" "ModifyRecord" "$params")
    
    if echo "$response" | grep -q "Error"; then
        log "Error: DNSPOD更新失败: $response"
        return 1
    else
        log "DNSPOD记录已更新为: $new_ip"
        return 0
    fi
}

# 创建DNS记录
create_record() {
    local new_ip=$1
    
    local params="{\"Domain\":\"$DOMAIN\",\"SubDomain\":\"$SUB_DOMAIN\",\"RecordType\":\"A\",\"RecordLine\":\"默认\",\"Value\":\"$new_ip\",\"TTL\":$TTL}"
    
    # 调用API创建记录
    response=$(python3 "$API_SCRIPT" "CreateRecord" "$params")
    
    if echo "$response" | grep -q "Error"; then
        log "Error: DNSPOD记录创建失败: $response"
        return 1
    else
        log "DNSPOD记录已创建: $new_ip"
        return 0
    fi
}

# 时间同步函数
sync_time() {
    log "尝试同步系统时间..."
    
    # 尝试使用chrony同步
    if command -v chronyd &> /dev/null && systemctl is-active chronyd &>/dev/null; then
        log "使用chrony同步时间..."
        chronyd -q 'server pool.ntp.org iburst' &>/dev/null
        if [ $? -eq 0 ]; then
            log "系统时间已通过chrony成功同步"
            return 0
        else
            log "警告: chrony同步失败，尝试其他方法"
        fi
    fi
    
    # 检查timedatectl同步状态（不执行set-ntp避免需要密码认证）
    if command -v timedatectl &> /dev/null; then
        if timedatectl status | grep -i "synchronized: yes" &>/dev/null; then
            log "系统时间已同步（timedatectl确认）"
            return 0
        else
            log "警告: 系统时间未同步"
        fi
    fi
    
    # 检查systemd-timesyncd状态（不重启服务避免需要权限）
    if systemctl is-active systemd-timesyncd &>/dev/null; then
        log "systemd-timesyncd正在运行，时间应已同步"
        return 0
    fi
    
    # 如果所有同步尝试都失败
    log "警告: 所有时间同步方法均失败，将使用Python脚本获取网络时间作为备用"
    return 1
}

# 主程序
main() {
    # 同步系统时间
    sync_time
    
    # 获取当前公网IP
    current_ip=$(get_current_ip)
    log "当前公网IP: $current_ip"
    
    # 获取DNSPOD记录
    record_info=$(get_record_info)
    
    # 解析记录ID和值
    if echo "$record_info" | grep -q "RecordList"; then
        # 提取第一条A记录
        record_id=$(echo "$record_info" | jq -r '.Response.RecordList[] | select(.Type=="A" and .Name=="'$SUB_DOMAIN'") | .RecordId' | head -1)
        record_ip=$(echo "$record_info" | jq -r '.Response.RecordList[] | select(.Type=="A" and .Name=="'$SUB_DOMAIN'") | .Value' | head -1)
        
        if [[ -z "$record_id" ]]; then
            log "未找到A记录，将创建新记录"
            create_record "$current_ip"
        elif [[ "$record_ip" != "$current_ip" ]]; then
            log "DNSPOD记录需要更新: $record_ip -> $current_ip"
            update_record "$record_id" "$current_ip"
        else
            log "DNSPOD记录无需更新，当前IP: $current_ip"
        fi
    else
        log "Error: 获取DNSPOD记录失败: $record_info"
        log "将尝试创建新记录"
        create_record "$current_ip"
    fi
}

# 执行主程序
main
