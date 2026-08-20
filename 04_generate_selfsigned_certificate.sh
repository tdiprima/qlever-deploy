#!/usr/bin/env bash
# 04_generate_selfsigned_certificate.sh — generate a self-signed TLS
# certificate for local/internal testing and write it to the paths
# CERT_FILE / CERT_KEY_FILE in config.sh.
#
# Use this instead of 04_request_certificate.sh when you have no
# Let's Encrypt path and no institutionally issued certificate yet
# (see 04_install_certificate.sh for that case). Browsers will show a
# "not private" warning for a self-signed cert — expected, fine for
# internal testing, not for public-facing production.
#
# Expects: config.sh has DOMAIN set to the real hostname.
# Produces: $CERT_FILE and $CERT_KEY_FILE (self-signed, CN=$DOMAIN).
# Then run: ./04_install_certificate.sh
#
# Safe to rerun — overwrites the previous self-signed pair.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

VALID_DAYS="365"

usage() {
    cat <<'USAGE_EOF'
Usage: ./04_generate_selfsigned_certificate.sh [--days N] [--help]

  --days N   Validity period in days (default: 365).
  --help     Show this message.

Writes a self-signed key/cert pair to CERT_FILE and CERT_KEY_FILE from
config.sh, with CN=DOMAIN. Run ./04_install_certificate.sh afterward to
install it into Apache.
USAGE_EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                [[ $# -ge 2 ]] || die "--days requires a value."
                VALID_DAYS="$2"
                shift
                ;;
            --help|-h) usage; exit 0 ;;
            *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

validate_preconditions() {
    command -v openssl >/dev/null 2>&1 \
        || die "openssl not found. Install it: sudo apt-get install -y openssl"

    [[ "$DOMAIN" != "your.domain.com" ]] \
        || die "Edit config.sh: set DOMAIN to your real hostname first."

    [[ "$VALID_DAYS" =~ ^[0-9]+$ ]] \
        || die "--days must be a positive integer, got: '$VALID_DAYS'"

    [[ -n "$CERT_FILE" && -n "$CERT_KEY_FILE" ]] \
        || die "Set CERT_FILE and CERT_KEY_FILE in config.sh."
}

warn_if_chain_configured() {
    [[ -z "$CERT_CHAIN_FILE" ]] && return 0
    [[ -f "$CERT_CHAIN_FILE" ]] || return 0
    warn "CERT_CHAIN_FILE is set to an existing file ($CERT_CHAIN_FILE)."
    warn "A self-signed cert has no intermediates — 04_install_certificate.sh"
    warn "will append it anyway, which will break the chain. Clear"
    warn "CERT_CHAIN_FILE in config.sh before installing this cert."
}

generate_selfsigned_pair() {
    local cert_dir key_dir
    cert_dir="$(dirname "$CERT_FILE")"
    key_dir="$(dirname "$CERT_KEY_FILE")"
    mkdir --parents "$cert_dir" || die "Could not create $cert_dir"
    mkdir --parents "$key_dir" || die "Could not create $key_dir"

    log "Generating self-signed certificate for CN=${DOMAIN} (${VALID_DAYS} days)..."
    openssl req -x509 -nodes -days "$VALID_DAYS" -newkey rsa:2048 \
        -keyout "$CERT_KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=${DOMAIN}" \
        || die "openssl failed to generate the certificate."

    chmod 600 "$CERT_KEY_FILE" || die "Could not chmod $CERT_KEY_FILE"
    log "Wrote certificate: $CERT_FILE"
    log "Wrote private key: $CERT_KEY_FILE (mode 600)"
}

main() {
    parse_arguments "$@"
    validate_preconditions
    warn_if_chain_configured
    generate_selfsigned_pair

    echo
    warn "Self-signed certificate. Browsers will show a 'not private'"
    warn "warning. Fine for internal testing, not for public production."
    next_step "run ./04_install_certificate.sh"
}

main "$@"
