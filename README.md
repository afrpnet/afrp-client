# frp-oidc-app

FRP + OIDC 多端客户端（Windows / Android / HarmonyOS / iOS 计划中），与 frp-oidc-php 共用数据库，通过 Bearer-token API 认证。

> 用户与安装文档见 [docs/](docs/README.md)：[用户手册](docs/user-guide.md)、
> [各平台安装说明](docs/install.md)、[常见问题 FAQ](docs/faq.md)。

## 工具链（均安装在 D 盘）

| 组件 | 路径 |
| --- | --- |
| Flutter (OpenHarmony 分支) | `D:\dev\flutter-ohos` |
| Node.js 18 | `D:\dev\node18` |
| JDK 17 | `D:\dev\jdk-17.0.2` |
| OHOS 命令行工具 (ohpm) | `D:\dev\harmony-tools\oh-command-line-tools\ohpm` |
| OpenHarmony SDK 26 (7.0-Beta1) | `D:\dev\harmony-sdk\26` |
| Android SDK / 模拟器 | `D:\dev\android-sdk`、AVD `frp_pixel` |

## 构建命令

### Windows 桌面端
```
flutter build windows
```

### 鸿蒙 HAP
```
cd ohos
export JAVA_HOME="D:\\dev\\jdk-17.0.2"
export PATH="/d/dev/node18:/d/dev/jdk-17.0.2/bin:/d/dev/harmony-tools/oh-command-line-tools/ohpm/bin:$PATH"
flutter build hap --debug      # 或 cd ohos && ./hvigorw.bat assembleHap -p product=default -p buildMode=debug
```

产物：`build\ohos\hap\entry-default-signed.hap`

## HarmonyOS 构建 FAQ（防重复踩坑）

### 1. 签名密码必须是加密密文（hvigor ≥ 5.19.8）
`build-profile.json5` 里 `storePassword` / `keyPassword` 不能是明文。hvigor 的 DecipherUtil 要求它们是 hex 编码的 AES-GCM 密文（布局 `BE32(ct+16) || iv(12) || ct || tag(16)`），解密密钥来自 **`<storeFile 所在目录>/material/{fd/0,fd/1,fd/2,ac,ce}`**（DevEco Studio 自动生成，纯 CLI 环境没有）。

本仓库提供 `ohos/gen-signing-material.js` 自动生成：
```
node gen-signing-material.js           # 确保 material 存在 + 改写 build-profile.json5 密码
node gen-signing-material.js --force   # 重新生成 material
node gen-signing-material.js --verify  # 自检（用插件自带样本解密出 "DebugKey"）
```
密钥推导（逆向自插件 `src/utils/decipher-util.js`）：
`root = pbkdf2_sha256(utf8(xor(fd0,fd1,fd2,COMPONENT)), salt, 10000, 16)`，`key = AES-128-GCM.decrypt(root, ce)`。
明文密码为 `LocalTestSignPassword_1234567890ab`（hap-sign-tool 手工签名时用这个）。

### 2. 应用证书叶子必须由 CA 签发
`signature/OpenHarmonyApplication.pem` 必须是 ≥2 张的证书链，且 **leaf 不能是自签证书**（自签报 `11013002 verify certificate chain failed`，单张报 `11013004 Profile cert must a cert chain`）。
SDK 自带的 `OpenHarmony.p12` 里 `openharmony application release` 是自签证书，但同库内有 **`openharmony application ca` 的 CA 私钥**，可用 `hap-sign-tool generate-cert` 重签：
```
java -jar <sdk>/26/toolchains/lib/hap-sign-tool.jar generate-cert \
  -keyAlias "openharmony application release" -keyPwd LocalTestSignPassword_1234567890ab \
  -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
  -issuerKeyAlias "openharmony application ca" -issuerKeyPwd LocalTestSignPassword_1234567890ab \
  -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release" \
  -validity 1095 -keyUsage digitalSignature -extKeyUsage codeSignature -signAlg SHA256withECDSA \
  -keystoreFile signature/OpenHarmony.p12 -keystorePwd LocalTestSignPassword_1234567890ab \
  -outFile new_leaf.pem
```
`gen-signing-material.js` 已内置该步骤（检测到自签自动重签，旧文件备份为 `.selfsigned.bak`）。

### 3. p12 密码长度限制
签名库密码必须 **≥32 字符**，否则 hvigor 报 `00303116`。本工程统一用 `LocalTestSignPassword_1234567890ab`（PKCS12 格式下 key 密码跟随 store 密码，无法单独改）。

### 4. 签名验证
```
java -jar <sdk>/26/toolchains/lib/hap-sign-tool.jar verify-app \
  -inFile build/ohos/hap/entry-default-signed.hap \
  -outCertChain out.cer -outProfile out.p7b
```
预期结尾输出 `verify: Verify success`，证书链为 `Release(CA 签发) ← Root CA ← Application CA`。

### 5. `ohpm install` 后必须重新打补丁
`@ohos/flutter_ohos` har 是按华为 HarmonyOS SDK 编译的（`KeyEvent.isCapsLockOn`），OpenHarmony SDK 26 只有 `capsLock` 字段。每次 `ohpm install` 后运行：
```
node ohos/patch-flutter-ohos-har.js
```

### 6. hvigor 缓存目录双哈希
`flutter build hap` 与直接 `hvigorw` 会算出不同的 project_caches 哈希目录，导致 node_modules 重复安装/找不到。若新哈希目录缺失，运行（管理员）：
```
ohos\link-workspace-cache.bat   # 把已安装的 workspace junction 到新哈希目录
```

### 7. 构建产物体积
debug HAP 约 170–210MB（含 Flutter debug 引擎符号），release 构建会显著缩小。

### 8. 模拟器/真机安装限制
- 本工程使用 **OpenHarmony 测试签名**（SDK 自带证书+profile），仅能安装到 **OpenHarmony 设备/模拟器**。
- **HarmonyOS NEXT 真机** 需要华为开发者账号的云签名（AGC 申请证书 + profile），无法用测试签名安装。
