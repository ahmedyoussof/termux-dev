#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU_NAME="ubuntu"
UBUNTU_USER="developer"
UBUNTU_HOME="/home/$UBUNTU_USER"
DISPLAY_NUM="${TERMUX_DEV_DISPLAY:-:0}"

TERMUX_TMP="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
STAGE_NAME="termux-dev-stage"
STAGE_DIR="$TERMUX_TMP/$STAGE_NAME"
UBUNTU_STAGE="/tmp/$STAGE_NAME"

# Packages that must install for the environment to work.
UBUNTU_REQUIRED="sudo git curl wget ca-certificates unzip zip tar gzip vim nano tmux
openssh-client jq tree procps file python3 python3-pip python3-venv nodejs npm
dbus dbus-x11 x11-xserver-utils xfce4 openjdk-17-jdk maven"

# Nice to have. Failures here are reported but never abort the install.
UBUNTU_OPTIONAL="ripgrep fd-find xfce4-terminal xfce4-goodies firefox"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

require_termux() {
    if ! command -v pkg >/dev/null 2>&1; then
        error "This script must be run from Termux."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        error "Native Termux Git is required to bootstrap this repository."
        echo
        echo "Run:"
        echo "  pkg update"
        echo "  pkg install git -y"
        exit 1
    fi
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null |
        grep -q "install ok installed"
}

install_termux_package() {
    local package="$1"

    if package_installed "$package"; then
        ok "$package already installed."
        return 0
    fi

    info "Installing Termux package: $package"

    if ! pkg install "$package" -y; then
        error "Failed to install $package."
        return 1
    fi

    ok "$package installed."
}

setup_termux() {
    info "Checking native Termux dependencies..."

    # pgrep/pkill drive the whole start/stop lifecycle.
    if ! command -v pgrep >/dev/null 2>&1; then
        install_termux_package "procps" || return 1
    fi

    install_termux_package "x11-repo" || return 1
    install_termux_package "termux-x11-nightly" || return 1
    install_termux_package "proot-distro" || return 1

    ok "Native Termux dependencies are ready."
}

install_ubuntu() {
    if proot-distro login "$UBUNTU_NAME" -- true >/dev/null 2>&1; then
        ok "Ubuntu already installed."
        return 0
    fi

    info "Installing Ubuntu..."

    if ! proot-distro install "$UBUNTU_NAME"; then
        error "Failed to install Ubuntu."
        return 1
    fi

    ok "Ubuntu installed."
}

ubuntu_exec() {
    proot-distro login "$UBUNTU_NAME" --shared-tmp -- "$@"
}

# Echoes the subset of "$@" that is not installed inside Ubuntu.
ubuntu_missing_packages() {
    ubuntu_exec bash -c '
        for package in "$@"; do
            dpkg-query -W -f="\${Status}" "$package" 2>/dev/null |
                grep -q "install ok installed" || printf "%s " "$package"
        done
    ' bash "$@" 2>/dev/null
}

# Installs a package list, falling back to one-by-one so a single bad
# package name (or a snap-only package such as firefox) cannot abort
# the whole environment.
ubuntu_install_packages() {
    local label="$1"
    shift

    if ubuntu_exec env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "$@"; then
        return 0
    fi

    warn "Bulk install of $label packages failed. Retrying individually..."

    local package
    local failed=""

    for package in "$@"; do
        ubuntu_exec env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y "$package" >/dev/null 2>&1 ||
            failed="$failed $package"
    done

    if [ -n "$failed" ]; then
        warn "Could not install:$failed"
        return 1
    fi

    return 0
}

setup_ubuntu() {
    info "Checking Ubuntu packages..."

    local missing_required
    local missing_optional

    missing_required="$(ubuntu_missing_packages $UBUNTU_REQUIRED)"
    missing_optional="$(ubuntu_missing_packages $UBUNTU_OPTIONAL)"

    if [ -z "$missing_required$missing_optional" ]; then
        ok "All Ubuntu packages already installed. Nothing to download."
        return 0
    fi

    info "Missing packages:$(echo " $missing_required$missing_optional" | tr -s ' ')"
    info "Updating Ubuntu package lists..."

    ubuntu_exec apt-get update || {
        error "Ubuntu apt update failed."
        return 1
    }

    if [ -n "$missing_required" ]; then
        info "Installing required Ubuntu packages..."

        ubuntu_install_packages "required" $missing_required || {
            error "Failed to install required Ubuntu packages."
            return 1
        }
    fi

    if [ -n "$missing_optional" ]; then
        info "Installing optional Ubuntu packages..."

        ubuntu_install_packages "optional" $missing_optional ||
            warn "Optional packages are incomplete. The desktop still works."
    fi

    ok "Ubuntu packages are ready."
}

setup_user() {
    info "Configuring Ubuntu developer user..."

    ubuntu_exec bash -c "
        if ! id -u '$UBUNTU_USER' >/dev/null 2>&1; then
            useradd -m -s /bin/bash '$UBUNTU_USER'
        fi

        usermod -aG sudo '$UBUNTU_USER'

        mkdir -p '$UBUNTU_HOME/projects'

        chown -R '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME'

        cat > /etc/sudoers.d/termux-dev <<EOF
$UBUNTU_USER ALL=(ALL:ALL) NOPASSWD:ALL
EOF

        chmod 440 /etc/sudoers.d/termux-dev
    " || {
        error "Failed to configure developer user."
        return 1
    }

    ok "Developer user and sudo are ready."
}

# D-Bus refuses to start a session bus without a machine ID, which is a
# very common cause of "XFCE starts and instantly dies" inside PRoot.
setup_machine_id() {
    info "Ensuring D-Bus machine ID..."

    ubuntu_exec bash -c '
        mkdir -p /var/lib/dbus

        if [ ! -s /etc/machine-id ]; then
            dbus-uuidgen > /etc/machine-id 2>/dev/null ||
                cat /proc/sys/kernel/random/uuid | tr -d - > /etc/machine-id
        fi

        if [ ! -s /var/lib/dbus/machine-id ]; then
            cp /etc/machine-id /var/lib/dbus/machine-id
        fi
    ' || {
        error "Failed to create the D-Bus machine ID."
        return 1
    }

    ok "D-Bus machine ID is present."
}

install_code_server() {
    info "Checking code-server..."

    if ubuntu_exec bash -c 'command -v code-server >/dev/null 2>&1'; then
        ok "code-server already installed."
        return 0
    fi

    info "Installing code-server..."

    ubuntu_exec bash -c '
        curl -fsSL https://code-server.dev/install.sh | sh
    ' || {
        error "Failed to install code-server."
        return 1
    }

    ok "code-server installed."
}

# Files are staged through the Termux temp directory, which PRoot maps to
# /tmp with --shared-tmp. This avoids fragile nested shell quoting.
stage_file() {
    local name="$1"

    mkdir -p "$STAGE_DIR"
    cat > "$STAGE_DIR/$name"
}

write_launchers() {
    info "Writing session launchers..."

    stage_file "termux-dev-xfce" <<'LAUNCHER'
#!/bin/bash
# Started by start.sh, in the foreground, inside PRoot.
# Runs the XFCE session directly so the PRoot process is the session lifetime.

set -u

if [ "${1:-}" = "--inner" ]; then
    # Runs inside the D-Bus session, so xfconf writes reach the live daemon.
    (
        sleep 8
        xset s off -dpms s noblank >/dev/null 2>&1
        xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false \
            >/dev/null 2>&1
        xfconf-query -c xfce4-power-manager \
            -p /xfce4-power-manager/dpms-enabled -n -t bool -s false \
            >/dev/null 2>&1
    ) &

    exec xfce4-session
fi

: "${DISPLAY:=:0}"
export DISPLAY

# Software rendering: there is no usable GPU driver inside PRoot.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

display_id="${DISPLAY#:}"
display_id="${display_id%%.*}"
socket="/tmp/.X11-unix/X$display_id"

waited=0
while [ ! -e "$socket" ] && [ "$waited" -lt 15 ]; do
    sleep 1
    waited=$((waited + 1))
done

if [ ! -e "$socket" ]; then
    echo "ERROR: X socket $socket is not visible inside Ubuntu."
    echo "Termux:X11 is not running, or PRoot was started without --shared-tmp."
    exit 1
fi

if ! xset -q >/dev/null 2>&1; then
    echo "ERROR: cannot open display $DISPLAY."
    exit 1
fi

# Blanking never recovers under Termux:X11 and looks exactly like a crash.
xset s off -dpms s noblank >/dev/null 2>&1 || true

if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$0" --inner
fi

exec dbus-launch --exit-with-session "$0" --inner
LAUNCHER

    stage_file "termux-dev-code-server" <<'LAUNCHER'
#!/bin/bash
set -u

export XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

exec code-server --bind-addr 127.0.0.1:8080
LAUNCHER

    ubuntu_exec bash -c "
        install -m 755 '$UBUNTU_STAGE/termux-dev-xfce' /usr/local/bin/termux-dev-xfce
        install -m 755 '$UBUNTU_STAGE/termux-dev-code-server' /usr/local/bin/termux-dev-code-server
    " || {
        error "Failed to install session launchers."
        return 1
    }

    rm -f "$STAGE_DIR/termux-dev-xfce" "$STAGE_DIR/termux-dev-code-server"

    ok "Session launchers installed."
}

configure_xfce() {
    info "Applying XFCE fixes for Termux:X11..."

    local xfconf_dir="$UBUNTU_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"

    mkdir -p "$STAGE_DIR/xfconf" "$STAGE_DIR/autostart"

    cat > "$STAGE_DIR/xfconf/xfwm4.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XML

    cat > "$STAGE_DIR/xfconf/xfce4-power-manager.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="uint" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="blank-on-battery" type="uint" value="0"/>
    <property name="dpms-on-battery-sleep" type="uint" value="0"/>
    <property name="dpms-on-battery-off" type="uint" value="0"/>
  </property>
</channel>
XML

    cat > "$STAGE_DIR/xfconf/xfce4-screensaver.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
XML

    local locker
    for locker in xfce4-screensaver light-locker xscreensaver; do
        cat > "$STAGE_DIR/autostart/$locker.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$locker
Exec=/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    done

    ubuntu_exec bash -c "
        mkdir -p '$xfconf_dir' '$UBUNTU_HOME/.config/autostart'

        # Only seed xfconf defaults, never clobber existing preferences.
        for file in '$UBUNTU_STAGE'/xfconf/*.xml; do
            target='$xfconf_dir/'\$(basename \"\$file\")
            [ -f \"\$target\" ] || cp \"\$file\" \"\$target\"
        done

        # Screen lockers are disabled by autostart override, not by
        # removing packages, so nothing needs to be downloaded again.
        cp '$UBUNTU_STAGE'/autostart/*.desktop '$UBUNTU_HOME/.config/autostart/'

        chown -R '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME/.config'
    " || {
        error "Failed to apply XFCE configuration."
        return 1
    }

    rm -rf "$STAGE_DIR/xfconf" "$STAGE_DIR/autostart"

    ok "XFCE configured (compositing off, blanking off, lockers disabled)."
}

configure_environment() {
    info "Configuring Ubuntu environment..."

    ubuntu_exec bash -c "
        cat > /etc/profile.d/termux-dev.sh <<'EOF'
export DISPLAY=\${DISPLAY:-$DISPLAY_NUM}
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export DEV_HOME=$UBUNTU_HOME
EOF

        mkdir -p '$UBUNTU_HOME/projects'

        cat > '$UBUNTU_HOME/.bashrc.termux-dev' <<'EOF'
export DISPLAY=\${DISPLAY:-$DISPLAY_NUM}
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
export DEV_HOME=$UBUNTU_HOME

alias cdev='cd $UBUNTU_HOME'
alias cproj='cd $UBUNTU_HOME/projects'
alias root='sudo -i'
EOF

        if ! grep -qxF 'source ~/.bashrc.termux-dev' '$UBUNTU_HOME/.bashrc' 2>/dev/null; then
            echo 'source ~/.bashrc.termux-dev' >> '$UBUNTU_HOME/.bashrc'
        fi

        chown '$UBUNTU_USER:$UBUNTU_USER' \
            '$UBUNTU_HOME/.bashrc' \
            '$UBUNTU_HOME/.bashrc.termux-dev'

        chown -R '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME/projects'
    " || {
        error "Failed to configure Ubuntu environment."
        return 1
    }

    ok "Ubuntu environment configured."
}

configure_termux_shell() {
    info "Configuring Termux shell helpers..."

    local line="alias ubuntu='proot-distro login $UBUNTU_NAME --user $UBUNTU_USER --shared-tmp'"

    if ! grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null; then
        echo "$line" >> "$HOME/.bashrc"
    fi

    ok "Termux 'ubuntu' alias is available in new sessions."
}

configure_code_server() {
    info "Configuring code-server..."

    ubuntu_exec bash -c "
        mkdir -p '$UBUNTU_HOME/.config/code-server'

        if [ ! -f '$UBUNTU_HOME/.config/code-server/config.yaml' ]; then
            cat > '$UBUNTU_HOME/.config/code-server/config.yaml' <<'EOF'
bind-addr: 127.0.0.1:8080
auth: password
password: termux-dev
cert: false
EOF
        fi

        chown -R '$UBUNTU_USER:$UBUNTU_USER' \
            '$UBUNTU_HOME/.config'
    " || {
        error "Failed to configure code-server."
        return 1
    }

    warn "Initial code-server password: termux-dev"
}

verify_ubuntu() {
    info "Verifying Ubuntu environment..."

    local failed=0

    verify_command() {
        local name="$1"
        local command="$2"

        if ubuntu_exec bash -lc "command -v '$command' >/dev/null 2>&1"; then
            ok "$name"
        else
            error "$name is missing."
            failed=1
        fi
    }

    verify_file() {
        local name="$1"
        local path="$2"

        if ubuntu_exec bash -c "[ -s '$path' ]"; then
            ok "$name"
        else
            error "$name is missing ($path)."
            failed=1
        fi
    }

    verify_command "XFCE session" "xfce4-session"
    verify_command "D-Bus session" "dbus-run-session"
    verify_command "xset" "xset"
    verify_command "pgrep" "pgrep"
    verify_command "Git" "git"
    verify_command "Java" "java"
    verify_command "Maven" "mvn"
    verify_command "Node.js" "node"
    verify_command "Python" "python3"
    verify_command "code-server" "code-server"

    verify_file "D-Bus machine ID" "/etc/machine-id"
    verify_file "XFCE launcher" "/usr/local/bin/termux-dev-xfce"
    verify_file "code-server launcher" "/usr/local/bin/termux-dev-code-server"

    if ubuntu_exec bash -lc "id '$UBUNTU_USER' >/dev/null 2>&1"; then
        ok "Ubuntu user: $UBUNTU_USER"
    else
        error "Ubuntu user '$UBUNTU_USER' is missing."
        failed=1
    fi

    if ubuntu_exec bash -lc "sudo -n true >/dev/null 2>&1" >/dev/null 2>&1; then
        ok "sudo"
    else
        error "sudo configuration failed."
        failed=1
    fi

    if command -v pgrep >/dev/null 2>&1; then
        ok "Termux pgrep"
    else
        error "Termux pgrep is missing."
        failed=1
    fi

    if command -v termux-x11 >/dev/null 2>&1; then
        ok "Termux:X11"
    else
        error "Termux:X11 is missing."
        failed=1
    fi

    return "$failed"
}

# Config-only steps. These never touch the network.
apply_configuration() {
    setup_user || return 1
    setup_machine_id || return 1
    write_launchers || return 1
    configure_xfce || return 1
    configure_environment || return 1
    configure_termux_shell || return 1
    configure_code_server || return 1
}

install_all() {
    require_termux

    echo
    info "Preparing Termux Ubuntu Development Environment"
    echo

    setup_termux || exit 1
    install_ubuntu || exit 1
    setup_ubuntu || exit 1
    install_code_server || exit 1
    apply_configuration || exit 1

    echo
    info "Running final verification..."
    echo

    if ! verify_ubuntu; then
        echo
        error "Installation completed with verification errors."
        echo "Run:"
        echo "  ./install.sh repair"
        exit 1
    fi

    echo
    ok "Development environment is ready."
    echo
    echo "Ubuntu user : $UBUNTU_USER"
    echo "Projects    : $UBUNTU_HOME/projects"
    echo "VS Code     : http://127.0.0.1:8080"
    echo
    echo "Start with:"
    echo "  ./start.sh"
}

# Re-applies every configuration fix without downloading anything.
repair() {
    require_termux

    echo
    info "Repairing configuration (no downloads)"
    echo

    if ! proot-distro login "$UBUNTU_NAME" -- true >/dev/null 2>&1; then
        error "Ubuntu is not installed. Run ./install.sh first."
        exit 1
    fi

    apply_configuration || exit 1

    echo
    info "Verifying repaired environment..."
    echo

    if ! verify_ubuntu; then
        echo
        error "Some components are missing and cannot be repaired offline."
        echo "Run:"
        echo "  ./install.sh repair --full"
        exit 1
    fi

    echo
    ok "Repair completed successfully."
}

# Repair plus installation of anything genuinely missing.
repair_full() {
    require_termux

    echo
    info "Full repair (installs only what is missing)"
    echo

    setup_termux || exit 1
    install_ubuntu || exit 1
    setup_ubuntu || exit 1
    install_code_server || exit 1
    apply_configuration || exit 1

    echo
    info "Verifying repaired environment..."
    echo

    if ! verify_ubuntu; then
        echo
        error "Repair completed but some components are still missing."
        exit 1
    fi

    echo
    ok "Full repair completed successfully."
}

verify_only() {
    require_termux

    echo

    if ! verify_ubuntu; then
        echo
        error "Verification failed."
        echo "Run:"
        echo "  ./install.sh repair"
        exit 1
    fi

    echo
    ok "Environment verified."
}

case "${1:-install}" in
    install)
        install_all
        ;;
    repair)
        if [ "${2:-}" = "--full" ]; then
            repair_full
        else
            repair
        fi
        ;;
    verify)
        verify_only
        ;;
    *)
        echo "Usage:"
        echo "  $0                  Install / verify environment"
        echo "  $0 repair           Re-apply configuration fixes (no downloads)"
        echo "  $0 repair --full    Repair and install anything missing"
        echo "  $0 verify           Verify only"
        exit 1
        ;;
esac
