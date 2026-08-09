#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU_USER="developer"
RUN_DIR="$HOME/.termux-dev"
LOG_DIR="$RUN_DIR/logs"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }

clean=false
[ "${1:-}" = "clean" ] && clean=true

# Kills the PRoot process recorded by start.sh. Because the service runs in
# the foreground inside PRoot, this tears the whole session down cleanly.
stop_pid_file() {
    local file="$1"

    [ -f "$file" ] || return 0

    local pid
    pid="$(cat "$file" 2>/dev/null)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true

        local waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 5 ]; do
            sleep 1
            waited=$((waited + 1))
        done

        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$file"
}

info "Stopping code-server..."

stop_pid_file "$RUN_DIR/code-server.pid"
pkill -f "termux-dev-code-server" 2>/dev/null || true

info "Stopping XFCE..."

stop_pid_file "$RUN_DIR/xfce.pid"
pkill -f "termux-dev-xfce" 2>/dev/null || true

# Exact-name matching only, so nothing unrelated is caught.
for process in xfce4-session xfce4-panel xfdesktop xfwm4 xfsettingsd xfconfd \
    xfce4-screensaver xfce4-power-manager; do
    pkill -x "$process" 2>/dev/null || true
done

sleep 1

info "Stopping Termux:X11..."

stop_pid_file "$RUN_DIR/termux-x11.pid"
pkill -x "termux-x11" 2>/dev/null || true

if $clean; then
    info "Cleaning runtime data..."

    rm -rf "$LOG_DIR" 2>/dev/null || true
    rm -rf "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/runtime-$UBUNTU_USER" 2>/dev/null || true
fi

ok "Development environment stopped."
