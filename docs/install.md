# 各平台安装说明

## Windows 10/11（x64）

**安装版（推荐）**：下载 `afrp-oidc-client_<版本>_windows_amd64_setup.exe`，双击安装。安装时可选自动添加 Windows Defender 排除项，避免内置 frpc 被误拦。

**免安装版**：下载 `afrp-oidc-client_<版本>_windows_amd64_portable.zip`，解压到任意目录，双击 `afrp_oidc.exe` 启动。

> 首次运行如弹出 SmartScreen 提示，点「更多信息」→「仍要运行」。

说明：
- 内置 frpc 0.71.0，首次连接时自动释放到本机数据目录
- 升级：运行新版本安装程序自动升级；免安装版关闭程序后用新版本覆盖旧目录
- 卸载：安装版通过系统卸载；免安装版删除程序文件夹即可
- 数据保存在 `%APPDATA%\net.afrp\AFRP OIDC Client\`，不受升级/卸载影响

## macOS

下载 `afrp-oidc-client_<版本>_macos_<架构>.zip`，解压后双击 `.app`。

- Apple Silicon 选 `arm64`，Intel 选 `amd64`
- 首次运行需在「系统设置 → 隐私与安全性」中允许
- macOS 版 frpc 以压缩包形式分发，运行时自动解压

## Linux

> **注意**：Linux 版是图形桌面应用，需要有图形桌面环境（GNOME / KDE / XFCE 等）。无桌面的服务器无法直接运行，见下方说明。

下载 `afrp-oidc-client_<版本>_linux_<架构>.tar.gz`，解压后运行。

```bash
# 解压（文件直接释放到当前目录）
tar -xzf afrp-oidc-client_<版本>_linux_amd64.tar.gz

# 安装依赖（Debian/Ubuntu）
sudo apt install libgtk-3-0 libsecret-1-0 libjson-glib-1.0-0 libayatana-appindicator3-1

# 运行
./afrp_oidc
```

- amd64 适用于 x86_64 系统，arm64 适用于 ARM 系统（树莓派等）
- 兼容 Debian 12+、Ubuntu 20.04+、CentOS 9 等（GLIBC 2.35+）
- 数据保存在 `~/.local/share/net.afrp/AFRP OIDC Client/`

**无桌面服务器如何使用：**

Linux 客户端是 GUI 应用，不能直接在 SSH 终端中运行。服务器场景推荐以下方案：

1. **X11 转发**：从有桌面的电脑 SSH 到服务器（`ssh -X`），然后运行 `./afrp_oidc`，界面会显示在本地桌面
2. **直接用 frpc 命令行**：服务器通常已有 frpc，手动编写 `frpc.toml` 配置文件运行即可，不需要 GUI 客户端。OIDC 密钥从网页端获取后填入配置

## Android 7.0+

下载 `afrp-oidc-client_<版本>_android_all.apk`，传到手机安装。系统会提示允许「安装未知应用」。

- 包名：`net.afrp.frp_oidc_app`
- 内置 frpc，连接功能已可用

## HarmonyOS / OpenHarmony

下载 `afrp-oidc-client_<版本>_ohos_arm64.hap`，通过 `hdc install` 安装。

> 使用 OpenHarmony 测试签名，仅支持 OpenHarmony 设备/模拟器。HarmonyOS NEXT 真机需要华为云签名。

## OpenWrt

**IPK 安装**：
```bash
opkg install luci-app-afrp_<版本>_all.ipk
```

**手动安装**：下载 `luci-app-afrp-<版本>.tar.gz`，解压到 `/usr/lib/lua/luci/`。

安装后在 LuCI 界面「服务 → AFRP」中配置。
