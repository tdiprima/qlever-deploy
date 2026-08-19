#!/usr/bin/env bash
# 00_check_config.sh — validate config.sh and basic prerequisites.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

log "Checking configuration and prerequisites..."

[[ "$DOMAIN" == "your.domain.com" ]] && die "Edit config.sh: set DOMAIN to your real domain name first."
[[ "$CERT_EMAIL" == "you@example.com" ]] && die "Edit config.sh: set CERT_EMAIL to a real email address first."

command -v sudo >/dev/null 2>&1 || die "sudo not found. Install it, or edit these scripts to drop 'sudo' if running as root."

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    warn "This doesn't look like Ubuntu. These scripts assume apt/Ubuntu — adjust package manager calls if needed."
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    warn "Unusual architecture ($ARCH). QLever requires a 64-bit system; continuing anyway."
fi

log "Checking DNS for $DOMAIN (informational only, not blocking)..."
if command -v dig >/dev/null 2>&1; then
    RESOLVED="$(dig +short "$DOMAIN" 2>/dev/null | tail -n1)"
    if [[ -z "$RESOLVED" ]]; then
        warn "$DOMAIN does not resolve yet. That's fine for now — just make sure it points at this server's public IP before running 04_request_certificate.sh."
    else
        log "$DOMAIN currently resolves to: $RESOLVED"
    fi
else
    log "('dig' not installed — skipping DNS check, it's optional and not required to proceed.)"
fi

log "Config looks OK."
next_step "run ./01_install_qlever.sh"
