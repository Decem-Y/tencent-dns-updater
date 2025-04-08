# 腾讯云 DNS 自动更新IP工具


这是一套自动更新域名DNS记录的脚本工具，用于动态IP环境下保持域名解析与当前公网IP的同步。主要适用于家庭宽带、小型服务器等IP地址会变化的场景。

## 主要特性

- 自动检测当前公网IP地址
- 自动更新腾讯云DNSPOD的域名解析记录
- 支持自定义域名、子域名和TTL配置
- 支持通过独立的配置文件设置敏感信息
- 自动系统时间同步，避免API调用因时间不同步导致的认证失败
- 完整的日志记录
- 支持作为定时任务运行

## 文件说明

- `update_ip.sh` - 主脚本文件，负责获取公网IP并更新DNS记录
- `dnspod_api.py` - Python辅助脚本，负责与腾讯云API通信
- `config.template` - 配置文件模板，用于设置域名和API密钥

## 安装说明

### 依赖项

- bash环境
- curl
- jq
- python3
- requests (Python库)

### 安装步骤

1. 克隆或下载脚本到本地：

```bash
mkdir -p ~/tencent-dns-updater
# 将脚本文件放入此目录
```

2. 安装必要依赖：

```bash
# Debian/Ubuntu系统
sudo apt-get update
sudo apt-get install -y curl jq python3 python3-pip
pip3 install requests
```

3. 设置脚本执行权限：

```bash
chmod +x ~/tencent-dns-updater/update_ip.sh
chmod +x ~/tencent-dns-updater/dnspod_api.py
```

## 配置说明

有两种方式配置脚本：

### 1. 直接编辑脚本

在`update_ip.sh`中直接编辑配置参数：

```bash
# 配置信息
DOMAIN="your-domain.com"  # 你的主域名
SUB_DOMAIN="@"            # 子域名，如www，或使用@表示主域名
SECRET_ID="your-secret-id"   # 腾讯云API密钥ID
SECRET_KEY="your-secret-key" # 腾讯云API密钥
TTL=600                      # TTL值，单位秒
```

### 2. 使用配置文件（推荐）

创建配置文件目录：

```bash
mkdir -p ~/.config/tencent-dns-updater/
```

创建配置文件：

```bash
touch ~/.config/tencent-dns-updater/config

chmod 600 ~/.config/tencent-dns-updater/config
```

添加以下内容：

```bash
DOMAIN="your-domain.com"
SUB_DOMAIN="@"
SECRET_ID="your-secret-id"
SECRET_KEY="your-secret-key"
TTL=600
```

设置配置文件权限：

```bash
chmod 600 ~/.config/tencent-dns-updater/config
```

### 获取API密钥

1. 登录[腾讯云控制台](https://console.cloud.tencent.com/)
2. 进入 API 密钥管理页面
3. 创建或使用已有的API密钥
4. 将获得的SecretId和SecretKey填入配置中

## 使用方法

### 手动运行

直接执行脚本即可：

```bash
~/tencent-dns-updater/update_ip.sh
```

### 设置定时任务

通过crontab设置定时运行：

```bash
crontab -e
```

添加以下内容（每10分钟检查一次）：

```
*/10 * * * * /home/username/tencent-dns-updater/update_ip.sh >> /home/username/tencent-dns-updater/update_ip.log 2>&1
```

## 日志查看

脚本运行日志保存在：

```
/home/username/tencent-dns-updater/update_ip.log
```


## 故障排除

- 如果脚本无法正常工作，请检查日志文件中的错误信息
- 确保系统时间同步正确，API调用依赖准确的时间戳
- 验证网络连接是否正常，特别是到腾讯云API的连接
- 检查API密钥是否正确且有效

## 许可说明

此脚本工具供个人学习和使用，请遵循相关服务提供商的使用条款。
