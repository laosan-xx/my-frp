include $(TOPDIR)/rules.mk

PKG_NAME:=frp
# 自动取 GitHub 最新 release 版本号（结果缓存 1 小时到 $(TOPDIR)/tmp，限流/离线则构建失败）
FPR_LATEST_CACHE:=$(TOPDIR)/tmp/.frp-latest-$(PKG_NAME)
PKG_VERSION:=$(shell \
  if [ -s "$(FPR_LATEST_CACHE)" ]; then \
    mtime=$$(stat -c %Y "$(FPR_LATEST_CACHE)" 2>/dev/null || echo 0); \
    if [ $$(($$(date +%s) - mtime)) -lt 3600 ]; then cat "$(FPR_LATEST_CACHE)"; exit 0; fi; \
  fi; \
  v=$$(curl -fsSL --connect-timeout 5 "https://gh.2026178.xyz/api/repos/laosan-xx/frp/releases/latest" 2>/dev/null | grep -o '"tag_name": *"v[^"]*"' | grep -o '[0-9.]*'); \
  if [ -n "$$v" ]; then mkdir -p "$$(dirname "$(FPR_LATEST_CACHE)")"; echo "$$v" > "$(FPR_LATEST_CACHE)"; echo "$$v"; fi)
PKG_RELEASE:=1

# 预编译二进制来自公开 release（源码在私有库 laosan-xx/frp-diy，不参与 OpenWrt 编译）
PKG_SOURCE_URL:=https://github.com/laosan-xx/frp/releases/download/v$(PKG_VERSION)/

# 按目标架构选择 release asset（PKG_VERSION 自动取最新 release，无需手改）
# （PKG_HASH 故意省略：OpenWrt 对空 PKG_HASH 仅 warning、跳过校验，免去每次更新）
ifeq ($(ARCH),x86_64)
  PKG_SOURCE:=frp_$(PKG_VERSION)_linux_amd64.tar.gz
endif
ifeq ($(ARCH),aarch64)
  PKG_SOURCE:=frp_$(PKG_VERSION)_linux_arm64.tar.gz
endif
ifeq ($(ARCH),mipsel)
  PKG_SOURCE:=frp_$(PKG_VERSION)_linux_mipsle.tar.gz
endif
ifeq ($(ARCH),mips)
  PKG_SOURCE:=frp_$(PKG_VERSION)_linux_mips.tar.gz
endif
ifeq ($(ARCH),arm)
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    PKG_SOURCE:=frp_$(PKG_VERSION)_linux_arm.tar.gz
  else
    PKG_SOURCE:=frp_$(PKG_VERSION)_linux_arm_hf.tar.gz
  endif
endif

PKG_MAINTAINER:=
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

# 不支持的架构直接报错，避免下载阶段出现晦涩错误
define Build/Prepare
	[ -n "$(PKG_SOURCE)" ] || { \
		echo "ERROR: frp $(PKG_VERSION) 没有对应预编译包，ARCH=$(ARCH) (SUBTARGET=$(SUBTARGET))"; \
		exit 1; \
	}
	$(call Build/Prepare/Default)
endef

# 不编译，直接使用发布的二进制
define Build/Compile
	true
endef

# 最终程序用发布的二进制，其余配置文件（init/UCI/uci-defaults）用本项目的 files/
define Package/frp/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(2) $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/frp/$(2).d/
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
    DEPENDS:=
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
$(eval $(call BuildPackage,frpc))
