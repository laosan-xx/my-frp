#!/usr/bin/env bash
#
# sync-frp.sh — 本地测试脚本：同步上游 laosan-xx/frp 版本到本仓库 Makefile
#
# 用法:
#   ./sync-frp.sh              # 自动取上游最新 release 并对比/更新 Makefile
#   ./sync-frp.sh v0.70.8      # 指定某个 release tag 进行同步
#
# 同步策略: 对比上游最新版本号与最新 PKG_HASH，二者任一不一致则同步上游
#   - 版本号不同  -> 更新 PKG_VERSION 与 PKG_HASH
#   - 版本号相同但 HASH 不同 -> 仅更新 PKG_HASH (上游同一版本重新打包)
#   - 版本号与 HASH 均相同 -> 无需更新
#
# 依赖: bash / curl / sha256sum (Git for Windows 自带, 无需 jq)
# 注意: 未认证调用 GitHub API 有速率限制(约 60 次/小时)
#
set -euo pipefail

UPSTREAM_REPO="laosan-xx/frp"
MAKEFILE="Makefile"

# 1. 确定目标 release tag
if [ $# -ge 1 ]; then
  TAG="$1"
else
  echo "==> 查询上游 ${UPSTREAM_REPO} 最新 release ..."
  # 不依赖 jq: 直接从 JSON 中提取 "tag_name":"..." 字段
  RESP=$(curl -fsSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest")
  # 直接 sed 提取 "tag_name": "vX.Y.Z" 中引号内的纯 tag 值
  TAG=$(echo "$RESP" | sed -n 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  echo "错误: 无法获取上游 release tag" >&2
  exit 1
fi

# 去掉可能的 'v' 前缀，得到纯版本号 (如 0.70.8)
NEW_VERSION="${TAG#v}"
echo "==> 上游最新版本: ${TAG}  (PKG_VERSION=${NEW_VERSION})"

# 2. 读取本地当前版本
if [ ! -f "$MAKEFILE" ]; then
  echo "错误: 未找到 ${MAKEFILE}" >&2
  exit 1
fi
CURRENT_VERSION=$(grep '^PKG_VERSION:=' "$MAKEFILE" | sed 's/PKG_VERSION:=//')
echo "==> 本地当前 PKG_VERSION: ${CURRENT_VERSION}"
CURRENT_HASH=$(grep '^PKG_HASH:=' "$MAKEFILE" | sed 's/PKG_HASH:=//')
echo "==> 本地当前 PKG_HASH: ${CURRENT_HASH}"

# 3. 计算上游最新版本的 PKG_HASH
# 源 tarball 地址与 Makefile 中 PKG_SOURCE_URL 一致
TARBALL_URL="https://codeload.github.com/${UPSTREAM_REPO}/tar.gz/v${NEW_VERSION}"
echo "==> 下载并计算 sha256: ${TARBALL_URL}"
TMP_TAR="$(mktemp -t frp.XXXXXX).tar.gz"
trap 'rm -f "$TMP_TAR"' EXIT

curl -fsSL "$TARBALL_URL" -o "$TMP_TAR"
NEW_HASH=$(sha256sum "$TMP_TAR" | awk '{print $1}')
echo "==> 上游最新 PKG_HASH: ${NEW_HASH}"

# 4. 对比版本与 HASH，决定是否需要同步
# 4.1 版本不一致：更新版本 + HASH
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
  echo "==> 版本不一致，更新 ${MAKEFILE}: ${CURRENT_VERSION} -> ${NEW_VERSION}"
  sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=${NEW_VERSION}/" "$MAKEFILE"
  sed -i "s/^PKG_HASH:=.*/PKG_HASH:=${NEW_HASH}/" "$MAKEFILE"
  echo "==> 最新 PKG_HASH: ${NEW_HASH}"
# 4.2 版本一致但 HASH 不一致：仅更新 HASH（上游同一版本重新打包）
elif [ "$CURRENT_HASH" != "$NEW_HASH" ]; then
  echo "==> 版本一致，但 PKG_HASH 不一致，同步上游最新 HASH: ${CURRENT_HASH} -> ${NEW_HASH}"
  sed -i "s/^PKG_HASH:=.*/PKG_HASH:=${NEW_HASH}/" "$MAKEFILE"
  echo "==> 最新 PKG_HASH: ${NEW_HASH}"
else
  echo "==> 版本与 PKG_HASH 均与上游一致，无需更新。"
  echo "==> 最新 PKG_HASH: ${NEW_HASH}"
  exit 0
fi

echo "==> 完成。请检查 git diff 后决定是否提交。"
git --no-pager diff -- "$MAKEFILE" || true
