#!/usr/bin/env bash
# 07_verify.sh — sanity-check the whole stack end to end.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

TEST_QUERY="SELECT%20*%20WHERE%20%7B%3Fs%20%3Fp%20%3Fo%7D%20LIMIT%201"

log "Checking QLever locally on 127.0.0.1:${QLEVER_PORT} ..."
CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${QLEVER_PORT}/sparql?query=${TEST_QUERY}" || true)"
if [[ "$CODE" == "200" ]]; then
    log "Local QLever endpoint OK (HTTP $CODE)."
else
    warn "Local QLever endpoint returned HTTP '$CODE'. Check: qlever status  /  qlever log"
fi

log "Checking Apache reverse proxy over HTTPS (https://${DOMAIN}/sparql/) ..."
CODE="$(curl -s -o /dev/null -w '%{http_code}' "https://${DOMAIN}/sparql/?query=${TEST_QUERY}" || true)"
if [[ "$CODE" == "200" ]]; then
    log "HTTPS endpoint OK (HTTP $CODE): https://${DOMAIN}/sparql/"
else
    warn "HTTPS endpoint check returned '$CODE'. Check:"
    warn "  sudo systemctl status apache2"
    warn "  sudo apache2ctl configtest"
    warn "  sudo journalctl -u apache2 --no-pager -n 50"
fi

if is_shared_host; then
    log "Checking the QLever Web UI (https://${DOMAIN}/${QLEVER_UI_SLUG}) ..."
    CODE="$(curl -s -o /dev/null -w '%{http_code}' "https://${DOMAIN}/${QLEVER_UI_SLUG}" || true)"
    if [[ "$CODE" == "200" ]]; then
        log "Web UI OK (HTTP $CODE). Open it at https://${DOMAIN}/qlever"
    else
        warn "Web UI returned '$CODE'. 503: start it with 'qlever ui'. 404: QLEVER_UI_SLUG in config.sh is not the UI's backend slug."
    fi
fi

echo
log "Current ufw ruleset:"
sudo ufw status verbose

echo
log "If both checks above show HTTP 200, your SPARQL endpoint is live at:"
log "  https://${DOMAIN}/sparql/"
