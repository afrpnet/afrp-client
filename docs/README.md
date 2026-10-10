# AFRP OIDC Client 文档

多端内网穿透客户端，与网站共用同一账号体系：用网页端账号登录后，选择服务器并配置隧道即可连接。OIDC 认证字段全部由客户端自动填写，无需手动配置 frpc。

## 平台支持

| 平台 | 状态 | 安装方式 |
| --- | --- | --- |
| Windows 10/11（x64） | 已发布 | 安装版 / 免安装版 |
| macOS（Apple Silicon / Intel） | 已发布 | zip 解压 |
| Linux（amd64 / arm64） | 已发布 | tar.gz 解压 |
| Android 7.0+ | 已发布 | APK 安装 |
| HarmonyOS / OpenHarmony | 测试版 | HAP 侧载 |
| OpenWrt | 已发布 | IPK 安装 |

## 文档

- [用户手册](user-guide.md) — 登录、连接、隧道、消息、设置
- [安装说明](install.md) — 各平台详细安装步骤
- [常见问题](faq.md) — 连接失败、密钥、平台兼容性等
