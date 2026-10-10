include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-afrp
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=AFRP <https://www.afrp.net>

LUCI_TITLE:=AFRP - NAT Traversal Client
LUCI_DESCRIPTION:=AFRP NAT traversal support and management by afrp.net. \
Manage frpc tunnels with OIDC authentication, auto-update frpc core, \
and monitor connection status from LuCI.

LUCI_DEPENDS:=+uclient-fetch +ca-bundle
LUCI_PKGARCH:=all

# Feeds layout: package/luci-app-afrp/Makefile  -> ../../luci.mk
# SDK layout:   package/luci-app-afrp/Makefile  -> $(TOPDIR)/feeds/luci/luci.mk
LUCIMK:=$(firstword $(wildcard ../../luci.mk $(TOPDIR)/feeds/luci/luci.mk))
ifeq ($(LUCIMK),)
  $(error luci.mk not found: place this package under feeds/luci/applications or an SDK package/ dir)
endif
include $(LUCIMK)
