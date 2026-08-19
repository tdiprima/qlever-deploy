#!/usr/bin/env bash
# 02b_patch_apache_proxy.sh — upgrade the Apache reverse proxy written by
# 02_setup_apache.sh so that it also handles QLever's WebSocket progress
# channel and the separate QLever Web UI.
#
# Expects: 02_setup_apache.sh has already run. Safe to run before or after
#          04_request_certificate.sh, and safe to rerun.
# Produces: /etc/apache2/qlever-proxy.conf, Include-d from every QLever
#          vhost found (port 80 and, if certbot has run, port 443).
#
# Every file it touches is backed up first; if Apache's config test fails,
# all backups are restored automatically and Apache is left as it was.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

readonly TEMPLATE_FILE="$SCRIPT_DIR/apache/qlever-proxy.conf.template"
readonly INCLUDE_FILE="/etc/apache2/qlever-proxy.conf"
readonly VHOST_DIR="/etc/apache2/sites-available"
readonly REQUIRED_MODULES=(proxy proxy_http proxy_wstunnel headers rewrite)
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_SUFFIX

# Port the QLever Web UI listens on. 8176 is the qlever CLI default.
QLEVER_UI_PORT="${QLEVER_UI_PORT:-8176}"

is_dry_run="false"
backed_up_files=()

usage() {
    cat <<'USAGE_EOF'
Usage: ./02b_patch_apache_proxy.sh [--dry-run] [--help]

  --dry-run   Show what would change, write nothing, reload nothing.
  --help      Show this message.

Adds to the Apache vhost(s) created by 02_setup_apache.sh:
  - mod_proxy_wstunnel + the Upgrade rule QLever's progress socket needs
  - /sparql/  -> the SPARQL engine
  - /         -> the QLever Web UI
  - an ACME carve-out so certbot renewal keeps working
USAGE_EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) is_dry_run="true" ;;
            --help|-h) usage; exit 0 ;;
            *) err "Unknown argument: $1"; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# Fail early if the things we are about to edit are not there.
validate_preconditions() {
    command -v apache2ctl >/dev/null 2>&1 \
        || die "apache2ctl not found. Run ./02_setup_apache.sh first."

    [[ -f "$TEMPLATE_FILE" ]] \
        || die "Missing template: $TEMPLATE_FILE"

    [[ "$QLEVER_PORT" =~ ^[0-9]+$ ]] \
        || die "QLEVER_PORT in config.sh is not a number: '$QLEVER_PORT'"

    [[ "$QLEVER_UI_PORT" =~ ^[0-9]+$ ]] \
        || die "QLEVER_UI_PORT is not a number: '$QLEVER_UI_PORT'"

    [[ "$QLEVER_PORT" != "$QLEVER_UI_PORT" ]] \
        || die "QLEVER_PORT and QLEVER_UI_PORT are both '$QLEVER_PORT'. They must differ."
}

# Echo every QLever vhost file that exists. certbot names its copy
# <name>-le-ssl.conf, so after step 04 there are two.
find_qlever_vhosts() {
    local candidate
    for candidate in "$VHOST_DIR/qlever.conf" "$VHOST_DIR/qlever-le-ssl.conf"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
        fi
    done
}

enable_required_modules() {
    local module
    for module in "${REQUIRED_MODULES[@]}"; do
        if sudo apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
            log "Module '$module' already enabled."
        elif [[ "$is_dry_run" == "true" ]]; then
            log "DRY RUN: would enable module '$module'."
        else
            log "Enabling module '$module'..."
            sudo a2enmod "$module" >/dev/null || die "Failed to enable module '$module'."
        fi
    done
}

# Substitute the ports from config.sh into the template.
render_include_file() {
    local rendered
    rendered="$(sed \
        -e "s/__QLEVER_PORT__/${QLEVER_PORT}/g" \
        -e "s/__QLEVER_UI_PORT__/${QLEVER_UI_PORT}/g" \
        "$TEMPLATE_FILE")" || die "Failed to render template."

    if [[ "$is_dry_run" == "true" ]]; then
        log "DRY RUN: would write $INCLUDE_FILE (engine=${QLEVER_PORT}, ui=${QLEVER_UI_PORT})."
        return 0
    fi

    back_up_file "$INCLUDE_FILE"
    printf '%s\n' "$rendered" | sudo tee "$INCLUDE_FILE" >/dev/null \
        || die "Could not write $INCLUDE_FILE"
    log "Wrote $INCLUDE_FILE (engine=${QLEVER_PORT}, ui=${QLEVER_UI_PORT})."
}

# Copy a file aside so restore_backups can undo a bad edit.
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
            && warn "Restored $target from backup."
    done
}

# Neutralise the inline proxy directives 02_setup_apache.sh wrote, so they
# cannot compete with the include. Commented rather than deleted so the
# original intent stays visible in the file.
comment_out_inline_proxy_directives() {
    local vhost="$1"
    sudo sed --in-place --regexp-extended \
        's|^([[:space:]]*)(ProxyPreserveHost|ProxyPass|ProxyPassReverse)([[:space:]])|\1# superseded by qlever-proxy.conf: \2\3|' \
        "$vhost" || die "Failed to comment out inline directives in $vhost"
}

# Insert the Include line just before the closing </VirtualHost>.
insert_include_directive() {
    local vhost="$1"
    sudo sed --in-place \
        "s|^\([[:space:]]*\)</VirtualHost>|\1    Include ${INCLUDE_FILE}\n\1</VirtualHost>|" \
        "$vhost" || die "Failed to insert Include into $vhost"
}

patch_vhost() {
    local vhost="$1"

    if grep --quiet --fixed-strings "Include ${INCLUDE_FILE}" "$vhost"; then
        log "$(basename "$vhost") already includes qlever-proxy.conf — skipping."
        return 0
    fi

    if [[ "$is_dry_run" == "true" ]]; then
        log "DRY RUN: would patch $(basename "$vhost")."
        return 0
    fi

    log "Patching $(basename "$vhost")..."
    back_up_file "$vhost"
    comment_out_inline_proxy_directives "$vhost"
    insert_include_directive "$vhost"
}

verify_and_reload() {
    if [[ "$is_dry_run" == "true" ]]; then
        log "DRY RUN: would run 'apache2ctl configtest' and reload Apache."
        return 0
    fi

    log "Testing Apache configuration..."
    if ! sudo apache2ctl configtest; then
        err "Apache config test FAILED. Rolling back every change."
        restore_backups
        sudo apache2ctl configtest \
            || err "Rollback did not restore a valid config. Inspect ${VHOST_DIR} by hand."
        die "No changes were kept. Apache was not reloaded."
    fi

    log "Config test passed. Reloading Apache..."
    sudo systemctl reload apache2 || die "Apache reload failed. Check: systemctl status apache2"
}

report_next_actions() {
    echo
    log "Reverse proxy is now:"
    log "  https://${DOMAIN}/sparql/   -> SPARQL engine on 127.0.0.1:${QLEVER_PORT}"
    log "  https://${DOMAIN}/          -> Web UI on 127.0.0.1:${QLEVER_UI_PORT}"
    echo
    warn "A 503 at / is expected until you start the Web UI:  qlever ui"
    warn "A 503 at /sparql/ is expected until QLever is running: ./06_index_and_start.sh"
    echo
    log "Once QLever is up, confirm the engine path with:"
    log "  curl -s -o /dev/null -w '%{http_code}\\n' 'https://${DOMAIN}/sparql/?query=SELECT%20*%20WHERE%20%7B%3Fs%20%3Fp%20%3Fo%7D%20LIMIT%201'"
}

main() {
    parse_arguments "$@"
    validate_preconditions

    local vhosts
    mapfile -t vhosts < <(find_qlever_vhosts)
    [[ "${#vhosts[@]}" -gt 0 ]] \
        || die "No QLever vhost found in $VHOST_DIR. Run ./02_setup_apache.sh first."

    log "Found ${#vhosts[@]} QLever vhost(s) to patch."
    enable_required_modules
    render_include_file

    local vhost
    for vhost in "${vhosts[@]}"; do
        patch_vhost "$vhost"
    done

    verify_and_reload
    report_next_actions
}

main "$@"
