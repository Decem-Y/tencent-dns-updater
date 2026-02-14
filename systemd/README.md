# Systemd 服务配置

本目录包含了使用 systemd 实现开机自启和定时更新 IP 的配置文件。

## 安装步骤

### 1. 复制服务文件到用户 systemd 目录

```bash
mkdir -p ~/.config/systemd/user
cp systemd/dns-updater.service ~/.config/systemd/user/
cp systemd/dns-updater.timer ~/.config/systemd/user/
```

### 2. 修改服务文件中的路径

编辑 `~/.config/systemd/user/dns-updater.service`，将 `YOUR_USERNAME` 替换为实际的用户名：

```bash
sed -i "s|YOUR_USERNAME|$USER|g" ~/.config/systemd/user/dns-updater.service
```

### 3. 重载 systemd 配置并启用服务

```bash
systemctl --user daemon-reload
systemctl --user enable dns-updater.timer
systemctl --user start dns-updater.timer
```

### 4. 启用 linger（可选，确保未登录时也能运行）

```bash
sudo loginctl enable-linger $USER
```

## 服务说明

- **dns-updater.service**: 执行 IP 更新的主服务
- **dns-updater.timer**: 定时触发器
  - 开机后 30 秒首次运行
  - 之后每 5 分钟运行一次
  - 即使错过了运行时间也会补执行（Persistent=true）

## 常用管理命令

### 查看定时器状态

```bash
systemctl --user status dns-updater.timer
systemctl --user list-timers dns-updater.timer
```

### 查看运行日志

```bash
journalctl --user -u dns-updater.service -f
journalctl --user -u dns-updater.service --no-pager -n 50
```

### 手动触发一次

```bash
systemctl --user start dns-updater.service
```

### 停止定时任务

```bash
systemctl --user stop dns-updater.timer
systemctl --user disable dns-updater.timer
```

### 重启定时任务

```bash
systemctl --user restart dns-updater.timer
```

## 注意事项

1. **代理环境变量问题**: 如果服务器设置了 `HTTP_PROXY`/`HTTPS_PROXY` 等代理环境变量，脚本会自动使用 `--noproxy '*'` 参数绕过代理，确保获取服务器真实公网 IP。

2. **权限问题**: 使用用户级 systemd 服务（`systemctl --user`）无需 root 权限，但需要启用 linger 才能在未登录时运行。

3. **时间同步**: 脚本会自动检查系统时间同步状态，无需额外配置。如果时间不同步，Python 脚本会通过 NTP/HTTP 获取网络时间。
