# Linux 版本构建指南

## 快速开始（推荐：使用 WSL2）

### 1. 安装 WSL2 Ubuntu

在 **PowerShell（管理员）** 中执行：

```powershell
# 安装 WSL2 和 Ubuntu
wsl --install -d Ubuntu-22.04

# 重启后设置用户名密码
```

### 2. 在 WSL2 中安装依赖

```bash
# 进入 WSL
wsl

# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装 Flutter Linux 依赖
sudo apt install -y \
    clang cmake ninja-build \
    pkg-config libgtk-3-dev \
    liblzma-dev libstdc++-12-dev \
    xz-utils wget git

# 安装 Flutter（如果尚未安装）
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
flutter precache
flutter doctor

# 启用 Linux 桌面支持
flutter config --enable-linux-desktop
```

### 3. 构建 Linux 版本

```bash
# 进入项目目录（WSL 中访问 Windows 文件）
cd /mnt/d/ProjectData/frp-oidc-app

# 获取依赖
flutter pub get

# 构建便携版（tar.gz）
bash tool/build_linux.sh

# 或构建 AppImage（可选）
bash tool/build_linux_appimage.sh
```

产物位于 `dist/` 目录。

---

## 原生 Linux 构建

如果在原生 Linux 环境中，步骤相同：

```bash
# 1. 安装依赖（Ubuntu/Debian）
sudo apt install -y \
    clang cmake ninja-build \
    pkg-config libgtk-3-dev \
    liblzma-dev xz-utils wget git

# 2. 安装 Flutter
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
flutter precache
flutter config --enable-linux-desktop

# 3. 构建
cd /path/to/frp-oidc-app
flutter pub get
bash tool/build_linux.sh
```

---

## 产物说明

### 便携版 (tar.gz)

```
afrp-oidc-client_1.1.0_linux_amd64_portable.tar.gz
```

安装使用：
```bash
# 解压
mkdir -p ~/afrp-oidc
tar -xzf afrp-oidc-client_1.1.0_linux_amd64_portable.tar.gz -C ~/afrp-oidc

# 运行
~/afrp-oidc/afrp-oidc.sh

# (可选) 安装桌面快捷方式
cp ~/afrp-oidc/usr/share/applications/afrp-oidc.desktop ~/.local/share/applications/
```

### AppImage

```
afrp-oidc-client_1.1.0_linux_amd64.appimage
```

使用：
```bash
chmod +x afrp-oidc-client_1.1.0_linux_amd64.appimage
./afrp-oidc-client_1.1.0_linux_amd64.appimage
```

---

## 系统要求

- **GTK 3.0** 或更高版本
- **glibc 2.27** 或更高版本（Ubuntu 18.04+）
- **X11** 或 **Wayland** 显示服务器

---

## 故障排除

### GTK 未找到

```bash
# Ubuntu/Debian
sudo apt install libgtk-3-dev

# Fedora
sudo dnf install gtk3-devel

# Arch
sudo pacman -S gtk3
```

### Flutter doctor 报告问题

```bash
flutter doctor -v
```

确保 Linux toolchain 显示为 ✓。

### 构建失败：找不到 liblzma

```bash
# Ubuntu/Debian
sudo apt install liblzma-dev

# Fedora
sudo dnf install xz-devel
```

---

## 自动化构建（CI/CD）

GitHub Actions 示例：

```yaml
name: Build Linux

on:
  push:
    tags: ['v*']

jobs:
  build-linux:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y \
            clang cmake ninja-build \
            pkg-config libgtk-3-dev \
            liblzma-dev xz-utils
      
      - name: Install Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
      
      - name: Build
        run: |
          flutter config --enable-linux-desktop
          flutter pub get
          bash tool/build_linux.sh
      
      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: linux-portable
          path: dist/*.tar.gz
```
