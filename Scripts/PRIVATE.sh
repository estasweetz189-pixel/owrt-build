#!/bin/bash
# SPDX-License-Identifier: MIT
# 私有扩展：把 FanchmWrt 界面（fwx 家族）与后端挂进编译

FWX_SRC="./fanchm-src"
FWX_PKG="./fanchm-pkg"

rm -rf "$FWX_SRC" "$FWX_PKG"

# 1) 主仓库：fwx(kmod) / fwxd(守护) / libfwx_common / luci-theme-fanchmwrt / shortcut-fe / fullconenat
git clone --depth=1 --single-branch --branch fanchmwrt-25.12.6 \
  https://github.com/fanchmwrt/fanchmwrt.git "$FWX_SRC"
for p in fwx fwxd libfwx_common luci-theme-fanchmwrt shortcut-fe fullconenat fullconenat-nft; do
  if [ -d "$FWX_SRC/package/fcm/$p" ]; then
    cp -rf "$FWX_SRC/package/fcm/$p" ./package/
    echo "Copied package/fcm/$p"
  else
    echo "WARN: $FWX_SRC/package/fcm/$p not found"
  fi
done
rm -rf "$FWX_SRC"

# 2) 界面包仓库：19 个 luci-app-fwx-*
git clone --depth=1 --single-branch --branch main \
  https://github.com/fanchmwrt/fanchmwrt-packages.git "$FWX_PKG"
find "$FWX_PKG" -maxdepth 1 -type d -name 'luci-app-fwx-*' -exec cp -rf {} ./package/ \;
rm -rf "$FWX_PKG"

# 3) 内核补丁：struct nf_conn 增加 fwx_data（fwx.ko 强依赖，上游内核没有）
PATCH_SRC="$GITHUB_WORKSPACE/Scripts/patches/fwx/950-fwx-nf-conn-struct-user-hook.patch"
if [ -f "$PATCH_SRC" ]; then
  for d in ./target/linux/generic/hack-6.*/; do
    [ -d "$d" ] || continue
    cp -f "$PATCH_SRC" "${d}950-fwx-nf-conn-struct-user-hook.patch"
    echo "Kernel patch installed: ${d}"
  done
else
  echo "ERROR: fwx kernel patch missing"
  exit 1
fi

# 4) OpenClash 内置 Meta(mihomo) 内核：aarch64 版本直接塞进包目录，
#    避免上游 Makefile 的 INCLUDE_CORE 分支在 CI 上把 $CORE_ARCH 变量吞掉导致 404
OC_DIR="./package/luci-app-openclash"
OC_CORE_DIR="$OC_DIR/root/etc/openclash/core"
if [ -d "$OC_DIR" ]; then
  mkdir -p "$OC_CORE_DIR"
  CORE_URLS=(
    "https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    "https://ghfast.top/https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    "https://gh-proxy.com/https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
  )
  CORE_OK=0
  for u in "${CORE_URLS[@]}"; do
    if curl -fSL --connect-timeout 20 --retry 2 -o /tmp/clash_meta.tar.gz "$u"; then
      CORE_OK=1; break
    fi
  done
  if [ "$CORE_OK" = "1" ] && tar -xzf /tmp/clash_meta.tar.gz -C /tmp clash; then
    install -m 0755 /tmp/clash "$OC_CORE_DIR/clash_meta"
    echo "OpenClash core bundled: $(ls -lh "$OC_CORE_DIR/clash_meta" | awk '{print $5}')"
  else
    echo "ERROR: OpenClash meta core download failed"
    exit 1
  fi
  rm -f /tmp/clash /tmp/clash_meta.tar.gz
fi

echo "PRIVATE.sh: FanchmWrt packages copied."
