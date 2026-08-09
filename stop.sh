#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU="ubuntu"
DEV_USER="developer"
BASE_DIR="$HOME/.termux-dev"

info(){ echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $1"; }

stop_code_server(){
    info "Stopping Ubuntu code-server..."

    if command -v proot-distro >/dev/null 2>&1; then
        proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "
            pkill -u '$DEV_USER' -f 'code-server' 2>/dev/null || true
        " 2>/dev/null || true
    fi

    ok "code-server stopped"
}

stop_xfce(){
    info "Stopping XFCE..."

    pkill -f "xfce4-session" 2>/dev/null || true
    pkill -f "xfce4-panel" 2>/dev/null || true
    pkill -f "xfdesktop" 2>/dev/null || true
    pkill -f "xfwm4" 2>/dev/null || true
    pkill -f "xfsettingsd" 2>/dev/null || true
    pkill -f "xfconfd" 2>/dev/null || true
    pkill -f "startxfce4" 2>/dev/null || true

    ok "XFCE stopped"
}

stop_x11(){
    info "Stopping Termux:X11..."

    pkill -f "termux-x11" 2>/dev/null || true

    ok "Termux:X11 stopped"
}

clean(){
    info "Cleaning stale session data..."

    rm -rf "$BASE_DIR/logs" 2>/dev/null || true

    if command -v proot-distro >/dev/null 2>&1; then
        proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "
            rm -rf /tmp/.X11-unix 2>/dev/null || true
            rm -rf /home/$DEV_USER/.cache/code-server 2>/dev/null || true
        " 2>/dev/null || true
    fi

    ok "Temporary data cleaned"
}

stop_all(){
    stop_code_server
    stop_xfce
    stop_x11
    ok "Development environment stopped"
}

case "${1:-stop}" in
    stop)
        stop_all
        ;;
    clean)
        stop_all
        clean
        ;;
    *)
        echo "Usage: $0 [stop|clean]"
        exit 1
        ;;
esac
