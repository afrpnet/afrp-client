# AFRP OIDC Client 文档

多端内网穿透客户端（frp-oidc-app），与网站共用同一账号体系：不需要注册新账号，
用网页端账号登录后，选择服务器并配置隧道即可连接；OIDC 认证字段（clientID /
clientSecret / tokenEndpoint 等）全部由客户端自动填写，无需手动配置 frpc。

## 平台支持矩阵

| 平台 | 版本状态 | 安装包形式 | 内置 frpc（连接功能） |
| --- | --- | --- | --- |
| Windows 10/11（x64） | 已发布 | 免安装，解压即用 | 支持（frpc 0.71.0） |
| Android 7.0+ | 测试版 | app-debug.apk | 暂未提供，后续版本开放 |
| HarmonyOS / OpenHarmony | 测试版 | entry-default-signed.hap（仅 OpenHarmony 设备/模拟器） | 暂未提供，后续版本开放 |
| iOS | 规划中 | 待 Apple 签名与 macOS 构建环境 | 规划中 |
| Linux / macOS | 源码可构建（未实测、未提供安装包） | 自行构建 | 代码已内置对应 frpc 二进制 |

> Android / 鸿蒙测试版已可登录、查看会员与消息、修改设置（插件适配与运行测试持续进行中）；
> 「连接」功能暂未提供，隧道可提前配置好，后续版本直接复用，连接按钮会提示平台暂不支持。

## 文档索引

- [用户手册](user-guide.md) — 登录、连接、隧道、会员、消息、设置全流程说明
- [各平台安装说明](install.md) — Windows / Android / 鸿蒙 / iOS / Linux / macOS
- [常见问题 FAQ](faq.md) — 连接失败、密钥、支付、名称与 Logo 自定义等

开发者文档（工具链、构建、签名）见仓库根目录 [README](../README.md)。
