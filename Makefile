include $(TOPDIR)/rules.mk

PKG_NAME:=frp
PKG_VERSION:=0.70.26
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/laosan-xx/frp/tar.gz/v${PKG_VERSION}?
PKG_HASH:=e67d6e20d8ceb5138b6efeaef05af9705aa07668946be60a2745f91d524b5651

PKG_MAINTAINER:=
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/laosan-xx/frp
GO_PKG_BUILD_PKG:=github.com/laosan-xx/frp/cmd/...

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	$(call Build/Prepare/Default)
	mkdir -p $(PKG_BUILD_DIR)/web/frpc/dist
	mkdir -p $(PKG_BUILD_DIR)/web/frps/dist
	touch $(PKG_BUILD_DIR)/web/frpc/dist/index.html
	touch $(PKG_BUILD_DIR)/web/frps/dist/index.html
endef

include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/frp/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/frp/$(2).d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/conf/$(2)_full_example.toml $(1)/etc/frp/$(2).d/
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) ./files/$(2).config $(1)/etc/config/$(2)
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/$(2).init $(1)/etc/init.d/$(2)

	if [ -r ./files/$(2).uci-defaults ]; then \
		$(INSTALL_DIR) $(1)/etc/uci-defaults; \
		$(INSTALL_DATA) ./files/$(2).uci-defaults $(1)/etc/uci-defaults/$(2); \
	fi
endef

define Package/frp/template
  define Package/$(1)
    SECTION:=net
    CATEGORY:=Network
    SUBMENU:=Web Servers/Proxies
    TITLE:=$(1) - fast reverse proxy $(2)
    URL:=https://github.com/laosan-xx/frp
    DEPENDS:=$(GO_ARCH_DEPENDS)
  endef

  define Package/$(1)/description
    $(1) is a fast reverse proxy $(2) to help you expose a local server behind
    a NAT or firewall to the internet.
  endef

  define Package/$(1)/conffiles
/etc/config/$(1)
  endef

  define Package/$(1)/install
    $(call Package/frp/install,$$(1),$(1))
  endef
endef

$(eval $(call Package/frp/template,frpc,client))
$(eval $(call Package/frp/template,frps,server))
$(eval $(call BuildPackage,frpc))
$(eval $(call BuildPackage,frps))
