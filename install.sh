#!/data/data/com.termux/files/usr/bin/bash

set -u

UBUNTU="ubuntu"
DEV_USER="developer"
DEV_HOME="/home/$DEV_USER"
CODE_SERVER_PORT="8080"
STATE_DIR="$HOME/.termux-dev"

info(){ echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $1"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $1"; }
err(){ echo -e "\033[1;31m[ERROR]\033[0m $1"; }

need_cmd(){
    command -v "$1" >/dev/null 2>&1
}

run_ubuntu(){
    proot-distro login "$UBUNTU" --shared-tmp -- /bin/bash -lc "$1"
}

install_termux_packages(){
    info "Preparing Termux..."

    pkg update -y || { err "pkg update failed"; exit 1; }

    for p in proot-distro git curl wget; do
        if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
            ok "$p already installed"
        else
            pkg install "$p" -y || { err "Failed to install $p"; exit 1; }
        fi
    done
}

install_ubuntu(){
    if proot-distro list 2>/dev/null | grep -q "^ubuntu .* installed"; then
        ok "Ubuntu already installed"
    else
        info "Installing Ubuntu..."
        proot-distro install "$UBUNTU" || {
            err "Ubuntu installation failed"
            exit 1
        }
    fi
}

setup_ubuntu(){
    info "Preparing Ubuntu..."

    run_ubuntu "export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y sudo git curl wget ca-certificates unzip zip tar nano vim tmux openssh-client build-essential
"

    info "Creating developer user..."

    run_ubuntu "
if ! id '$DEV_USER' >/dev/null 2>&1; then
    useradd -m -s /bin/bash '$DEV_USER'
fi
usermod -aG sudo '$DEV_USER'
mkdir -p '$DEV_HOME/projects/java' '$DEV_HOME/projects/spring' '$DEV_HOME/projects/ai' '$DEV_HOME/projects/experiments'
chown -R '$DEV_USER:$DEV_USER' '$DEV_HOME'
"

    ok "Ubuntu developer user ready"
}

configure_sudo(){
    info "Configuring passwordless sudo for the developer user..."

    run_ubuntu "
cat > /etc/sudoers.d/$DEV_USER <<EOF
$DEV_USER ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/$DEV_USER
visudo -cf /etc/sudoers.d/$DEV_USER
"

    ok "sudo configured"
}

install_dev_tools(){
    info "Installing development tools inside Ubuntu..."

    run_ubuntu "
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openjdk-17-jdk maven nodejs npm python3 python3-pip python3-venv
"

    ok "Java / Maven / Node.js / Python installed"
}

install_code_server(){
    info "Installing code-server inside Ubuntu..."

    run_ubuntu "
if ! command -v code-server >/dev/null 2>&1; then
    curl -fsSL https://code-server.dev/install.sh | sh
fi
"

    info "Configuring code-server..."

    run_ubuntu "
mkdir -p '$DEV_HOME/.config/code-server'

cat > '$DEV_HOME/.config/code-server/config.yaml' <<EOF
bind-addr: 127.0.0.1:$CODE_SERVER_PORT
auth: none
cert: false
EOF

chown -R '$DEV_USER:$DEV_USER' '$DEV_HOME/.config'

mkdir -p '$DEV_HOME/.local/bin'
cat > '$DEV_HOME/.local/bin/start-code-server' <<EOF
#!/bin/bash
exec code-server '$DEV_HOME/projects'
EOF
chmod +x '$DEV_HOME/.local/bin/start-code-server'
chown -R '$DEV_USER:$DEV_USER' '$DEV_HOME/.local'

    ok "code-server configured"
}

configure_user_shell(){
    info "Configuring developer shell..."

    run_ubuntu "
cat > '$DEV_HOME/.bashrc.termux-dev' <<'EOF'
export DEV_HOME=/home/developer/projects
export DISPLAY=:1
export PATH=\"\$HOME/.local/bin:\$PATH\"

alias cdev='cd \$DEV_HOME'
alias cjava='cd \$DEV_HOME/java'
alias cspring='cd \$DEV_HOME/spring'
alias cair='cd \$DEV_HOME/ai'
alias rootme='sudo -i'
EOF

cat >> '$DEV_HOME/.bashrc' <<'EOF'

[ -f ~/.bashrc.termux-dev ] && . ~/.bashrc.termux-dev
EOF

chown '$DEV_USER:$DEV_USER' '$DEV_HOME/.bashrc' '$DEV_HOME/.bashrc.termux-dev'
"

    ok "Developer shell configured"
}

create_state(){
    mkdir -p "$STATE_DIR"
    cat > "$STATE_DIR/config" <<EOF
DISPLAY=:1
CODE_SERVER_PORT=$CODE_SERVER_PORT
UBUNTU=$UBUNTU
DEV_USER=$DEV_USER
EOF
}

install_all(){
    install_termux_packages
    install_ubuntu
    setup_ubuntu
    configure_sudo
    install_dev_tools
    install_code_server
    configure_user_shell
    create_state

    echo
    ok "Installation completed."
    echo
    echo "Start the environment with:"
    echo "  ./start.sh"
    echo
    echo "Ubuntu:"
    echo "  proot-distro login ubuntu --shared-tmp"
    echo
    echo "VS Code UI:"
    echo "  http://127.0.0.1:8080"
}

repair(){
    info "Repairing/updating Ubuntu development environment..."
    install_ubuntu
    setup_ubuntu
    configure_sudo
    install_dev_tools
    install_code_server
    configure_user_shell
    create_state
    ok "Repair completed."
}

case "${1:-install}" in
    install) install_all ;;
    repair) repair ;;
    *)
        echo "Usage: $0 [install|repair]"
        exit 1
        ;;
esac
