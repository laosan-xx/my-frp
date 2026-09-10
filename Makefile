include $(TOPDIR)/rules.mk

PKG_NAME:=frp

# 兜底版本：仅当所有 API 都访问不到、且本地也没有缓存时启用，保证 PKG_VERSION 永不为空
FRP_FALLBACK_VERSION:=0.80.9

# 查询结果缓存到 $(TOPDIR)/tmp，1 小时内不再联网
FRP_LATEST_CACHE:=$(TOPDIR)/tmp/.frp-latest-$(PKG_NAME)

# 依次尝试的 API，取第一个可用的（GitHub 官方 + GH 镜像；CI 里官方 API 通常直连可用）
FRP_LATEST_APIS:= \
	https://api.github.com/repos/laosan-xx/frp/releases/latest \
	https://gh.2026178.xyz/api/repos/laosan-xx/frp/releases/latest \
	https://ghfast.top/https://api.github.com/repos/laosan-xx/frp/releases/latest

# 取版本号：有效缓存 -> 逐个 API -> 过期缓存 -> 兜底版本（任何情况下都保证有输出）
FRP_LATEST=\
  cached=$$(cat "$(FRP_LATEST_CACHE)" 2>/dev/null); \
  if [ -s "$(FRP_LATEST_CACHE)" ]; then \
    mtime=$$(stat -c %Y "$(FRP_LATEST_CACHE)" 2>/dev/null || echo 0); \
    if [ $$(($$(date +%s) - mtime)) -lt 3600 ]; then echo "$$cached"; exit 0; fi; \
  fi; \
  for api in $(FRP_LATEST_APIS); do \
    v=$$(curl -fsSL --compressed --connect-timeout 8 --max-time 20 \
        -H "Accept: application/vnd.github+json" \
        $${GITHUB_TOKEN:+-H "Authorization: Bearer $$GITHUB_TOKEN"} \
        "$$api" 2>/dev/null \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1); \
    if [ -n "$$v" ]; then \
      mkdir -p "$(TOPDIR)/tmp"; echo "$$v" > "$(FRP_LATEST_CACHE)"; echo "$$v"; exit 0; \
    fi; \
  done; \
  if [ -n "$$cached" ]; then echo "$$cached"; exit 0; fi; \
  echo "frp: 获取最新版本号失败，使用兜底版本 $(FRP_FALLBACK_VERSION)" >&2; \
  echo "$(FRP_FALLBACK_VERSION)"

PKG_VERSION:=$(strip $(shell $(FRP_LATEST)))
PKG_RELEASE:=1

# 取不到版本号就退回兜底版本，绝不用 $(error) 打断解析。
# 原因：defconfig 阶段 OpenWrt 会 dump 每个包的 Makefile，一旦这里解析失败，
# 它只会打印一行 ERROR 然后跳过整个包（CI 不会失败），
# 最终表现就是"编译成功但固件里没有 frpc"。
ifeq ($(PKG_VERSION),)
  PKG_VERSION:=$(FRP_FALLBACK_VERSION)
endif

# 预编译二进制来自公开 release（源码在私有库 laosan-xx/frp-diy，不参与 OpenWrt 编译）
PKG_SOURCE_URL:=https://github.com/laosan-xx/frp/releases/download/v$(PKG_VERSION)/

# release 每次更新哈希都会变，无法写死。注意：留空并不等于跳过校验——download.mk 会把缺省
# 值 "x" 传给 download.pl，而 download.pl 只认 32/64 位十六进制或字面量 skip，收到 "x" 会直接
# die "Cannot find appropriate hash command"，所以这里必须显式写 skip
PKG_HASH:=skip

# 按目标架构选择 release asset（PKG_VERSION 自动取最新 release，无需手改）
ifeq ($(ARCH),x86_64)
  FRP_ARCH:=amd64
endif
ifeq ($(ARCH),aarch64)
  FRP_ARCH:=arm64
endif
ifeq ($(ARCH),mipsel)
  FRP_ARCH:=mipsle
endif
ifeq ($(ARCH),mips)
  FRP_ARCH:=mips
endif
ifeq ($(ARCH),arm)
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    FRP_ARCH:=arm
  else
    FRP_ARCH:=arm_hf
  endif
endif

# 关键：首次 defconfig 扫描包时，.config 里还没有 CONFIG_ARCH（它正是 defconfig 自己写进去的），
# 此时 $(ARCH) 为空，上面所有 ifeq 都落空。若这时撞上下面的 $(error)，本包会被 OpenWrt 跳过，
# 而后续 defconfig 会复用已生成的 tmp/.packageinfo 不再重扫，frpc 就彻底从固件里消失了。
# 所以这里补一个占位值，保证 Makefile 在扫描阶段一定能被完整解析（文件名保持完整即可）。
# 真正 download/构建时 $(ARCH) 一定有效，会重新算出正确的 FRP_ARCH。
ifeq ($(strip $(ARCH)),)
  FRP_ARCH:=arm64
endif

# 走到这里 FRP_ARCH 仍为空，才说明目标架构真的没有预编译包
ifeq ($(strip $(FRP_ARCH)),)
  $(error frp: ARCH=$(ARCH) (SUBTARGET=$(SUBTARGET)) 没有对应的预编译包)
endif

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_linux_$(FRP_ARCH).tar.gz
# tarball 顶层目录名就是 frp_$(PKG_VERSION)_linux_$(FRP_ARCH)，默认解压到 $(BUILD_DIR) 后
# 正好落在 PKG_BUILD_DIR；不设的话默认 PKG_BUILD_DIR 是 frp-$(PKG_VERSION)，会找不到二进制
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)_$(PKG_VERSION)_linux_$(FRP_ARCH)

PKG_MAINTAINER:=
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

# 不编译，直接使用发布的二进制；解压后确认目录结构符合预期
define Build/Prepare
	$(call Build/Prepare/Default)
	echo "frp: ARCH=$(ARCH) FRP_ARCH=$(FRP_ARCH) VERSION=$(PKG_VERSION)"
	[ -x "$(PKG_BUILD_DIR)/frpc" ] || { \
		echo "ERROR: $(PKG_BUILD_DIR)/frpc 不存在，release tarball 目录结构与预期不符"; \
		exit 1; \
	}
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
