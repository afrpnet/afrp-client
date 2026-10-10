# AFRP OIDC Client

基于 [frp](https://github.com/fatedier/frp) 的多端内网穿透客户端，内置 OIDC 认证，支持 Windows / macOS / Linux / Android / HarmonyOS / OpenWrt。

## 功能

- 登录账号、查看会员状态、购买套餐
- 选择服务器、配置隧道（TCP / UDP / HTTP / HTTPS / STCP / SUDP / XTCP）
- 一键连接，内置 frpc 核心自动释放
- OIDC 密钥管理（粘贴已有 / 一键生成 / 清除）
- 站内消息提醒
- 多平台统一界面

## 安装

### Windows

**安装版（推荐）**：下载 `afrp-oidc-client_<版本>_windows_amd64_setup.exe`，双击安装。安装时可选自动添加 Windows Defender 排除项，避免内置 frpc 被误拦。

**免安装版**：下载 `afrp-oidc-client_<版本>_windows_amd64_portable.zip`，解压到任意目录，双击 `afrp_oidc.exe` 启动。

> 首次运行如弹出 SmartScreen 提示，点「更多信息」→「仍要运行」。

### macOS

下载 `afrp-oidc-client_<版本>_macos_<架构>.zip`，解压后双击 `.app`。首次运行需在「系统设置 → 隐私与安全性」中允许。

- Apple Silicon 选 `arm64`，Intel 选 `amd64`

### Linux

下载 `afrp-oidc-client_<版本>_linux_<架构>.tar.gz`，解压后运行 `afrp_oidc`。

需要 GTK3 环境：
```bash
# Debian/Ubuntu
sudo apt install libgtk-3-0 libsecret-1-0 libjson-glib-1.0-0 libayatana-appindicator3-1
```

### Android

下载 `afrp-oidc-client_<版本>_android_all.apk`，传到手机安装。系统会提示允许「安装未知应用」。

> 当前版本内置 frpc 连接功能已可用。

### HarmonyOS / OpenHarmony

下载 `afrp-oidc-client_<版本>_ohos_arm64.hap`，通过 `hdc install` 安装。

> 使用 OpenHarmony 测试签名，仅支持 OpenHarmony 设备/模拟器。HarmonyOS NEXT 真机需要华为云签名。

### OpenWrt

**IPK 安装**：
```bash
opkg install luci-app-afrp_<版本>_all.ipk
```

**手动安装**：下载 `luci-app-afrp-<版本>.tar.gz`，解压到 `/usr/lib/lua/luci/`。

安装后在 LuCI 界面「服务 → AFRP」中配置。

## 快速开始

1. **登录**：输入账号密码，默认连接 `https://www.afrp.net`
2. **设置 OIDC 密钥**：在「连接」页选择「粘贴已有密钥」或「一键生成新密钥」
3. **添加隧道**：选择服务器，点「添加隧道」，填写本地 IP、端口、远程端口
4. **连接**：点「连接服务器」，状态变绿即成功

## 文档

- [用户手册](docs/user-guide.md) — 详细功能说明
- [安装说明](docs/install.md) — 各平台安装细节
- [常见问题](docs/faq.md) — FAQ

## 更新

- **Windows 安装版**：运行新版本安装程序自动升级
- **Windows 免安装版**：关闭程序，用新版本覆盖旧目录
- **其他平台**：App 内检查更新或到 [Releases](https://github.com/afrpnet/afrp-client/releases) 下载

## 数据位置

| 平台 | 路径 |
| --- | --- |
| Windows | `%APPDATA%\net.afrp\AFRP OIDC Client\` |
| macOS | `~/Library/Application Support/net.afrp/AFRP OIDC Client/` |
| Linux | `~/.local/share/net.afrp/AFRP OIDC Client/` |
| Android | `/data/data/net.afrp.frp_oidc_app/` |

隧道配置和登录状态保存在本机，换设备需重新登录。

## 许可证

MIT
