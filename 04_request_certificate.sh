#!/usr/bin/env bash
# 04_request_certificate.sh — install certbot and request a Let's Encrypt
# certificate. Certbot's Apache installer writes a 443 VirtualHost
# (qlever-le-ssl.conf) and wires the certificate into it.
#
# REQUIRES ./02b_patch_apache_proxy.sh to have run first. The catch-all
# "ProxyPass /" from 02_setup_apache.sh forwards the ACME challenge to
# QLever, which answers 503 (or nothing at all) and validation fails.
# 02b installs the "ProxyPass /.well-known/acme-challenge/ !" carve-out
# that lets the challenge be served from disk instead.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

readonly PROXY_INCLUDE_FILE="/etc/apache2/qlever-proxy.conf"
readonly ACME_WEBROOT="/var/www/html"
readonly ACME_CHALLENGE_DIR="${ACME_WEBROOT}/.well-known/acme-challenge"

# The catch-all proxy must exempt the ACME path or validation returns 503.
verify_acme_carve_out() {
    if [[ ! -f "$PROXY_INCLUDE_FILE" ]]; then
        die "Missing ${PROXY_INCLUDE_FILE}.
Run ./02b_patch_apache_proxy.sh first — without its ACME carve-out the
'ProxyPass /' rule sends Let's Encrypt's challenge to QLever and the
challenge fails with HTTP 503."
    fi

    if ! grep --quiet --fixed-strings 'ProxyPass /.well-known/acme-challenge/ !' "$PROXY_INCLUDE_FILE"; then
        die "${PROXY_INCLUDE_FILE} has no ACME carve-out.
Expected the line: ProxyPass /.well-known/acme-challenge/ !
Rerun ./02b_patch_apache_proxy.sh."
    fi

    log "ACME carve-out present in ${PROXY_INCLUDE_FILE}."
}

# certbot --webroot writes the challenge token here; Apache serves it via
# the Alias in qlever-proxy.conf.
prepare_challenge_directory() {
    sudo mkdir --parents "$ACME_CHALLENGE_DIR" || die "Could not create $ACME_CHALLENGE_DIR"
    log "Challenge directory ready: $ACME_CHALLENGE_DIR"
}

install_certbot() {
    if command -v certbot >/dev/null 2>&1; then
        log "certbot already installed."
        return 0
    fi

    log "Installing certbot (Apache plugin)..."
    sudo apt-get update -y
    sudo apt-get install -y certbot python3-certbot-apache || die "Failed to install certbot."
}

# Prove Apache serves the challenge path from disk before spending a real
# Let's Encrypt attempt on it. Failed validations are rate-limited.
#
# The Host header is essential: Apache picks the vhost by name, so a
# request to 127.0.0.1 without it matches the DEFAULT vhost, not the
# QLever one, and the test passes while the real challenge still fails.
test_challenge_path_locally() {
    local token_file="${ACME_CHALLENGE_DIR}/qlever-deploy-selftest"
    local token_url="/.well-known/acme-challenge/qlever-deploy-selftest"
    local expected="qlever-deploy-selftest"
    local via_vhost via_public

    echo "$expected" | sudo tee "$token_file" >/dev/null \
        || die "Could not write $token_file"

    # Same vhost Let's Encrypt will select.
    via_vhost="$(curl --silent --max-time 10 \
        --header "Host: ${DOMAIN}" \
        "http://127.0.0.1${token_url}" || true)"

    # The actual round trip, over the public internet.
    via_public="$(curl --silent --max-time 15 \
        "http://${DOMAIN}${token_url}" || true)"

    sudo rm --force "$token_file"

    if [[ "$via_vhost" != "$expected" ]]; then
        die "Self-test FAILED on the '${DOMAIN}' vhost (served locally).
Got: '${via_vhost}'
A 503 body here means the catch-all ProxyPass still wins. Check that
${PROXY_INCLUDE_FILE} is Include-d by the vhost serving ${DOMAIN}:
  sudo apache2ctl -S
  sudo systemctl reload apache2"
    fi
    log "Self-test passed on the ${DOMAIN} vhost."

    if [[ "$via_public" != "$expected" ]]; then
        die "Self-test FAILED over the public internet.
Got: '${via_public}'
Apache serves this path correctly on the server, so the request is being
blocked or altered between the internet and this host (campus firewall,
upstream proxy). Let's Encrypt would hit the same wall."
    fi
    log "Self-test passed over the public internet."
}

# Let's Encrypt staging has far looser rate limits and does not consume
# production failed-validation budget. Prove the whole path works here
# first; --dry-run neither saves nor installs anything.
validate_against_staging() {
    log "Validating against Let's Encrypt STAGING (no rate-limit cost)..."
    if sudo certbot certonly --dry-run \
        --authenticator webroot \
        --webroot-path "$ACME_WEBROOT" \
        --domain "$DOMAIN" \
        --email "$CERT_EMAIL" \
        --agree-tos \
        --non-interactive; then
        log "Staging validation PASSED. Safe to request the real certificate."
        return 0
    fi

    die "Staging validation FAILED — no production attempt was made, so your
rate-limit budget is untouched. Fix the cause above and rerun.
Full detail: /var/log/letsencrypt/letsencrypt.log"
}

request_certificate() {
    log "Requesting/renewing certificate for ${DOMAIN}..."

    # webroot authenticator (deterministic: serves from ACME_WEBROOT) plus
    # the apache installer (writes the 443 vhost). The apache AUTHENTICATOR
    # is deliberately not used — it loses to ProxyPass.
    local certbot_args=(
        --authenticator webroot
        --webroot-path "$ACME_WEBROOT"
        --installer apache
        --domain "$DOMAIN"
        --email "$CERT_EMAIL"
        --agree-tos
        --redirect
    )

    if sudo certbot "${certbot_args[@]}" --non-interactive; then
        log "Certificate obtained."
        return 0
    fi

    warn "Non-interactive run failed or needs input — retrying interactively."
    sudo certbot "${certbot_args[@]}" \
        || die "certbot failed. See /var/log/letsencrypt/letsencrypt.log for the real reason."
}

main() {
    pause_for_manual_step "Confirm DNS for '${DOMAIN}' points at this server's PUBLIC IP address.
From another machine, run:  dig +short ${DOMAIN}
It must match this server's public IP, or Let's Encrypt's HTTP-01
challenge (over port 80) will fail."

    verify_acme_carve_out
    install_certbot
    prepare_challenge_directory
    test_challenge_path_locally
    validate_against_staging
    request_certificate

    log "Certbot's systemd timer handles renewal automatically — nothing to schedule yourself."
    log "Apache should now be serving https://${DOMAIN}/ with a valid certificate."
    next_step "run ./05_setup_qlever_dataset.sh"
}

main "$@"
