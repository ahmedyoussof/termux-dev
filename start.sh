#!/data/data/com.termux/files/usr/bin/bash

set -u

DISPLAY_NUM=":1"
UBUNTU_NAME="ubuntu"
UBUNTU_USER="developer"
LOG_DIR="$HOME/.termux-dev/logs"

mkdir -p "$LOG_DIR"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

command -v termux-x11 >/dev/null 2>&1 || {
    error "Termux:X11 is not installed. Run ./install.sh first."
    exit 1
}

command -v proot-distro >/dev/null 2>&1 || {
    error "proot-distro is not installed. Run ./install.sh first."
    exit 1
}

export DISPLAY="$DISPLAY_NUM"

info "Starting Termux:X11..."

if pgrep -f "termux-x11" >/dev/null 2>&1; then
    ok "Termux:X11 already running."
else
    termux-x11 "$DISPLAY_NUM" >"$LOG_DIR/termux-x11.log" 2>&1 &
    sleep 2

    pgrep -f "termux-x11" >/dev/null 2>&1 || {
        error "Termux:X11 failed to start."
        cat "$LOG_DIR/termux-x11.log"
        exit 1
    }
    ok "Termux:X11 started."
fi

info "Starting Ubuntu XFCE..."

proot-distro login "$UBUNTU_NAME" \
    --user "$UBUNTU_USER" \
    --shared-tmp \
    -- bash -lc '
        export DISPLAY=:1
        export LIBGL_ALWAYS_SOFTWARE=1
        export XDG_RUNTIME_DIR=/tmp/runtime-$USER
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"

        if ! pgrep -u "$USER" -f "xfce4-session" >/dev/null 2>&1; then
            nohup dbus-launch --exit-with-session startxfce4 >/tmp/xfce.log 2>&1 &
        fi
    ' >/dev/null 2>&1

sleep 5

if proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
    -- bash -lc 'pgrep -u "$USER" -f "xfce4-session" >/dev/null 2>&1'; then
    ok "XFCE started."
else
    error "XFCE failed to start."
    proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
        -- bash -lc 'cat /tmp/xfce.log 2>/dev/null || true'
    exit 1
fi

info "Starting code-server..."

if proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
    -- bash -lc 'pgrep -u "$USER" -f "code-server" >/dev/null 2>&1'; then
    ok "code-server already running."
else
    proot-distro login "$UBUNTU_NAME" \
        --user "$UBUNTU_USER" \
        --shared-tmp \
        -- bash -lc '
            nohup code-server \
                --bind-addr 127.0.0.1:8080 \
                >/tmp/code-server.log 2>&1 &
        ' >/dev/null 2>&1

    sleep 3

    if proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
        -- bash -lc 'pgrep -u "$USER" -f "code-server" >/dev/null 2>&1'; then
        ok "code-server started."
    else
        error "code-server failed to start."
        proot-distro login "$UBUNTU_NAME" --user "$UBUNTU_USER" --shared-tmp \
            -- bash -lc 'cat /tmp/code-server.log 2>/dev/null || true'
        exit 1
    fi
fi

echo
ok "Development environment is ready."
echo "Display : $DISPLAY"
echo "Ubuntu  : $UBUNTU_NAME"
echo "User    : $UBUNTU_USER"
echo "VS Code : http://127.0.0.1:8080"
echo
echo "Open the Termux:X11 Android app to see XFCE."
