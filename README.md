# AFRP OIDC Client

基于 [frp](https://github.com/fatedier/frp) 的多端内网穿透客户端，内置 OIDC 认证，支持 Windows / macOS / Linux / Android / HarmonyOS / OpenWrt。

## 功能

- 登录账号、查看会员状态、购买套餐
- 选择服务器、配置隧道（TCP / UDP / HTTP / HTTPS / STCP / SUDP / XTCP）
- 一键连接，内置 frpc 核心自动释放
- OIDC 密钥管理（粘贴已有 / 一键生成 / 清除）
- 站内消息提醒
- 多平台统一界面

## 客户端测试情况

| 平台 | 测试情况 | 仓库 |
| --- | --- | --- |
| Windows | ✅ 已测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库） |
| Android | ✅ 已测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库） |
| OpenWrt | ✅ 已测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库 `openwrt/` 目录，LuCI 插件 ipk / apk） |
| Docker | ✅ 已测试 | [afrpnet/afrp-docker](https://github.com/afrpnet/afrp-docker)（Docker Hub `afrp/afrp`） |
| macOS | ❎ 未测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库） |
| Linux | ✅ 已测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库） |
| HarmonyOS / OpenHarmony | ❎ 未测试 | [afrpnet/afrp-client](https://github.com/afrpnet/afrp-client)（本仓库） |

> ✅ 表示已在真实设备 / 环境中完成连接测试；❎ 表示已提供构建产物但尚未验证，欢迎反馈问题。

## 安装

### Windows

**安装版（推荐）**：下载 `afrp-oidc-client_<版本>_windows_amd64_setup.exe`，双击安装。安装时可选自动添加 Windows Defender 排除项，避免内置 frpc 被误拦。

**免安装版**：下载 `afrp-oidc-client_<版本>_windows_amd64_portable.zip`，解压到任意目录，双击 `afrp_oidc.exe` 启动。

> 首次运行如弹出 SmartScreen 提示，点「更多信息」→「仍要运行」。

### macOS

下载 `afrp-oidc-client_<版本>_macos_<架构>.zip`，解压后双击 `.app`。首次运行需在「系统设置 → 隐私与安全性」中允许。

- Apple Silicon 选 `arm64`，Intel 选 `amd64`

### Linux

二选一：

- **DEB 安装包**（Debian/Ubuntu）：下载 `afrp-oidc-client_<版本>_linux_<架构>.deb`，执行 `sudo apt install ./afrp-oidc-client_<版本>_linux_<架构>.deb`。
  - 程序装在 `/opt/afrp-oidc-client/`，命令 `afrp_oidc`，系统菜单项 `/usr/share/applications/net.afrp.frp_oidc_app.desktop`
  - 安装时会自动在桌面放一个启动图标（XFCE/GNOME/KDE 等通用）；若没有，从「应用程序 → 网络 → AFRP OIDC 客户端」打开，右键可「添加到桌面/面板」
  - 菜单没刷新时执行 `xfce4-panel -r`（XFCE）或重新登录
- **免安装版**：下载 `afrp-oidc-client_<版本>_linux_<架构>.tar.gz`，解压后运行 `afrp_oidc`（首次启动会把带图标的启动器和桌面图标注册到用户目录）。

卸载会一并清理桌面图标：
```bash
sudo apt remove afrp-oidc-client
```

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

**添加客户端 opkg 源，安装 .ipk（推荐）**：
```bash
# 1) 添加软件源（一次即可，之后可自动更新）
echo 'src/gz afrp https://afrpnet.github.io/afrp-client' >> /etc/opkg/customfeeds.conf
# 2) 更新列表并安装
opkg update
opkg install luci-app-afrp
```
**opkg 安装 .ipk（无网络环境时）**
```bash
wget -O /tmp/afrp.ipk https://dl.afrp.net/app/luci-app-afrp_1.1.5_all.ipk
opkg install /tmp/afrp.ipk
```
**通用压缩包（无 opkg / 不想装包时）**
```bash
wget -O /tmp/afrp.tar.gz https://dl.afrp.net/app/luci-app-afrp-1.1.5.tar.gz
tar -xzf /tmp/afrp.tar.gz -C /tmp
cd /tmp/luci-app-afrp-1.1.0 && ./install.sh
```
卸载：同一目录 `./install.sh uninstall`（加 `--purge` 连配置一起删）。

**手动安装**：下载 `luci-app-afrp-<版本>.tar.gz`，解压到 `/usr/lib/lua/luci/`。

安装后在 LuCI 界面「服务 → AFRP 内网穿透」中配置。

## 快速开始

1. **登录**：输入账号密码，默认连接 `https://www.afrp.net`
2. **选择服务器**：选择要连接的服务器
3. **设置 OIDC 密钥**：在「连接」页选择「粘贴已有密钥」或「一键生成新密钥」
4. **添加隧道**：选择服务器，点「添加隧道」，填写本地 IP、端口、远程端口
5. **连接**：点「连接服务器」，状态变绿即成功

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

## 发版流程

版本号真源是 `pubspec.yaml`，其余落点由脚本统一改写，不要手动编辑。

```bash
# 1. 改版本并同步所有落点（版本变化时 build 号自动 +1）
bash tool/sync-version.sh 1.3.18

# 2. 校验各落点一致（CI 也会跑同一份检查，不一致直接失败）
bash tool/sync-version.sh --check 1.3.18

# 3. 提交并打 tag，tag 版本必须与 pubspec.yaml 一致
git add -A && git commit -m "chore: bump version to 1.3.18"
git tag v1.3.18 && git push origin main && git push origin v1.3.18
```

同步落点：`pubspec.yaml`、`lib/core/updater.dart`、`installer/setup.iss`、`openwrt/luci-app-afrp/Makefile`、`ohos/AppScope/app.json5`。
OpenWrt LuCI 页面上的版本号由 `openwrt/tools/build-ipk.php` 在打包时注入，无需手改。

## 许可证

MIT
