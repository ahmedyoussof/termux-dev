#!/data/data/com.termux/files/usr/bin/bash

set -u

DISPLAY_NUM="${TERMUX_DEV_DISPLAY:-:0}"
UBUNTU_NAME="ubuntu"
UBUNTU_USER="developer"

RUN_DIR="$HOME/.termux-dev"
LOG_DIR="$RUN_DIR/logs"
TERMUX_TMP="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

DISPLAY_ID="${DISPLAY_NUM#:}"
DISPLAY_ID="${DISPLAY_ID%%.*}"
X_SOCKET="$TERMUX_TMP/.X11-unix/X$DISPLAY_ID"

mkdir -p "$LOG_DIR"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

command -v termux-x11 >/dev/null 2>&1 || {
    error "Termux:X11 is not installed. Run ./install.sh first."
    exit 1
}

command -v proot-distro >/dev/null 2>&1 || {
    error "proot-distro is not installed. Run ./install.sh first."
    exit 1
}

command -v pgrep >/dev/null 2>&1 || {
    error "pgrep is missing. Run: pkg install procps -y"
    exit 1
}

pid_alive() {
    local file="$1"

    [ -f "$file" ] || return 1

    local pid
    pid="$(cat "$file" 2>/dev/null)"

    [ -n "$pid" ] || return 1

    kill -0 "$pid" 2>/dev/null
}

# wait_for <seconds> <command...>
wait_for() {
    local timeout="$1"
    shift

    local waited=0

    while [ "$waited" -lt "$timeout" ]; do
        "$@" >/dev/null 2>&1 && return 0
        sleep 1
        waited=$((waited + 1))
    done

    return 1
}

port_open() {
    (exec 3<>/dev/tcp/127.0.0.1/8080) >/dev/null 2>&1
}

show_log() {
    local file="$1"

    echo
    echo "--- $file ---"
    tail -n 40 "$file" 2>/dev/null || echo "(no log)"
    echo "---"
    echo
}

# ---------------------------------------------------------------- Termux:X11

info "Starting Termux:X11 on $DISPLAY_NUM..."

if [ -e "$X_SOCKET" ] && pid_alive "$RUN_DIR/termux-x11.pid"; then
    ok "Termux:X11 already running."
else
    rm -f "$X_SOCKET" 2>/dev/null || true

    termux-x11 "$DISPLAY_NUM" >"$LOG_DIR/termux-x11.log" 2>&1 &
    echo $! > "$RUN_DIR/termux-x11.pid"

    # The Android activity owns the surface. Without it the X server runs
    # but nothing is ever drawn, which looks exactly like a black screen.
    if command -v am >/dev/null 2>&1; then
        am start --user 0 \
            -n com.termux.x11/com.termux.x11.MainActivity \
            >/dev/null 2>&1 || true
    fi

    if ! wait_for 15 test -e "$X_SOCKET"; then
        error "Termux:X11 failed to start (no socket at $X_SOCKET)."
        show_log "$LOG_DIR/termux-x11.log"
        exit 1
    fi

    ok "Termux:X11 started."
fi

# ---------------------------------------------------------------------- XFCE

info "Starting Ubuntu XFCE..."

if pgrep -x xfce4-session >/dev/null 2>&1; then
    ok "XFCE already running."
else
    pkill -f "termux-dev-xfce" >/dev/null 2>&1 || true

    # PRoot traces every process in the container: when the login exits,
    # its children die with it. The session therefore has to stay in the
    # foreground inside PRoot and be backgrounded here, in Termux.
    proot-distro login "$UBUNTU_NAME" \
        --user "$UBUNTU_USER" \
        --shared-tmp \
        -- env "DISPLAY=$DISPLAY_NUM" /usr/local/bin/termux-dev-xfce \
        >"$LOG_DIR/xfce.log" 2>&1 &

    echo $! > "$RUN_DIR/xfce.pid"

    if ! wait_for 45 pgrep -x xfce4-session; then
        error "XFCE failed to start."

        if ! pid_alive "$RUN_DIR/xfce.pid"; then
            error "The Ubuntu session exited. See the log below."
        fi

        show_log "$LOG_DIR/xfce.log"
        exit 1
    fi

    ok "XFCE started."
fi

# --------------------------------------------------------------- code-server

info "Starting code-server..."

if port_open; then
    ok "code-server already running."
else
    pkill -f "termux-dev-code-server" >/dev/null 2>&1 || true

    proot-distro login "$UBUNTU_NAME" \
        --user "$UBUNTU_USER" \
        --shared-tmp \
        -- /usr/local/bin/termux-dev-code-server \
        >"$LOG_DIR/code-server.log" 2>&1 &

    echo $! > "$RUN_DIR/code-server.pid"

    if ! wait_for 30 port_open; then
        if pid_alive "$RUN_DIR/code-server.pid"; then
            warn "code-server is running but 127.0.0.1:8080 is not answering yet."
        else
            error "code-server failed to start."
            show_log "$LOG_DIR/code-server.log"
            exit 1
        fi
    else
        ok "code-server started."
    fi
fi

echo
ok "Development environment is ready."
echo "Display : $DISPLAY_NUM"
echo "Ubuntu  : $UBUNTU_NAME"
echo "User    : $UBUNTU_USER"
echo "VS Code : http://127.0.0.1:8080"
echo "Logs    : $LOG_DIR"
echo
echo "Open the Termux:X11 Android app to see XFCE."
