#!/usr/bin/env bash
# 01_install_qlever.sh — idempotent installer for QLever's dependencies and CLI.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

require_cmd_or_install() {
    # $1 = command to check, $2 = apt package name
    local cmd="$1" pkg="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        log "'$cmd' already installed, skipping."
    else
        log "Installing package '$pkg' (provides '$cmd')..."
        sudo apt-get install -y "$pkg" || die "Failed to install '$pkg'."
    fi
}

log "Updating apt package index..."
sudo apt-get update -y || warn "apt-get update failed; continuing with cached package lists."

require_cmd_or_install python3 python3
require_cmd_or_install pip3 python3-pip
require_cmd_or_install curl curl
require_cmd_or_install tar tar

if command -v docker >/dev/null 2>&1; then
    log "Docker already installed, skipping."
else
    log "Installing Docker (docker.io)..."
    sudo apt-get install -y docker.io || die "Failed to install docker.io."
fi

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet docker; then
        log "Starting docker service..."
        sudo systemctl enable --now docker || warn "Could not enable/start docker automatically."
    else
        log "Docker service already running."
    fi
fi

if groups "$USER" | grep -qw docker; then
    log "User '$USER' already in 'docker' group."
else
    log "Adding user '$USER' to 'docker' group (requires re-login to take effect)..."
    sudo usermod -aG docker "$USER" || warn "Could not add user to docker group; you may need sudo for docker commands."
fi

if command -v pipx >/dev/null 2>&1; then
    log "pipx already installed, skipping."
else
    log "Installing pipx..."
    sudo apt-get install -y pipx || {
        warn "apt install of pipx failed; falling back to pip --user."
        python3 -m pip install --user pipx --break-system-packages || die "Failed to install pipx."
    }
fi

python3 -m pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"

if command -v qlever >/dev/null 2>&1; then
    log "'qlever' CLI already installed, checking for updates..."
    pipx upgrade qlever || warn "Could not upgrade qlever via pipx; continuing with existing version."
else
    log "Installing 'qlever' CLI via pipx..."
    pipx install qlever || die "pipx install of qlever failed."
fi

log "Verifying installation..."
if command -v qlever >/dev/null 2>&1; then
    log "qlever CLI found: $(command -v qlever)"
    qlever --version 2>/dev/null || warn "qlever installed but '--version' failed; check manually."
else
    warn "qlever not on PATH in this shell yet. Open a new terminal, or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

if docker info >/dev/null 2>&1; then
    log "Docker is accessible without sudo."
else
    warn "Docker needs sudo in this session still. Log out/in (or run 'newgrp docker') before 06_index_and_start.sh if this persists."
fi

log "QLever dependencies installed."
next_step "run ./02_setup_apache.sh"
