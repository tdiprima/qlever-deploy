#!/usr/bin/env bash
# uninstall.sh — undo what the numbered scripts did to Apache, so they can
# be rerun from a clean slate (for example after changing DOMAIN or
# SHARED_HOST in config.sh).
#
# Removes: the QLever vhosts (qlever.conf, qlever-ssl.conf and certbot's
#          qlever-le-ssl.conf), /etc/apache2/qlever-proxy.conf, and the
#          .bak-* copies the scripts left beside them. With --certs, also
#          the certificate and key 04_install_certificate.sh installed.
# Leaves:  packages, Apache modules, ufw rules, Let's Encrypt's own files,
#          QLever itself and QLEVER_WORKDIR (the index and its data).
#
# Safe to rerun — anything already gone is skipped.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

readonly VHOST_DIR="/etc/apache2/sites-available"
readonly SSL_VHOST_FILE="${VHOST_DIR}/qlever-ssl.conf"
readonly QLEVER_SITES=(qlever qlever-ssl qlever-le-ssl)

is_dry_run="false"
should_remove_certs="false"
is_confirmed="false"

usage() {
    cat <<'USAGE_EOF'
Usage: ./uninstall.sh [--dry-run] [--certs] [--yes] [--help]

  --dry-run   List what would be removed, change nothing.
  --certs     Also remove the certificate and private key installed by
              04_install_certificate.sh. Files another enabled Apache site
              still uses are kept.
  --yes       Do not ask for confirmation.
  --help      Show this message.

Removes the QLever Apache vhosts and /etc/apache2/qlever-proxy.conf, then
reloads Apache. QLever, its index and the firewall are not touched.
USAGE_EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) is_dry_run="true" ;;
            --certs) should_remove_certs="true" ;;
            --yes|-y) is_confirmed="true" ;;
            --help|-h) usage; exit 0 ;;
            *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# Echo every Apache file the numbered scripts wrote, backups included.
find_apache_files() {
    local site
    for site in "${QLEVER_SITES[@]}"; do
        sudo find "$VHOST_DIR" -maxdepth 1 -name "${site}.conf*" 2>/dev/null
    done
    sudo find /etc/apache2 -maxdepth 1 -name 'qlever-proxy.conf*' 2>/dev/null
}

# Echo the installed certificate and key, backups included. The paths are
# read from the live vhost as well as derived from DOMAIN, because DOMAIN
# may have been edited since the certificate was installed.
find_certificate_files() {
    local paths=("/etc/ssl/certs/${DOMAIN}-fullchain.crt" "/etc/ssl/private/${DOMAIN}.key")
    local configured

    if [[ -f "$SSL_VHOST_FILE" ]]; then
        while IFS= read -r configured; do
            paths+=("$configured")
        done < <(sed --quiet --regexp-extended \
            's/^[[:space:]]*SSLCertificate(Key)?File[[:space:]]+//p' "$SSL_VHOST_FILE")
    fi

    local path
    for path in "${paths[@]}"; do
        # certbot owns this tree; "certbot delete" is the way to remove it.
        [[ "$path" == /etc/letsencrypt/* ]] && continue
        sudo find "$(dirname "$path")" -maxdepth 1 -name "$(basename "$path")*" 2>/dev/null
    done | sort --unique
}

# True if an enabled site or conf still names this file. -R follows the
# sites-enabled symlinks; -r would skip them.
is_still_referenced() {
    sudo grep -R --quiet --fixed-strings -- "$1" \
        /etc/apache2/sites-enabled /etc/apache2/conf-enabled 2>/dev/null
}

confirm_or_exit() {
    [[ "$is_confirmed" == "true" ]] && return 0
    local answer
    read -rp "Remove the files listed above? Type 'yes' to continue: " answer
    [[ "$answer" == "yes" ]] || die "Nothing was removed."
}

disable_sites() {
    local site
    for site in "${QLEVER_SITES[@]}"; do
        if [[ -e "/etc/apache2/sites-enabled/${site}.conf" ]]; then
            log "Disabling site '${site}'..."
            sudo a2dissite "${site}.conf" >/dev/null || warn "Could not disable ${site}.conf"
        fi
    done
}

remove_files() {
    local target
    for target in "$@"; do
        sudo rm --force "$target" && log "Removed $target"
    done
}

remove_certificate_files() {
    local target
    for target in "$@"; do
        if is_still_referenced "$target"; then
            warn "Keeping $target — another enabled Apache site uses it."
        else
            sudo rm --force "$target" && log "Removed $target"
        fi
    done
}

reload_apache() {
    command -v apache2ctl >/dev/null 2>&1 || return 0

    if ! sudo apache2ctl configtest; then
        die "Apache config test failed after the removal. Apache was NOT reloaded
and is still serving its previous configuration. Check: sudo apache2ctl -S"
    fi
    sudo systemctl reload apache2 || warn "Apache reload failed. Check: systemctl status apache2"
}

main() {
    parse_arguments "$@"

    local apache_files=() certificate_files=()
    mapfile -t apache_files < <(find_apache_files)
    if [[ "$should_remove_certs" == "true" ]]; then
        mapfile -t certificate_files < <(find_certificate_files)
    fi

    if [[ "${#apache_files[@]}" -eq 0 && "${#certificate_files[@]}" -eq 0 ]]; then
        log "Nothing to remove — no QLever Apache configuration found."
        exit 0
    fi

    log "Will remove:"
    printf '  %s\n' ${apache_files[@]+"${apache_files[@]}"} ${certificate_files[@]+"${certificate_files[@]}"}

    if [[ "$is_dry_run" == "true" ]]; then
        log "DRY RUN: nothing was changed."
        exit 0
    fi

    confirm_or_exit
    disable_sites
    remove_files ${apache_files[@]+"${apache_files[@]}"}
    remove_certificate_files ${certificate_files[@]+"${certificate_files[@]}"}
    reload_apache

    log "QLever's Apache configuration is gone. QLever itself was not touched."
    next_step "check config.sh, then run ./02_setup_apache.sh"
}

main "$@"
