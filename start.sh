#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU="ubuntu"
DEV_USER="developer"
DISPLAY_NUM=":1"
CODE_SERVER_PORT="8080"
LOG_DIR="$HOME/.termux-dev/logs"

mkdir -p "$LOG_DIR"

info(){ echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $1"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $1"; }
err(){ echo -e "\033[1;31m[ERROR]\033[0m $1"; }

running(){
    pgrep -f "$1" >/dev/null 2>&1
}

if ! command -v proot-distro >/dev/null 2>&1; then
    err "proot-distro is not installed. Run ./install.sh"
    exit 1
fi

export DISPLAY="$DISPLAY_NUM"

info "Starting Termux:X11..."

if running "termux-x11"; then
    ok "Termux:X11 already running"
else
    termux-x11 "$DISPLAY_NUM" >"$LOG_DIR/x11.log" 2>&1 &
    sleep 2
fi

if ! running "termux-x11"; then
    err "Termux:X11 failed to start"
    cat "$LOG_DIR/x11.log"
    exit 1
fi

ok "Termux:X11 ready"

info "Starting existing Termux XFCE..."

if running "xfce4-session"; then
    ok "XFCE already running"
else
    dbus-launch --exit-with-session startxfce4 >"$LOG_DIR/xfce.log" 2>&1 &
    sleep 5
fi

if running "xfce4-session"; then
    ok "XFCE ready"
else
    err "XFCE did not start"
    cat "$LOG_DIR/xfce.log"
    exit 1
fi

info "Starting Ubuntu code-server..."

proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "
export DISPLAY=$DISPLAY_NUM
export PATH=\$HOME/.local/bin:\$PATH

if pgrep -u '$DEV_USER' -f 'code-server' >/dev/null 2>&1; then
    exit 0
fi

su - '$DEV_USER' -c '
export DISPLAY=$DISPLAY_NUM
export PATH=\$HOME/.local/bin:\$PATH
nohup code-server --bind-addr 127.0.0.1:$CODE_SERVER_PORT '$DEV_USER'/projects >\$HOME/code-server.log 2>&1 &
'
"

sleep 3

if proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "pgrep -u '$DEV_USER' -f 'code-server' >/dev/null 2>&1"; then
    ok "Ubuntu code-server ready"
else
    err "code-server failed to start"
    proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "cat /home/$DEV_USER/code-server.log 2>/dev/null || true"
    exit 1
fi

echo
ok "Development environment is ready."
echo
echo "XFCE       : Termux:X11"
echo "Ubuntu     : $UBUNTU"
echo "User       : $DEV_USER"
echo "VS Code UI : http://127.0.0.1:$CODE_SERVER_PORT"
echo
echo "Inside the VS Code terminal:"
echo "  sudo -i"
echo
echo "To enter Ubuntu directly:"
echo "  proot-distro login ubuntu --shared-tmp"
