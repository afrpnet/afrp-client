本文档介绍 AFRP OIDC 客户端在各平台的安装方法和详细使用说明。

## 一、平台概览

| 平台 | 安装包 | 图形界面 | 内置 frpc |
| --- | --- | --- | --- |
| Windows 10/11（x64 / arm64） | 安装版 / 免安装版 | 是 | 是（0.71.0） |
| macOS（Apple Silicon / Intel） | zip 解压 | 是 | 是 |
| Linux（amd64 / arm64） | tar.gz 解压 | 是（需桌面环境） | 是 |
| Android 7.0+ | APK 安装 | 是 | 是 |
| HarmonyOS / OpenHarmony | HAP 侧载 | 是 | 测试中 |
| OpenWrt | IPK / APK 安装 | LuCI 网页界面 | 是 |

> **重要**：Windows / macOS / Linux / Android 版为图形桌面应用，需要有图形界面环境。Linux 服务器（无桌面）不能直接运行客户端，见第四节说明。

---

## 二、各平台安装

### 2.1 Windows

> **⚠️ Windows 11 智能应用控制（SAC）用户必读**
>
> 如果你的 Windows 11 开启了「智能应用控制」（Windows 安全中心 → 应用和浏览器控制），系统会阻止未签名的安装程序和卸载程序运行，导致**无法安装**或**无法卸载/升级**。
>
> **解决方案（任选其一）：**
> 1. **使用免安装版**（推荐）：下载 portable.zip，解压即用，不受 SAC 影响
> 2. **临时关闭 SAC**：Windows 安全中心 → 应用和浏览器控制 → 智能应用控制 → 关闭。⚠️ 关闭后无法重新开启，只能重置系统，请谨慎操作
> 3. **手动允许**：被拦截后到「保护历史记录」中手动允许该程序（每次更新都需重复操作）

**安装版（推荐，SAC 用户请用免安装版）**

1. 下载对应架构的安装包：
   - x64（Intel/AMD）：`afrp-oidc-client_<版本>_windows_amd64_setup.exe`
   - arm64（骁龙等）：`afrp-oidc-client_<版本>_windows_arm64_setup.exe`
2. 双击运行，按提示安装
3. 安装时建议勾选「添加 Windows 安全中心排除项」，避免内置 frpc 被误拦
4. 安装完成后从开始菜单或桌面快捷方式启动

**免安装版**

1. 下载 `afrp-oidc-client_<版本>_windows_amd64_portable.zip`
2. 解压到任意目录（如 `D:\AFRP\`）
3. 双击 `afrp_oidc.exe` 启动
4. 注意：要复制整个文件夹（包含 `.dll` 和 `data\` 子目录），不能只拷 exe

> 首次运行如弹出「Windows 已保护你的电脑」，点「更多信息」→「仍要运行」。

### 2.2 macOS

1. 下载对应架构的 zip 包：
   - Apple Silicon（M1/M2/M3/M4）：`macos_arm64.zip`
   - Intel：`macos_amd64.zip`
2. 解压后双击 `.app` 文件
3. 首次运行需在「系统设置 → 隐私与安全性」中点「仍要打开」

### 2.3 Linux

> **需要图形桌面环境**（GNOME / KDE / XFCE 等）。无桌面的服务器请参考第四节。

```bash
# 1. 下载
wget https://github.com/afrpnet/afrp-client/releases/download/v<版本>/afrp-oidc-client_<版本>_linux_amd64.tar.gz

# 2. 安装依赖（Debian/Ubuntu）
sudo apt install libgtk-3-0 libsecret-1-0 libjson-glib-1.0-0 libayatana-appindicator3-1

# 3. 解压（文件直接释放到当前目录）
tar -xzf afrp-oidc-client_<版本>_linux_amd64.tar.gz

# 4. 运行
./afrp_oidc
```

- amd64 适用于 x86_64，arm64 适用于 ARM（树莓派等）
- 兼容 Debian 12+、Ubuntu 20.04+、CentOS 9+（GLIBC 2.35+）

### 2.4 Android

1. 下载 `afrp-oidc-client_<版本>_android_all.apk`
2. 传到手机，点击安装
3. 系统提示「允许安装未知应用」时，为文件管理器/浏览器开启该权限
4. 安装后桌面图标为「AFRP OIDC Client」

### 2.5 OpenWrt

**IPK 安装（opkg，适用于 OpenWrt 23.x 及更早）**

```bash
opkg install luci-app-afrp_<版本>_all.ipk
```

**APK 安装（apk-tools，适用于 OpenWrt 25.12+）**

```bash
apk add --allow-untrusted luci-app-afrp_<版本>.apk
```

安装后在 LuCI 界面「服务 → AFRP」中配置。

---

## 三、使用教程

### 3.1 首次使用（四步）

**第一步：登录**

打开客户端，输入账号和密码。账号与网站通用，不需要单独注册。

- 客户端自动连接官方站点
- 登录状态保存在本机，下次打开自动登录

**第二步：设置 OIDC 密钥**

在「连接」页找到 OIDC 认证卡片，有两种方式：

- **粘贴已有密钥**：从网页端「连接说明」页面复制密钥，粘贴到客户端
- **一键生成新密钥**：点击按钮在服务端生成新密钥

> 注意：生成新密钥会使旧密钥立即失效，其他使用旧密钥的设备会断开。

**第三步：选择服务器、添加隧道**

1. 在「连接」页下拉选择服务器
2. 点击「添加隧道」，填写信息：

| 隧道类型 | 填写项 | 典型用途 |
| --- | --- | --- |
| TCP | 本地IP、本地端口、远程端口 | 远程桌面（3389→13389） |
| UDP | 同上 | 游戏、语音服务 |
| HTTP | 本地IP、本地端口、子域名 | 本机网站通过域名访问 |
| HTTPS | 同上 | 带证书的网站 |
| STCP | 本地IP、本地端口、访问密钥 | 加密TCP，P2P不占服务器端口 |
| SUDP | 同上 | 加密UDP，P2P |
| XTCP | 同上 | 点对点直连（NAT打洞） |

- 本地 IP 默认 `127.0.0.1`（本机）
- 隧道名称只支持字母、数字、`_`、`.`、`-`
- 隧道保存在本机，按服务器分组，退出登录不丢失

**第四步：连接**

点击「连接服务器」按钮：

- 灰色圆点 → 未连接
- 橙色圆点 → 正在启动
- 绿色圆点 → 已连接（隧道已启动）

底部运行日志实时显示 frpc 输出，`error` 行标红，`success` 行标绿。

### 3.2 界面说明

登录后主界面有 3 个页签：

| 页签 | 功能 |
| --- | --- |
| **连接** | 选服务器、配置隧道、一键连接、查看日志 |
| **消息** | 站内信，未读显示角标，每 60 秒自动刷新 |
| **设置** | 账号信息、OIDC 密钥、关于、退出登录 |

- 电脑宽屏：左侧边栏导航
- 手机窄屏：底部导航栏

### 3.3 密钥管理

密钥（Client Secret）是 frpc 向服务器做 OIDC 认证的凭证，等同于穿透密码。

| 操作 | 说明 |
| --- | --- |
| 粘贴已有密钥 | 从网页端复制，保存到本机安全存储 |
| 一键生成新密钥 | 服务端生成，旧密钥立即失效，明文只显示一次 |
| 清除本机密钥 | 仅删除本机副本，服务端密钥不变 |

> 密钥保存在本机系统安全存储（加密），服务端只存哈希。换设备时可从网页端复制后「粘贴已有密钥」。

### 3.4 查看配置文件

点击「查看配置」可预览自动生成的 `frpc.toml`：

- 密钥默认用圆点打码，可切换「显示密钥」
- 可「复制完整配置」用于手动部署
- 包含服务器地址、user、auth.oidc.* 认证字段与每条隧道的 `[[proxies]]`

---

## 四、服务器（无桌面 Linux）使用方案

Linux 客户端是 GUI 应用，无法在纯 SSH 终端中运行。服务器场景推荐以下方案：

### 方案 A：X11 转发（临时管理）

从有桌面的电脑 SSH 到服务器：

```bash
# Windows 用 MobaXterm 或安装 VcXsrv
# macOS 自带 X11 转发
ssh -X root@你的服务器

# 服务器上运行
./afrp_oidc
```

界面会显示在本地桌面，适合临时配置隧道。

### 方案 B：frp-onekey 一键脚本（推荐）

使用 [frp-onekey](https://github.com/KuwiNet/frp-onekey) 一键部署脚本，自动安装 frpc、配置 systemd 服务、提供全局快捷命令。

**安装（国内服务器优先用镜像源）：**

```bash
# 国内镜像源（推荐）
curl -LO https://arelay.cn/raw.githubusercontent.com/KuwiNet/frp-onekey/master/frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install

# 或 GitHub 源
curl -L https://frpc.afrp.net -o frpc.sh && chmod +x frpc.sh && sudo bash frpc.sh install
```

安装后：
- 程序目录：`/opt/frpc/`
- 配置文件：`/opt/frpc/frpc.toml`
- 服务管理：systemd 自动管理，崩溃自动重启

**全局快捷命令：**

```bash
frpc start     # 启动服务
frpc stop      # 停止服务
frpc restart   # 重启服务
frpc status    # 查看运行状态
frpc enable    # 开机自启
frpc disable   # 关闭自启
frpc version   # 查看 frp 版本
frpc config    # 编辑配置文件（vim）
frpc log       # 实时查看日志（Ctrl+C 退出）
frpc           # 不带参数显示完整帮助
```

**配置 OIDC 连接：**

编辑配置文件，填入从网页端获取的 OIDC 信息：

```bash
frpc config
```

在 `frpc.toml` 中填写：

```toml
serverAddr = "服务器地址"
serverPort = 7000

auth.method = "oidc"
auth.oidc.clientID = "你的用户名"
auth.oidc.clientSecret = "从网页端「连接说明」获取的密钥"
auth.oidc.tokenEndpointURL = "https://www.afrp.net/oidc/token"
auth.oidc.audience = "frp"
auth.oidc.scope = "openid"

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 10022
```

保存后启动：

```bash
frpc start
frpc log    # 查看连接日志
```

**其他操作：**

```bash
# 更新 frpc（保留配置文件）
sudo bash frpc.sh update

# 卸载
sudo bash frpc.sh uninstall
```

> 脚本特性：安装时如检测到已有 `frpc.toml` 不会覆盖；`update` 仅更新二进制不改动配置；支持 Ubuntu / Debian / CentOS / Rocky / AlmaLinux。

---

## 五、常见问题

### 安装与卸载

**Q：Windows 11 安装/卸载/升级时被系统拦截？**
这是 Windows「智能应用控制」（SAC）阻止了未签名的程序。
- **推荐**：使用免安装版（portable.zip），解压即用，不受 SAC 影响
- 或临时关闭 SAC（关闭后无法重新开启，只能重置系统）
- 或在「保护历史记录」中手动允许（每次更新都需重复）

**Q：升级时弹出关不掉的终端窗口？**
已修复（v1.2.3+）。旧版本升级时更新脚本中的 `find` 命令会被 Windows Terminal 拦截弹出空窗口。请升级到最新版本。

### 登录问题

**Q：登录提示连接失败？**
检查网络是否能访问站点。客户端会自动尝试多个备用地址。

**Q：账号密码是什么？**
与网站通用，使用网页端相同的用户名（或邮箱）+ 密码。

### 连接问题

**Q：连接失败，日志显示 `authentication failed`？**
密钥与服务端不一致，重新「粘贴已有密钥」或「一键生成新密钥」。

**Q：提示「账号未开启 OIDC 认证」？**
联系管理员在后台为该账号开启 OIDC 认证。

**Q：同一时刻能连几个服务器？**
一个。切换服务器前请先断开。

### Linux 问题

**Q：运行提示 `GLIBC_2.38 not found`？**
当前构建基于 Ubuntu 22.04（GLIBC 2.35），兼容 Debian 12+、Ubuntu 20.04+。如果系统 GLIBC 低于 2.35，请升级系统。

**Q：提示找不到 GTK 库？**
```bash
# Debian/Ubuntu
sudo apt install libgtk-3-0 libsecret-1-0 libjson-glib-1.0-0 libayatana-appindicator3-1
```

### 数据与升级

**Q：隧道配置会丢失吗？**
不会。配置保存在本机，退出登录也保留。但不随账号同步，换设备需重新配置。

**Q：如何升级？**
- Windows 安装版：运行新版本安装程序（SAC 用户请用免安装版覆盖）
- Windows 免安装版：关闭程序，用新版本覆盖旧目录
- macOS/Linux：关闭程序，用新版本替换旧文件
- 数据目录不受升级影响

**Q：数据保存在哪？**

| 平台 | 路径 |
| --- | --- |
| Windows | `%APPDATA%\net.afrp\AFRP OIDC Client\` |
| macOS | `~/Library/Application Support/net.afrp/AFRP OIDC Client/` |
| Linux | `~/.local/share/net.afrp/AFRP OIDC Client/` |
| Android | `/data/data/net.afrp.frp_oidc_app/` |
