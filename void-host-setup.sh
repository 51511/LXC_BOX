#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# void-host-setup.sh — 設定 Void Linux 當 lxcbox Host
# 取代 alpine-host-setup.sh
#
# 安裝：
#   sudo sh void-host-setup.sh

set -e

# ── 安裝必要套件 ──────────────────────────────────────────────────────────────
echo "==> 安裝 LXC 和相關工具..."
xbps-install -Sy \
    lxc \
    debootstrap \
    xhost \
    xauth

# ── 設定 /etc/lxc/default.conf ───────────────────────────────────────────────
# 清空 default.conf，避免 veth 網路設定跟 lxcbox 衝突
echo "==> 設定 /etc/lxc/default.conf..."
cat > /etc/lxc/default.conf << 'EOF'
# lxcbox host default config
# 保持空白，讓每個 container 的 config 自己決定網路設定
EOF

# ── 設定 sudoers ──────────────────────────────────────────────────────────────
# 讓一般用戶可以用 sudo 跑 lxc 指令
echo "==> 設定 sudoers..."
cat > /etc/sudoers.d/lxcbox << 'EOF'
# lxcbox — 允許一般用戶管理 LXC container
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-start
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-stop
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-info
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-attach
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-snapshot
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-destroy
%wheel ALL=(root) NOPASSWD: /usr/bin/nsenter
EOF
chmod 440 /etc/sudoers.d/lxcbox

# ── 安裝 lxcbox 工具到 PATH ───────────────────────────────────────────────────
echo "==> 安裝 lxcbox 工具..."
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

for tool in lxcbox lxcbox-create lxcbox-enter lxcbox-export \
            lxcbox-host-exec lxcbox-init lxcbox-list \
            lxcbox-rm lxcbox-snapshot; do
    if [ -f "${SCRIPT_DIR}/${tool}" ]; then
        ln -sf "${SCRIPT_DIR}/${tool}" "/usr/local/bin/${tool}"
        echo "  linked: ${tool}"
    fi
done

# ── 設定 PATH ─────────────────────────────────────────────────────────────────
echo "==> 提示：把 ~/.local/bin 加到 PATH"
echo "    在 ~/.bashrc 加入："
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""

echo ""
echo "==> 完成！現在可以用："
echo "    lxcbox create --name mybox"
echo "    lxcbox enter mybox"
