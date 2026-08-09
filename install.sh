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

setup_ubuntu() {
    info "Updating Ubuntu package lists..."

    ubuntu_exec apt-get update || {
        error "Ubuntu apt update failed."
        return 1
    }

    info "Installing Ubuntu development environment..."

    ubuntu_exec env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sudo \
        git \
        curl \
        wget \
        ca-certificates \
        unzip \
        zip \
        tar \
        gzip \
        vim \
        nano \
        tmux \
        openssh-client \
        jq \
        ripgrep \
        fd-find \
        tree \
        procps \
        file \
        which \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        dbus-x11 \
        xfce4 \
        xfce4-goodies \
        firefox \
        openjdk-17-jdk \
        maven \
        || {
            error "Failed to install Ubuntu packages."
            return 1
        }

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

configure_environment() {
    info "Configuring Ubuntu environment..."

    ubuntu_exec bash -c "
        cat > /etc/profile.d/termux-dev.sh <<'EOF'
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export DEV_HOME=/home/developer
EOF

        mkdir -p '$UBUNTU_HOME/projects'

        cat > '$UBUNTU_HOME/.bashrc.termux-dev' <<'EOF'
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export DEV_HOME=/home/developer

alias cdev='cd /home/developer'
alias cproj='cd /home/developer/projects'
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

    verify_command "XFCE" "startxfce4"
    verify_command "XFCE session" "xfce4-session"
    verify_command "D-Bus session" "dbus-run-session"
    verify_command "Git" "git"
    verify_command "Java" "java"
    verify_command "Maven" "mvn"
    verify_command "Node.js" "node"
    verify_command "Python" "python3"
    verify_command "code-server" "code-server"

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

    return "$failed"
}

install_all() {
    require_termux

    echo
    info "Preparing Termux Ubuntu Development Environment"
    echo

    setup_termux || exit 1
    install_ubuntu || exit 1
    setup_ubuntu || exit 1
    setup_user || exit 1
    install_code_server || exit 1
    configure_environment || exit 1
    configure_code_server || exit 1

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

repair() {
    require_termux

    echo
    info "Repairing Termux Ubuntu Development Environment"
    echo

    setup_termux || exit 1
    install_ubuntu || exit 1
    setup_ubuntu || exit 1
    setup_user || exit 1
    install_code_server || exit 1
    configure_environment || exit 1
    configure_code_server || exit 1

    echo
    info "Verifying repaired environment..."
    echo

    if ! verify_ubuntu; then
        echo
        error "Repair completed but some components are still missing."
        exit 1
    fi

    echo
    ok "Repair completed successfully."
}

case "${1:-install}" in
    install)
        install_all
        ;;
    repair)
        repair
        ;;
    *)
        echo "Usage:"
        echo "  $0          Install / verify environment"
        echo "  $0 repair   Repair / verify environment"
        exit 1
        ;;
esac