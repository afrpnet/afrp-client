#!/usr/bin/env bash
# 把 Flutter Linux bundle 打成 .deb（CI 调用，amd64/arm64 共用）
# 用法: tool/make-deb.sh <amd64|arm64> <bundle-dir> <output-dir>
set -euo pipefail

ARCH="${1:?usage: make-deb.sh <amd64|arm64> <bundle-dir> <output-dir>}"
STAGE="${2:?bundle dir required}"
OUT="${3:-dist}"

case "$ARCH" in
  amd64|arm64) ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

VER=$(grep '^version:' pubspec.yaml | sed -E 's/version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
[ -d "$STAGE" ] || { echo "bundle not found: $STAGE" >&2; exit 1; }

rm -rf "$STAGE/data/flutter_assets/assets/frpc/windows" "$STAGE/data/flutter_assets/assets/frpc/macos"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/afrp-oidc-client" "$ROOT/usr/bin" \
         "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/512x512/apps" \
         "$ROOT/usr/share/pixmaps"
cp -a "$STAGE/." "$ROOT/opt/afrp-oidc-client/"
ln -s /opt/afrp-oidc-client/afrp_oidc "$ROOT/usr/bin/afrp_oidc"

ICON_SRC="$ROOT/opt/afrp-oidc-client/data/flutter_assets/assets/brand/app_icon.png"
cp "$ICON_SRC" "$ROOT/usr/share/icons/hicolor/512x512/apps/net.afrp.frp_oidc_app.png"
# 少数桌面环境/启动器仍从 pixmaps 取图标
cp "$ICON_SRC" "$ROOT/usr/share/pixmaps/net.afrp.frp_oidc_app.png"

cat > "$ROOT/usr/share/applications/net.afrp.frp_oidc_app.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AFRP OIDC Client
Name[zh_CN]=AFRP OIDC 客户端
GenericName=FRP Tunneling Client
GenericName[zh_CN]=内网穿透客户端
Comment=AFRP OIDC 内网穿透客户端
Comment[zh_CN]=AFRP OIDC 内网穿透客户端
Exec=/opt/afrp-oidc-client/afrp_oidc
Icon=net.afrp.frp_oidc_app
Terminal=false
Categories=Network;RemoteAccess;
Keywords=frp;tunnel;内网穿透;穿透;OIDC;
StartupNotify=true
StartupWMClass=net.afrp.frp_oidc_app
EOF

cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# 以 root 运行，$SUDO_USER/$PKEXEC_UID 指向发起安装的桌面用户
set -e

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true

# 读取用户的 XDG 桌面目录（中文系统通常是 ~/桌面）
desktop_dir_for() {
	home=$1
	dir=""
	if [ -f "$home/.config/user-dirs.dirs" ]; then
		line=$(grep -m1 '^XDG_DESKTOP_DIR=' "$home/.config/user-dirs.dirs" 2>/dev/null || true)
		dir=${line#XDG_DESKTOP_DIR=}
		dir=${dir%\"}
		dir=${dir#\"}
	fi
	case "$dir" in
		'$HOME'/*) dir="$home/${dir#\$HOME/}" ;;
	esac
	[ -n "$dir" ] || dir="$home/Desktop"
	printf '%s\n' "$dir"
}

# 首次安装/升级时为发起安装的用户补一个桌面启动图标（XFCE/GNOME/KDE 等通用）
if [ "$1" = "configure" ]; then
	user=""
	if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
		user="$SUDO_USER"
	elif [ -n "${PKEXEC_UID:-}" ]; then
		user=$(getent passwd "$PKEXEC_UID" 2>/dev/null | cut -d: -f1 || true)
	fi
	if [ -n "$user" ] && [ "$user" != "root" ]; then
		home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)
		if [ -n "$home" ] && [ -d "$home" ]; then
			dir=$(desktop_dir_for "$home")
			shortcut="$dir/net.afrp.frp_oidc_app.desktop"
			if [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null; then
				if [ ! -e "$shortcut" ]; then
					install -o "$(id -u "$user")" -g "$(id -g "$user")" -m 0755 \
						/usr/share/applications/net.afrp.frp_oidc_app.desktop "$shortcut" 2>/dev/null || true
				fi
			fi
		fi
	fi
fi

exit 0
EOF

cat > "$ROOT/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true

# 卸载时清掉安装时放到用户桌面的启动图标（只删我们写入的那个）
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	for home in /root /home/*; do
		[ -d "$home" ] || continue
		dir=""
		if [ -f "$home/.config/user-dirs.dirs" ]; then
			line=$(grep -m1 '^XDG_DESKTOP_DIR=' "$home/.config/user-dirs.dirs" 2>/dev/null || true)
			dir=${line#XDG_DESKTOP_DIR=}
			dir=${dir%\"}
			dir=${dir#\"}
		fi
		case "$dir" in
			'$HOME'/*) dir="$home/${dir#\$HOME/}" ;;
		esac
		for candidate in "$dir" "$home/Desktop"; do
			[ -n "$candidate" ] || continue
			f="$candidate/net.afrp.frp_oidc_app.desktop"
			if [ -f "$f" ] && grep -q '^Exec=/opt/afrp-oidc-client/afrp_oidc$' "$f"; then
				rm -f "$f"
			fi
		done
	done
fi

exit 0
EOF
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"

mkdir -p "$ROOT/debian"
cat > "$ROOT/debian/control" <<'EOF'
Source: afrp-oidc-client
Section: net
Priority: optional
Maintainer: afrpnet <afrpnet@users.noreply.github.com>
Standards-Version: 4.6.1

Package: afrp-oidc-client
Architecture: any
Description: AFRP OIDC 内网穿透客户端
EOF
DEPENDS=$(cd "$ROOT" && dpkg-shlibdeps -O opt/afrp-oidc-client/afrp_oidc opt/afrp-oidc-client/lib/*.so 2>/dev/null | sed -n 's/^shlibs:Depends=//p' | head -1)
[ -n "$DEPENDS" ] || DEPENDS="libgtk-3-0, libstdc++6, libsecret-1-0, libayatana-appindicator3-1"
SIZE=$(du -sk "$ROOT/opt" | cut -f1)
cat > "$ROOT/DEBIAN/control" <<EOF
Package: afrp-oidc-client
Version: $VER
Architecture: $ARCH
Maintainer: afrpnet <afrpnet@users.noreply.github.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: net
Priority: optional
Homepage: https://www.afrp.net
Description: AFRP OIDC 内网穿透客户端
 基于 OIDC 认证的 frp 客户端，带图形界面与自动连接。
EOF
rm -rf "$ROOT/debian"

mkdir -p "$OUT"
DEB="$OUT/afrp-oidc-client_${VER}_linux_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$ROOT" "$DEB"
dpkg-deb --info "$DEB"
