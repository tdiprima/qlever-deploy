#!/usr/bin/env bash
# 04_install_certificate.sh — install an institutionally issued TLS
# certificate and publish the QLever reverse proxy over HTTPS.
#
# Replaces the Let's Encrypt flow, which cannot work here: Stony Brook's
# perimeter firewall blocks the "acme-protocol" application by User-Agent
# and answers HTTP-01 validation with an "Application Blocked" 503 before
# the request reaches this server. Reproduce with:
#   curl -A "Mozilla/5.0 (compatible; Let's Encrypt validation server; \
#            +https://www.letsencrypt.org)" http://<domain>/
#
# Expects: ./02_setup_apache.sh and ./02b_patch_apache_proxy.sh have run,
#          and CERT_FILE / CERT_KEY_FILE / CERT_CHAIN_FILE in config.sh
#          point at the files your issuer supplied.
# Produces: /etc/apache2/sites-available/qlever-ssl.conf serving :443.
#
# Safe to rerun — that is how you install a renewed certificate.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

readonly PROXY_INCLUDE_FILE="/etc/apache2/qlever-proxy.conf"
readonly SSL_VHOST_FILE="/etc/apache2/sites-available/qlever-ssl.conf"
readonly HTTP_VHOST_FILE="/etc/apache2/sites-available/qlever.conf"
readonly INSTALLED_CERT="/etc/ssl/certs/${DOMAIN}-fullchain.crt"
readonly INSTALLED_KEY="/etc/ssl/private/${DOMAIN}.key"
readonly EXPIRY_WARN_DAYS=30

BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_SUFFIX

should_redirect_http="false"
install_completed="false"
backed_up_files=()

usage() {
    cat <<'USAGE_EOF'
Usage: ./04_install_certificate.sh [--redirect-http] [--help]

  --redirect-http  Also make the port 80 vhost 301-redirect to HTTPS.
                   Omitted by default so plain HTTP keeps working while
                   you test.
  --help           Show this message.

Reads CERT_FILE, CERT_KEY_FILE and CERT_CHAIN_FILE from config.sh.
USAGE_EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --redirect-http) should_redirect_http="true" ;;
            --help|-h) usage; exit 0 ;;
            *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

on_exit() {
    if [[ "$install_completed" == "true" ]]; then
        return 0
    fi
    if [[ "${#backed_up_files[@]}" -gt 0 ]]; then
        warn "Exiting before the install was verified — rolling back."
        restore_backups
    fi
}
trap on_exit EXIT

back_up_file() {
    local target="$1"
    [[ -f "$target" ]] || return 0
    sudo cp --preserve=all "$target" "${target}${BACKUP_SUFFIX}" \
        || die "Could not back up $target"
    backed_up_files+=("$target")
    log "Backed up $target -> ${target}${BACKUP_SUFFIX}"
}

restore_backups() {
    local target
    for target in "${backed_up_files[@]:-}"; do
        [[ -n "$target" ]] || continue
        sudo cp --preserve=all "${target}${BACKUP_SUFFIX}" "$target" \
            && warn "Restored $target"
    done
}

validate_preconditions() {
    command -v openssl >/dev/null 2>&1 || die "openssl not found. Install it: sudo apt-get install -y openssl"
    command -v apache2ctl >/dev/null 2>&1 || die "apache2ctl not found. Run ./02_setup_apache.sh first."

    [[ -f "$PROXY_INCLUDE_FILE" ]] \
        || die "Missing ${PROXY_INCLUDE_FILE}. Run ./02b_patch_apache_proxy.sh first."

    [[ -n "$CERT_FILE" && -n "$CERT_KEY_FILE" ]] \
        || die "Set CERT_FILE and CERT_KEY_FILE in config.sh."

    [[ -f "$CERT_FILE" ]]     || die "Certificate not found: $CERT_FILE"
    [[ -f "$CERT_KEY_FILE" ]] || die "Private key not found: $CERT_KEY_FILE"

    if [[ -n "$CERT_CHAIN_FILE" && ! -f "$CERT_CHAIN_FILE" ]]; then
        die "Chain file configured but not found: $CERT_CHAIN_FILE"
    fi
    if [[ -z "$CERT_CHAIN_FILE" ]]; then
        warn "No CERT_CHAIN_FILE set. Without the issuer's intermediates most"
        warn "browsers and API clients will reject this certificate."
    fi
}

# A cert that does not match its key produces an Apache that refuses to
# start, so check before touching anything. Comparing public keys works
# for RSA and EC alike; comparing moduli would not.
verify_key_matches_certificate() {
    local cert_pubkey key_pubkey

    cert_pubkey="$(openssl x509 -in "$CERT_FILE" -noout -pubkey 2>/dev/null)" \
        || die "Could not parse certificate: $CERT_FILE (is it PEM?)"
    key_pubkey="$(openssl pkey -in "$CERT_KEY_FILE" -pubout 2>/dev/null)" \
        || die "Could not parse private key: $CERT_KEY_FILE (is it PEM, and unencrypted?)"

    # Guard against both being empty, which would compare equal.
    [[ -n "$cert_pubkey" && -n "$key_pubkey" ]] \
        || die "Could not extract a public key from the certificate or the key file."

    [[ "$cert_pubkey" == "$key_pubkey" ]] \
        || die "Certificate and private key DO NOT MATCH.
  cert: $CERT_FILE
  key:  $CERT_KEY_FILE
Apache would fail to start. Check you were given a matching pair."

    log "Certificate and private key match."
}

# Apache will serve a cert for the wrong name quite happily; browsers
# will not. Catch it here instead of in the field.
verify_certificate_covers_domain() {
    local names
    names="$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null \
        | grep -o 'DNS:[^,]*' | sed 's/^DNS://' | tr -d ' ')"

    if [[ -z "$names" ]]; then
        names="$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null \
            | grep -o 'CN *= *[^,/]*' | sed 's/CN *= *//' | tr -d ' ')"
    fi

    [[ -n "$names" ]] || die "Could not read any hostname from $CERT_FILE"

    local name
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ "$name" == "$DOMAIN" ]]; then
            log "Certificate covers ${DOMAIN}."
            return 0
        fi
        # Wildcard: *.example.com matches host.example.com, one label only.
        if [[ "$name" == '*.'* && "$DOMAIN" == *".${name#\*.}" ]]; then
            local remainder="${DOMAIN%".${name#\*.}"}"
            if [[ "$remainder" != *.* ]]; then
                log "Certificate covers ${DOMAIN} via wildcard ${name}."
                return 0
            fi
        fi
    done <<< "$names"

    die "Certificate does NOT cover '${DOMAIN}'.
It is valid for: $(echo "$names" | tr '\n' ' ')
Fix DOMAIN in config.sh, or get a certificate for the right name."
}

verify_certificate_validity_dates() {
    if ! openssl x509 -in "$CERT_FILE" -noout -checkend 0 >/dev/null 2>&1; then
        die "Certificate has EXPIRED: $(openssl x509 -in "$CERT_FILE" -noout -enddate)"
    fi

    local warn_seconds=$(( EXPIRY_WARN_DAYS * 86400 ))
    if ! openssl x509 -in "$CERT_FILE" -noout -checkend "$warn_seconds" >/dev/null 2>&1; then
        warn "Certificate expires in under ${EXPIRY_WARN_DAYS} days: $(openssl x509 -in "$CERT_FILE" -noout -enddate)"
    fi

    log "Certificate valid: $(openssl x509 -in "$CERT_FILE" -noout -enddate | sed 's/notAfter=/expires /')"
}

# Modern Apache wants leaf + intermediates in one SSLCertificateFile;
# SSLCertificateChainFile has been deprecated since 2.4.8.
install_certificate_files() {
    local fullchain
    fullchain="$(cat "$CERT_FILE")" || die "Could not read $CERT_FILE"

    if [[ -n "$CERT_CHAIN_FILE" ]]; then
        fullchain="${fullchain}"$'\n'"$(cat "$CERT_CHAIN_FILE")" \
            || die "Could not read $CERT_CHAIN_FILE"
    fi

    back_up_file "$INSTALLED_CERT"
    printf '%s\n' "$fullchain" | sudo tee "$INSTALLED_CERT" >/dev/null \
        || die "Could not write $INSTALLED_CERT"
    sudo chown root:root "$INSTALLED_CERT"
    sudo chmod 644 "$INSTALLED_CERT"
    log "Installed certificate chain: $INSTALLED_CERT"

    # The key is the secret. root-only, and never echoed anywhere.
    back_up_file "$INSTALLED_KEY"
    sudo install --owner=root --group=root --mode=0600 \
        "$CERT_KEY_FILE" "$INSTALLED_KEY" \
        || die "Could not install private key to $INSTALLED_KEY"
    log "Installed private key: $INSTALLED_KEY (mode 0600, root only)"
}

enable_ssl_module() {
    if sudo apache2ctl -M 2>/dev/null | grep -q 'ssl_module'; then
        log "Module 'ssl' already enabled."
        return 0
    fi
    log "Enabling module 'ssl'..."
    sudo a2enmod ssl >/dev/null || die "Failed to enable mod_ssl."
}

write_ssl_vhost() {
    back_up_file "$SSL_VHOST_FILE"
    sudo tee "$SSL_VHOST_FILE" >/dev/null <<VHOST_EOF
# GENERATED by 04_install_certificate.sh — rerun that script to update.
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${DOMAIN}

    SSLEngine on
    SSLCertificateFile    ${INSTALLED_CERT}
    SSLCertificateKeyFile ${INSTALLED_KEY}

    # Tell browsers to stick to HTTPS. Remove this if you ever need to
    # serve this hostname over plain HTTP again — browsers cache it.
    Header always set Strict-Transport-Security "max-age=15768000"

    ErrorLog \${APACHE_LOG_DIR}/qlever_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/qlever_ssl_access.log combined

    Include ${PROXY_INCLUDE_FILE}
</VirtualHost>
</IfModule>
VHOST_EOF
    log "Wrote $SSL_VHOST_FILE"
    sudo a2ensite qlever-ssl.conf >/dev/null || die "Could not enable qlever-ssl.conf"
}

add_http_redirect() {
    if [[ "$should_redirect_http" != "true" ]]; then
        log "Leaving port 80 serving normally (pass --redirect-http to force HTTPS)."
        return 0
    fi

    [[ -f "$HTTP_VHOST_FILE" ]] || die "Missing $HTTP_VHOST_FILE"

    if grep --quiet 'Redirect permanent / https://' "$HTTP_VHOST_FILE"; then
        log "Port 80 already redirects to HTTPS."
        return 0
    fi

    back_up_file "$HTTP_VHOST_FILE"
    sudo sed --in-place \
        "s%^\([[:space:]]*\)</VirtualHost>%\1    Redirect permanent / https://${DOMAIN}/\n\1</VirtualHost>%" \
        "$HTTP_VHOST_FILE" || die "Could not add redirect to $HTTP_VHOST_FILE"
    log "Port 80 now redirects to https://${DOMAIN}/"
}

verify_and_reload() {
    log "Testing Apache configuration..."
    if ! sudo apache2ctl configtest; then
        err "Apache config test FAILED. Rolling back."
        restore_backups
        sudo a2dissite qlever-ssl.conf >/dev/null 2>&1
        die "No changes kept. Apache was not reloaded."
    fi

    log "Config test passed. Reloading Apache..."
    sudo systemctl reload apache2 || die "Apache reload failed. Check: systemctl status apache2"
}

verify_tls_locally() {
    local subject
    subject="$(echo \
        | openssl s_client -connect "127.0.0.1:443" -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null)"

    if [[ -n "$subject" ]]; then
        log "TLS handshake OK on :443 — serving ${subject}"
    else
        warn "Could not complete a local TLS handshake on :443. Check: sudo systemctl status apache2"
    fi
}

main() {
    parse_arguments "$@"

    validate_preconditions
    verify_key_matches_certificate
    verify_certificate_covers_domain
    verify_certificate_validity_dates

    install_certificate_files
    enable_ssl_module
    write_ssl_vhost
    add_http_redirect
    verify_and_reload
    install_completed="true"

    verify_tls_locally

    echo
    log "HTTPS is live: https://${DOMAIN}/"
    warn "503 at / until the Web UI runs (qlever ui), and at /sparql/ until step 06."
    next_step "run ./05_setup_qlever_dataset.sh"
}

main "$@"
