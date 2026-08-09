#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU_NAME="ubuntu"
UBUNTU_USER="developer"
UBUNTU_HOME="/home/$UBUNTU_USER"

info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

require_termux() {
    command -v pkg >/dev/null 2>&1 || {
        error "Run this script from Termux."
        exit 1
    }

    command -v git >/dev/null 2>&1 || {
        error "Native Termux Git is required to bootstrap this repository."
        echo "Run: pkg update && pkg install git -y"
        exit 1
    }
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null |
        grep -q "install ok installed"
}

install_termux_package() {
    local package="$1"
    if package_installed "$package"; then
        ok "$package already installed."
    else
        info "Installing $package..."
        pkg install "$package" -y || {
            error "Failed to install $package."
            return 1
        }
        ok "$package installed."
    fi
}

setup_termux() {
    info "Preparing native Termux..."
    install_termux_package x11-repo || return 1
    install_termux_package termux-x11-nightly || return 1
    install_termux_package proot-distro || return 1
}

install_ubuntu() {
    if proot-distro login "$UBUNTU_NAME" -- true >/dev/null 2>&1; then
        ok "Ubuntu already installed."
        return 0
    fi

    info "Installing Ubuntu..."
    proot-distro install "$UBUNTU_NAME" || {
        error "Failed to install Ubuntu."
        return 1
    }
    ok "Ubuntu installed."
}

ubuntu_exec() {
    proot-distro login "$UBUNTU_NAME" --shared-tmp -- "$@"
}

setup_ubuntu() {
    info "Updating Ubuntu package lists..."
    ubuntu_exec apt-get update || return 1

    info "Installing Ubuntu development packages..."
    ubuntu_exec env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sudo git curl wget ca-certificates unzip zip tar gzip \
        vim nano tmux openssh-client jq ripgrep fd-find tree procps \
        file which python3 python3-pip python3-venv nodejs npm \
        dbus-x11 firefox openjdk-17-jdk maven || {
        error "Failed to install Ubuntu packages."
        return 1
    }

    ok "Ubuntu development packages ready."
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

        echo '$UBUNTU_USER ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers.d/termux-dev
        chmod 440 /etc/sudoers.d/termux-dev
    " || {
        error "Failed to configure developer user."
        return 1
    }

    ok "Developer user + sudo ready."
}

install_code_server() {
    info "Installing code-server..."

    ubuntu_exec bash -c '
        if command -v code-server >/dev/null 2>&1; then
            exit 0
        fi
        curl -fsSL https://code-server.dev/install.sh | sh
    ' || {
        error "Failed to install code-server."
        return 1
    }

    ok "code-server ready."
}

configure_environment() {
    info "Configuring environment..."

    ubuntu_exec bash -c "
        cat > /etc/profile.d/termux-dev.sh <<'EOF'
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export DEV_HOME=/home/developer
EOF

        mkdir -p '$UBUNTU_HOME/projects'
        chown -R '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME/projects'

        cat > '$UBUNTU_HOME/.bashrc.termux-dev' <<'EOF'
export DISPLAY=:1
export DEV_HOME=/home/developer
alias cdev='cd /home/developer'
alias cproj='cd /home/developer/projects'
alias root='sudo -i'
EOF

        grep -qxF 'source ~/.bashrc.termux-dev' '$UBUNTU_HOME/.bashrc' 2>/dev/null ||
            echo 'source ~/.bashrc.termux-dev' >> '$UBUNTU_HOME/.bashrc'

        chown '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME/.bashrc' '$UBUNTU_HOME/.bashrc.termux-dev'
    " || return 1

    ok "Environment configured."
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

        chown -R '$UBUNTU_USER:$UBUNTU_USER' '$UBUNTU_HOME/.config'
    " || return 1

    warn "Initial code-server password: termux-dev"
}

install_all() {
    require_termux
    echo

    setup_termux || exit 1
    install_ubuntu || exit 1
    setup_ubuntu || exit 1
    setup_user || exit 1
    install_code_server || exit 1
    configure_environment || exit 1
    configure_code_server || exit 1

    echo
    ok "Development environment is ready."
    echo "Projects : $UBUNTU_HOME/projects"
    echo "VS Code  : http://127.0.0.1:8080"
    echo
    echo "Run: ./start.sh"
}

case "${1:-install}" in
    install|repair) install_all ;;
    *) echo "Usage: $0 [install|repair]"; exit 1 ;;
esac
