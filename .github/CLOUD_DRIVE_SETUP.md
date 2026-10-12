# 网盘自动上传配置指南

CI 构建完成后会自动上传产物到国内网盘，方便用户下载。

## 坚果云 WebDAV

### 1. 获取应用密码
1. 登录 [坚果云](https://www.jianguoyun.com/)
2. 点击右上角头像 → 账户信息 → 安全选项
3. 找到"第三方应用管理" → 添加应用
4. 记录生成的**应用密码**

### 2. 添加 GitHub Secrets
在 GitHub 仓库 Settings → Secrets and variables → Actions 中添加：

| Secret 名称 | 值 |
|------------|-----|
| `JGY_USERNAME` | 你的坚果云登录邮箱/手机号 |
| `JGY_PASSWORD` | 上面生成的应用密码（不是登录密码！） |

### 3. 下载链接格式
```
https://www.jianguoyun.com/p/{文件名}
```

---

## 123 云盘 OpenAPI

### 1. 申请 API 凭证
1. 访问 [123 云盘开放平台](https://www.123pan.com/developer)
2. 登录并创建应用
3. 获取 `Client ID` 和 `Client Secret`

### 2. 添加 GitHub Secrets
在 GitHub 仓库 Settings → Secrets and variables → Actions 中添加：

| Secret 名称 | 值 |
|------------|-----|
| `PAN123_CLIENT_ID` | 你的 Client ID |
| `PAN123_CLIENT_SECRET` | 你的 Client Secret |

### 3. 下载链接格式
```
https://www.123pan.com/s/{fileId}
```

---

## 注意事项

- 如果某个网盘的 secret 未设置，该网盘的上传步骤会跳过（`if: env.XXX != ''`）
- 上传失败不会导致整个 CI 失败（`|| true`）
- 下载链接会在 CI 日志中输出，可在 Actions 页面查看
- 坚果云免费版每月 1GB 上传流量，大文件注意流量限制
