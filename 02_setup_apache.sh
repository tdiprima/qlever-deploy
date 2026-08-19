#!/usr/bin/env bash
# 02_setup_apache.sh — install Apache2, enable proxy modules, write a
# reverse-proxy vhost pointing at the local QLever port.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

log "Installing Apache2 (if needed)..."
if command -v apache2 >/dev/null 2>&1; then
    log "Apache2 already installed."
else
    sudo apt-get update -y
    sudo apt-get install -y apache2 || die "Failed to install apache2."
fi

log "Enabling required Apache modules..."
for mod in proxy proxy_http headers; do
    if sudo apache2ctl -M 2>/dev/null | grep -q "${mod}_module"; then
        log "Module '$mod' already enabled."
    else
        sudo a2enmod "$mod"
    fi
done

VHOST_FILE="/etc/apache2/sites-available/qlever.conf"
if [[ -f "$VHOST_FILE" ]]; then
    log "$VHOST_FILE already exists — leaving it untouched."
    log "(Delete it first if you want this script to regenerate it from config.sh.)"
else
    log "Writing $VHOST_FILE ..."
    sudo tee "$VHOST_FILE" >/dev/null <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:${QLEVER_PORT}/
    ProxyPassReverse / http://127.0.0.1:${QLEVER_PORT}/

    RequestHeader set X-Forwarded-Proto "http"

    ErrorLog \${APACHE_LOG_DIR}/qlever_error.log
    CustomLog \${APACHE_LOG_DIR}/qlever_access.log combined
</VirtualHost>
EOF
fi

log "Enabling qlever site..."
sudo a2ensite qlever.conf

if [[ -f /etc/apache2/sites-enabled/000-default.conf ]]; then
    warn "The default Apache site is still enabled. If it conflicts, run:"
    warn "  sudo a2dissite 000-default.conf && sudo systemctl reload apache2"
fi

sudo apache2ctl configtest || die "Apache config test failed — check $VHOST_FILE"
sudo systemctl reload apache2 || sudo systemctl restart apache2

log "Apache is now proxying http://${DOMAIN}/ -> 127.0.0.1:${QLEVER_PORT}"
log "(Certbot will upgrade this to HTTPS on port 443 in a later step.)"
next_step "run ./03_configure_ufw.sh"
