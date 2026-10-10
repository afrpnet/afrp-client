# 各平台安装说明

## Windows 10/11（x64）— 已发布

免安装，解压即用，不需要管理员权限。

1. 获取 Windows 版压缩包并解压到任意目录，例如 `D:\FRP客户端\`。
   注意：要复制**整个文件夹**（包含 `afrp_oidc.exe`、若干 `.dll` 和 `data\` 子目录），
   不能只拷 exe。
2. 双击 `afrp_oidc.exe` 启动。
3. 首次运行如弹出「Windows 已保护你的电脑」（SmartScreen），点
   「更多信息」→「仍要运行」。这是因为客户端未购买代码签名证书，属正常现象。
4. 按 [用户手册 · 首次使用](user-guide.md#首次使用四步) 登录并配置。

其他说明：

- **连接功能**：内置 frpc 0.71.0，首次连接时自动释放到本机数据目录，无需单独安装 frpc。
- **升级**：关闭程序后，用新版本文件夹的内容覆盖旧目录即可；本机数据保存在
  `%APPDATA%\net.afrp\AFRP OIDC Client\`，不受覆盖影响（登录状态、密钥、隧道都保留）。
- **卸载**：删除程序文件夹即可；如需同时清除本机数据，再删除
  `%APPDATA%\net.afrp\AFRP OIDC Client\`。
- **从源码构建**：`flutter build windows`，产物在 `build\windows\x64\runner\Release\`。
  工具链与注意事项见仓库根目录 [README](../README.md)。

## Android 7.0+ — 测试版

当前为开发测试包（debug APK），用于功能体验与验证。

1. 获取 `app-debug.apk`（仓库内路径：`build\app\outputs\flutter-apk\app-debug.apk`）。
2. 传到手机后点击安装。系统会提示允许「安装未知应用」，按提示为文件管理器 /
   浏览器开启该权限后继续安装。
3. 也可以连接电脑后用 adb 安装：`adb install app-debug.apk`。
4. 安装后桌面图标名称为「AFRP OIDC Client」，包名 `net.afrp.frp_oidc_app`。

当前能力与限制：

- 桌面端功能（登录、会员、消息、设置）在 Android 上一致，插件适配与运行测试持续进行中。
- **暂不可用：连接**。点击「连接服务器」会提示
  「当前平台暂不支持内置 frpc（Android 版将在后续版本提供）」。
  隧道可以提前配置好，后续版本升级后直接使用。
- 后续版本（release 包）将内置 Android 版 frpc；正式对外分发前需改用 release 构建，
  并配置正式签名。

## HarmonyOS / OpenHarmony — 测试版

当前为 OpenHarmony 测试签名包，**只能安装到 OpenHarmony 设备或模拟器**，
不能安装到 HarmonyOS NEXT 手机（真机需要华为开发者账号的云签名，见根 README FAQ 8）。

1. 获取 `entry-default-signed.hap`（仓库内路径：`build\ohos\hap\entry-default-signed.hap`）。
2. 用 DevEco Studio 打开工程后安装到模拟器/设备，或使用命令行：
   `hdc install entry-default-signed.hap`。
3. 应用名称为「AFRP OIDC Client」，bundleName 为 `net.afrp.frp_oidc_app`。

当前能力与限制：

- 构建与签名已打通；登录、会员、消息、设置等功能的插件适配与运行测试持续进行中。
- **暂不可用：连接**（提示内容同 Android，后续版本提供）。
- 从源码构建：`flutter build hap --debug`；签名、缓存等常见问题见根 README
  「HarmonyOS 构建 FAQ」。

## iOS — 规划中

尚未创建 iOS 工程，暂不提供安装包。规划要点：

- 需要 macOS + Xcode 构建环境；分发需要 Apple 开发者账号（TestFlight 或企业签名）。
- frpc 无法像桌面端那样直接释放可执行文件，计划以 gomobile 打包成
  xcframework 嵌入（详见任务 #19「iOS 工程准备与 Mac/CI 构建方案」）。

## Linux / macOS — 源码可构建

代码中已内置对应平台的 frpc（Linux amd64、macOS amd64），但尚未提供官方安装包、未实测。

- 在对应系统上自行构建：
  - Linux：`flutter build linux`，产物为可执行文件及 `data/` 目录；
  - macOS：`flutter build macos`，产物为 `.app`，首次运行需在
    「系统设置 → 隐私与安全性」中允许。
- macOS 版 frpc 以 `tar.gz` 资源形式随包分发、运行时解压，
  用于规避杀毒软件对 frpc 二进制的误报。
