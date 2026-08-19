#!/usr/bin/env bash
# 03_configure_ufw.sh — open 80/tcp and 443/tcp for Apache, inserting the
# rules ABOVE any existing DENY rules so they actually take effect.
# QLever's own port (7000 by default) is deliberately left closed — Apache
# reaches it over localhost, so it never needs to be exposed externally.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

command -v ufw >/dev/null 2>&1 || die "ufw not found. Install it with: sudo apt install ufw"

ufw_has_ipv4_allow_in() {
    local rule="$1"
    sudo ufw status numbered | grep -E "^\[[[:space:]]*[0-9]+\][[:space:]]+${rule}[[:space:]]+ALLOW IN" >/dev/null
}

# Insert an "allow <rule>" rule just above the first existing inbound DENY rule,
# so it isn't shadowed by broad deny rules further down the list. Safe to re-run:
# skips if a matching ALLOW IN rule already exists.
ufw_allow_before_denies() {
    local rule="$1"

    if ufw_has_ipv4_allow_in "$rule"; then
        log "ufw: 'allow $rule' already present, skipping."
        return
    fi

    local first_deny_num
    first_deny_num="$(sudo ufw status numbered | sed -nE 's/^\[[[:space:]]*([0-9]+)\].*DENY IN.*/\1/p' | head -n1)"

    if [[ -n "$first_deny_num" ]]; then
        log "Inserting 'allow $rule' at position $first_deny_num (above existing DENY rules)..."
        sudo ufw insert "$first_deny_num" allow "$rule" || die "ufw failed to insert allow rule for $rule."
    else
        log "No DENY rules found yet; appending 'allow $rule'."
        sudo ufw allow "$rule" || die "ufw failed to add allow rule for $rule."
    fi

    if ufw_has_ipv4_allow_in "$rule"; then
        log "ufw: confirmed '$rule ALLOW IN'."
    else
        die "ufw did not show '$rule ALLOW IN' after updating. Run 'sudo ufw status numbered' and check the output."
    fi
}

# if sudo ufw status | grep -qw "22/tcp.*ALLOW\|OpenSSH.*ALLOW"; then
#     log "SSH (22/tcp) already allowed — good, won't lock you out."
# else
#     warn "No rule allowing SSH (22/tcp) was found. Adding one now so you don't get locked out."
#     ufw_allow_before_denies "22/tcp"
# fi

ufw_allow_before_denies "80/tcp"
ufw_allow_before_denies "443/tcp"

log "NOTE: QLever's port (${QLEVER_PORT}/tcp) is intentionally NOT opened."
log "Apache reaches it over 127.0.0.1, and your existing DENY rules already"
log "block external access to it — nothing further to do there."

if sudo ufw status | grep -qi "Status: active"; then
    log "ufw already active."
else
    warn "ufw is not active yet."
    pause_for_manual_step "Review the ruleset below carefully before enabling ufw — a mistake here can lock you out of SSH.
Run 'sudo ufw status numbered' yourself and confirm 22/tcp is allowed, then run:
  sudo ufw enable"
fi

echo
log "Current ufw ruleset:"
sudo ufw status numbered

next_step "run ./04_request_certificate.sh"
