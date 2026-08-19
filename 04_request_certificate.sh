#!/usr/bin/env bash
# 04_request_certificate.sh — install certbot's Apache plugin and request
# a Let's Encrypt certificate. Certbot will rewrite qlever.conf to add a
# 443 VirtualHost with TLS automatically.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

pause_for_manual_step "Confirm DNS for '${DOMAIN}' points at this server's PUBLIC IP address.
From another machine, run:  dig +short ${DOMAIN}
It must match this server's public IP, or Let's Encrypt's HTTP-01
challenge (over port 80) will fail."

log "Installing certbot (Apache plugin)..."
if command -v certbot >/dev/null 2>&1; then
    log "certbot already installed."
else
    sudo apt-get update -y
    sudo apt-get install -y certbot python3-certbot-apache || die "Failed to install certbot."
fi

log "Requesting/renewing certificate for ${DOMAIN}..."
if sudo certbot --apache -d "${DOMAIN}" -m "${CERT_EMAIL}" --agree-tos --redirect --non-interactive; then
    log "Certificate obtained non-interactively."
else
    warn "Non-interactive run failed or needs input — retrying interactively."
    sudo certbot --apache -d "${DOMAIN}" -m "${CERT_EMAIL}" || die "certbot failed. Check DNS and that port 80 is reachable from the internet."
fi

log "Certbot's systemd timer handles renewal automatically — nothing to schedule yourself."
log "Apache should now be serving https://${DOMAIN}/ with a valid certificate."
next_step "run ./05_setup_qlever_dataset.sh"
