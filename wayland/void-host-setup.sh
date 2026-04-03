#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# void-host-setup.sh — 設定 Void Linux 當 lxcbox Host
#
# 安裝：
#   sudo sh void-host-setup.sh [USERNAME]

set -e

TARGET_USER="${1:-${SUDO_USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d':' -f6)"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

echo "=== lxcbox Void Host Setup ==="
echo "目標用戶: ${TARGET_USER}"
echo ""

# ── 1. 安裝必要套件 ───────────────────────────────────────────────────────────
echo "[1/8] 安裝 LXC 和相關工具..."
xbps-install -Sy \
    lxc \
    debootstrap \
    xhost \
    xauth \
    rsync

# ── 2. 設定 /etc/lxc/default.conf ────────────────────────────────────────────
echo "[2/8] 設定 /etc/lxc/default.conf..."
cat > /etc/lxc/default.conf << 'LXCEOF'
# lxcbox host default config
LXCEOF

# ── 3. 設定 sudoers ───────────────────────────────────────────────────────────
echo "[3/8] 設定 sudoers..."
cat > /etc/sudoers.d/lxcbox << 'SUDOEOF'
# lxcbox — 允許一般用戶管理 LXC container
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-start
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-stop
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-info
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-attach
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-copy
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-snapshot
%wheel ALL=(root) NOPASSWD: /usr/bin/lxc-destroy
%wheel ALL=(root) NOPASSWD: /usr/bin/nsenter
SUDOEOF
chmod 440 /etc/sudoers.d/lxcbox

# ── 4. 安裝 lxcbox 工具到 PATH ────────────────────────────────────────────────
echo "[4/8] 安裝 lxcbox 工具到 /usr/local/bin/..."
for tool in lxcbox lxcbox-create lxcbox-enter lxcbox-export \
            lxcbox-host-exec lxcbox-init lxcbox-list \
            lxcbox-rm lxcbox-snapshot; do
    if [ -f "${SCRIPT_DIR}/${tool}" ]; then
        install -m 755 "${SCRIPT_DIR}/${tool}" "/usr/local/bin/${tool}"
        echo "  installed: ${tool}"
    fi
done

# ── 5. 安裝 Login_Script ──────────────────────────────────────────────────────
echo "[5/8] 安裝 Login_Script..."
if [ -d "${SCRIPT_DIR}/Login_Script" ]; then
    install -m 644 "${SCRIPT_DIR}/Login_Script/lxcbox-session" /usr/lib/lxcbox/lxcbox-session 2>/dev/null || {
        mkdir -p /usr/lib/lxcbox
        install -m 644 "${SCRIPT_DIR}/Login_Script/lxcbox-session" /usr/lib/lxcbox/lxcbox-session
    }

    # /etc/profile.d/ — TTY / SSH login
    cat > /etc/profile.d/lxcbox-session.sh << PROFEOF
#!/bin/sh
[ "\$(id -un)" != "${TARGET_USER}" ] && return 0
[ -f /usr/lib/lxcbox/lxcbox-session ] && . /usr/lib/lxcbox/lxcbox-session
PROFEOF
    chmod 644 /etc/profile.d/lxcbox-session.sh

    # ~/.bashrc — terminal emulator
    if ! grep -q "lxcbox-session" "${TARGET_HOME}/.bashrc" 2>/dev/null; then
        cat >> "${TARGET_HOME}/.bashrc" << BASHEOF

# lxcbox-session: 自動進入 LXC container
if [ -f /usr/lib/lxcbox/lxcbox-session ]; then
    . /usr/lib/lxcbox/lxcbox-session
fi
BASHEOF
        chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.bashrc"
    fi

    # void-shell 指令
    cat > /usr/local/bin/void-shell << 'VOIDEOF'
#!/bin/sh
export LXCBOX_SKIP=1
export _LXCBOX_SESSION_LOADED=1
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │   Void Linux 原生 Shell                     │"
echo "  │   輸入 'exit' 回到 lxcbox session           │"
echo "  └─────────────────────────────────────────────┘"
echo ""
exec /bin/bash --norc --noprofile
VOIDEOF
    chmod 755 /usr/local/bin/void-shell
    echo "      完成"
fi

# ── 6. 設定 PATH ──────────────────────────────────────────────────────────────
echo "[6/8] 設定 PATH..."
if ! grep -q "\.local/bin" "${TARGET_HOME}/.bashrc" 2>/dev/null; then
    cat >> "${TARGET_HOME}/.bashrc" << 'PATHEOF'
export PATH="$HOME/.local/bin:$PATH"
PATHEOF
fi

# ── 7. GRUB Void Terminal entry ───────────────────────────────────────────────
echo "[7/8] 設定 GRUB Void Terminal entry..."
ROOT_PART="$(findmnt -n -o SOURCE /)"
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_PART}" 2>/dev/null)"
VMLINUZ="$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|/boot/||')"
INITRD="$(ls /boot/initramfs-*.img /boot/initrd-*.img /boot/initrd.img-* 2>/dev/null | sort -V | tail -1 | sed 's|/boot/||')"
BTRFS_SUBVOL=""
if findmnt -n -o OPTIONS / | grep -q "subvol="; then
    BTRFS_SUBVOL="$(findmnt -n -o OPTIONS / | grep -o 'subvol=[^,]*' | cut -d= -f2)"
fi

if [ -n "${VMLINUZ}" ] && [ -n "${ROOT_UUID}" ] && [ -n "${INITRD}" ]; then
    if ! grep -q "Void Terminal" /etc/grub.d/40_custom 2>/dev/null; then
        ROOTFLAGS=""
        [ -n "${BTRFS_SUBVOL}" ] && ROOTFLAGS="rootflags=subvol=${BTRFS_SUBVOL} "
        cat >> /etc/grub.d/40_custom << GRUBEOF

menuentry "Void Linux — Void Terminal (不進 LXC)" {
    insmod btrfs
    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}
    linux   /${BTRFS_SUBVOL}/boot/${VMLINUZ} root=UUID=${ROOT_UUID} rw ${ROOTFLAGS}loglevel=4 lxcbox_skip=1
    initrd  /${BTRFS_SUBVOL}/boot/${INITRD}
}
GRUBEOF
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null \
            && echo "      GRUB 更新完成" \
            || echo "      WARNING: grub-mkconfig 失敗"
    else
        echo "      GRUB entry 已存在，跳過"
    fi
else
    echo "      WARNING: 無法自動偵測 kernel，跳過 GRUB 設定"
fi

# ── 8. 設定 Wayland socket 權限 ───────────────────────────────────────────────
echo "[8/8] 設定 Wayland socket 權限..."
# 讓 container 內可以存取 host 的 Wayland socket
WAYLAND_SOCKET_DIR="/run/user/$(id -u ${TARGET_USER})"
if [ -d "${WAYLAND_SOCKET_DIR}" ]; then
    chmod 755 "${WAYLAND_SOCKET_DIR}"
    echo "      XDG_RUNTIME_DIR 權限設定完成"
fi

# 加入開機時自動設定 Wayland socket 權限的服務
cat > /etc/runit/sv/lxcbox-wayland/run << SVEOF 2>/dev/null || true
#!/bin/sh
# 確保 Wayland socket 對 container 可存取
while true; do
    for uid_dir in /run/user/*/; do
        [ -S "\${uid_dir}wayland-0" ] && chmod 755 "\${uid_dir}"
    done
    sleep 5
done
SVEOF

echo ""
echo "=== 安裝完成 ==="
echo ""
echo "  效果："
echo "  ✓ TTY / SSH 登入      → 自動進入 lxcbox"
echo "  ✓ 圖形 terminal       → 自動進入 lxcbox"
echo "  ✓ 輸入 void-shell     → 回到 Void 原生 shell"
echo "  ✓ GRUB「Void Terminal」→ 整個 session 跳過 lxcbox"
echo ""
echo "  使用方式："
echo "    lxcbox create --name mybox"
echo "    lxcbox enter mybox"
echo ""
echo "  下次登入後生效。"
