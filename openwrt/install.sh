#!/bin/sh
# luci-app-afrp 通用安装脚本（OpenWrt，在解压后的目录内执行）
#   ./install.sh             安装或升级（保留已有 /etc/config/afrp）
#   ./install.sh uninstall           卸载（保留配置）
#   ./install.sh uninstall --purge   卸载并删除配置
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$DIR/files"

die() { echo "错误: $1" >&2; exit 1; }
say() { echo "$1"; }

[ "$(id -u)" = "0" ] || die "请用 root 运行（ssh 登录路由器后执行）。"

LUCI_CLEAN='rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true'

stop_service() {
    if [ -x /etc/init.d/afrp ]; then
        /etc/init.d/afrp stop 2>/dev/null || true
    fi
}

enable_and_reload() {
    [ -x /etc/init.d/afrp ] && /etc/init.d/afrp enable 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload 2>/dev/null || true
}

case "${1:-install}" in
    install)
        [ -d "$FILES" ] || die "未找到 files/ 目录，请在解压后的 luci-app-afrp-* 目录内运行。"
        [ -x /etc/init.d/rpcd ] || say "提示: 未检测到 rpcd，可能不是 OpenWrt 系统，继续安装。"

        TMP="/tmp/afrp-install.$$"
        rm -rf "$TMP"
        mkdir -p "$TMP"
        cp -r "$FILES"/. "$TMP"/

        # 升级时不覆盖用户已有配置
        if [ -f /etc/config/afrp ]; then
            rm -f "$TMP/etc/config/afrp"
            say "检测到已有 /etc/config/afrp，保留现有配置。"
        fi

        stop_service
        cp -r "$TMP"/. /
        rm -rf "$TMP"

        # 权限兜底（Windows 打包无 exec 位）
        chmod 755 /etc/init.d/afrp 2>/dev/null || true
        chmod 600 /etc/config/afrp 2>/dev/null || true
        for f in /usr/libexec/afrp/render /usr/libexec/afrp/update-core /usr/libexec/afrp/import-account; do
            [ -f "$f" ] && chmod 755 "$f"
        done

        $LUCI_CLEAN
        enable_and_reload

        if [ -x /etc/init.d/afrp ] && /etc/init.d/afrp enabled 2>/dev/null; then
            /etc/init.d/afrp restart 2>/dev/null || true
        fi

        say ""
        say "安装完成。"
        if [ ! -x /usr/bin/frpc ]; then
            say "提示: 未检测到 /usr/bin/frpc，请打开 LuCI「服务 → AFRP frpc → 运行状态」在线安装 frpc 核心。"
        fi
        say "入口: LuCI 菜单「服务 → AFRP frpc」（基础设置 / 隧道管理 / 运行状态）。"
        ;;
    uninstall)
        stop_service
        /etc/init.d/afrp disable 2>/dev/null || true

        rm -f /etc/init.d/afrp
        rm -f /usr/share/luci/menu.d/luci-app-afrp.json
        rm -f /usr/share/rpcd/acl.d/luci-app-afrp.json
        rm -rf /usr/libexec/afrp
        rm -rf /www/luci-static/resources/view/afrp
        rm -f /var/etc/afrp.toml

        if [ "${2:-}" = "--purge" ]; then
            rm -f /etc/config/afrp
            say "已删除 /etc/config/afrp（--purge）。"
        else
            say "已保留 /etc/config/afrp（如需删除: ./install.sh uninstall --purge）。"
        fi

        rm -f /tmp/afrp-import.json /tmp/afrp-login.json
        $LUCI_CLEAN
        /etc/init.d/rpcd restart 2>/dev/null || true
        [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload 2>/dev/null || true
        say "卸载完成。"
        ;;
    *)
        say "用法: ./install.sh [uninstall [--purge]]"
        exit 1
        ;;
esac
