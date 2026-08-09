#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU_NAME="ubuntu"
UBUNTU_USER="developer"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }

clean=false
[ "${1:-}" = "clean" ] && clean=true

info "Stopping code-server..."

proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
    -- bash -lc 'pkill -u "$USER" -f code-server 2>/dev/null || true' 2>/dev/null || true

info "Stopping XFCE..."

proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
    -- bash -lc '
        for p in xfce4-session xfce4-panel xfdesktop xfwm4 xfsettingsd xfconfd dbus-daemon; do
            pkill -u "$USER" -f "$p" 2>/dev/null || true
        done
    ' 2>/dev/null || true

sleep 1

info "Stopping Termux:X11..."
pkill -f "termux-x11" 2>/dev/null || true

if $clean; then
    info "Cleaning runtime data..."
    rm -rf "$HOME/.termux-dev/logs" 2>/dev/null || true

    proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
        -- bash -lc '
            rm -rf "/tmp/runtime-$USER"
            rm -f /tmp/code-server.log /tmp/xfce.log
        ' 2>/dev/null || true
fi

ok "Development environment stopped."
