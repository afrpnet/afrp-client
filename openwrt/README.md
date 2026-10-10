# luci-app-afrp — AFRP OIDC frpc 客户端（OpenWrt LuCI 插件）

在 OpenWrt 路由器上以 LuCI 网页插件的形式运行 frpc：隧道配置可视化，OIDC 认证参数自动
填充，frpc 核心可在线更新。与网站（afrp.net）和桌面/移动 App 共用同一套账号体系。

## 目录结构

```
luci-app-afrp/                 LuCI 插件源码（含 SDK Makefile）
  Makefile                     OpenWrt SDK / feeds 编译入口（PKGARCH=all）
  root/etc/config/afrp         UCI 配置模板（升级不覆盖）
  root/etc/init.d/afrp         procd 服务脚本（reload = stop + start）
  root/usr/libexec/afrp/render           由 UCI 生成 /var/etc/afrp.toml
  root/usr/libexec/afrp/update-core      frpc 核心检测/检查/安装（ucode）
  root/usr/libexec/afrp/import-account   从官网导入账号与服务器（ucode）
  root/usr/share/luci/menu.d/            LuCI 菜单与 ACL
  root/usr/share/rpcd/acl.d/
  htdocs/luci-static/resources/view/afrp/ 三个页面：client / proxy / status
tools/build-ipk.php            本机打包脚本（生成 .ipk 与 tar.gz，无需 SDK）
install.sh                     通用 tar.gz 包内的安装脚本（随包分发）
dist/                          打包产物（build-ipk.php 生成）
```

## 安装（三选一）

### 1. opkg 安装 .ipk（推荐）

```sh
wget -O /tmp/afrp.ipk https://www.afrp.net/download/files/luci-app-afrp_1.1.0-1_all.ipk
opkg install /tmp/afrp.ipk
```

安装完刷新 LuCI（或 F5），菜单「服务 → AFRP frpc」。

> 若提示签名相关错误：`opkg install --force-signature /tmp/afrp.ipk`。

### 2. 通用压缩包（无 opkg / 不想装包时）

```sh
wget -O /tmp/afrp.tar.gz https://www.afrp.net/download/files/luci-app-afrp-1.1.0.tar.gz
tar -xzf /tmp/afrp.tar.gz -C /tmp
cd /tmp/luci-app-afrp-1.1.0 && ./install.sh
```

卸载：同一目录 `./install.sh uninstall`（加 `--purge` 连配置一起删）。

### 3. 自编译（OpenWrt SDK / 源码树）

```sh
# SDK：把 luci-app-afrp 拷到 package/ 下
cd ~/openwrt-sdk/package && cp -r /path/to/luci-app-afrp .
cd .. && make defconfig && make package/luci-app-afrp/compile V=s
# 产物 bin/packages/*/base/luci-app-afrp_*.ipk
```

源码树（feeds/luci/applications 下）或 SDK 两种布局都支持（Makefile 自动探测 luci.mk）。

## 配置流程

1. 打开 LuCI「服务 → AFRP frpc → 基础设置」，填入 `服务器地址 / 端口`（默认 7000）。
2. 到官网「用户中心 → APP / 客户端」取得 `client_id` 与 `client_secret` 填入；
   或直接使用下面的「官网导入」一步完成（推荐）。
3. 「隧道管理」页添加隧道（类型、本地端口、子域名/自定义域名等），保存并应用。
4. 「基础设置」勾选「启用」，或在「运行状态」页点「启动服务」。

配置保存在 `/etc/config/afrp`（UCI），运行配置由 `render` 生成到 `/var/etc/afrp.toml`
（每次启动/重载自动重写，不要手工编辑）。

### 官网导入（推荐上手方式）

「运行状态 → 官网导入」：填官网地址（默认取 https://www.afrp.net）、账号、密码，
可选勾选「顺带重置客户端密钥」（用官网侧当前密钥覆盖本机），点击导入。插件会：

1. 调官网 `/api/config.php` 拉取 OIDC 参数（issuer/audience/scope/token 地址）；
2. 用账号密码调 `/api/login.php` 换临时令牌；
3. 拉取 `/api/servers.php` 服务器列表，直接「设为当前服务器」；
4. 若勾选重置，则调用 `/api/secret.php` 生成新的 client_id / client_secret 并写入本机。

> 密码与令牌仅写入 /tmp 临时文件，调用完立即删除，不落盘。

### frpc 核心更新

「运行状态 → 核心更新」会自动检测路由器架构（读 /etc/openwrt_release，回退 uname -m），
从官网下载清单 manifest.json 中匹配 `frpc / openwrt / 最新` 条目，核对 sha256 后安装到
`/usr/bin/frpc`。更新过程：下载 → 校验 → 解压 → 新文件预检（架构探测）→ 备份 → 原子替换，
失败自动回滚，不会把正在运行的 frpc 覆盖坏。

frp 官方发布名与清单 arch 字段对照（清单由我们维护，会做映射）：

| frp 官方文件名 | 清单 arch | 常见机型 |
| --- | --- | --- |
| frp_*_linux_amd64 | amd64 | x86_64 软路由 |
| frp_*_linux_arm64 | arm64 | 现代 ARM 路由（如 R2S/R4S 之外的新片） |
| frp_*_linux_arm | arm | armv7 老款路由 |
| frp_*_linux_mips | mips | 大端 MIPS（少见） |
| frp_*_linux_mipsle | mipsle | 主流 MT7620/7621（如 K2P、Newifi） |
| frp_*_linux_mips64 / mips64le | mips64 / mips64le | 高性能 MIPS |
| frp_*_linux_riscv64 | riscv64 | RISC-V 开发板 |

自动检测不准时，可在「基础设置 → 核心架构」手动指定。

## 排障

- 服务起不来：`logread | grep afrp` 看原因；也可在「运行状态」页看日志卡（最近 50 条）。
- 常见原因：未填 client_id/secret、隧道字段不合法（日志会给出具体行）、frpc 未安装。
- 手动命令：
  ```sh
  /etc/init.d/afrp start|stop|restart
  /usr/libexec/afrp/update-core status
  /usr/libexec/afrp/update-core check https://www.afrp.net amd64
  ```
- 配置文件校验：`uci show afrp`；重新渲染：`/etc/init.d/afrp restart`。

## 打包与发布（维护者）

```sh
# 本机直接打包（需要 PHP，无需 OpenWrt SDK）
php tools/build-ipk.php --verify

# 打包并发布到网站下载中心（拷贝文件 + 登记 manifest.json）
php tools/build-ipk.php --verify \
    --site-root D:/ProjectData/frp-oidc-php/web \
    --site-url https://www.afrp.net \
    --notes "LuCI 插件 v1.1.0"
```

发布条目固定为两条（kind=app, platform=openwrt, arch=all）：
`channel=ipk`（.ipk，opkg 安装）与 `channel=portable`（.tar.gz，install.sh 安装），
id 由 channel 决定（确定性 md5 前缀），重复发布会原地更新而不是新增。

## 已知限制

- 尚未在真机路由器上完整实测（本地仅做格式自检 `--verify` 与脚本语法检查）；
  首次上机建议先 `logread -f` 观察。
- uhttpd 上传/下载在部分老固件上需 `luci-base` 已装（一般默认都有）。
- OIDC 令牌有效期与 frpc 重连相关；断线由 procd 自动拉起并重新认证。
