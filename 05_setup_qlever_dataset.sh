#!/usr/bin/env bash
# 05_setup_qlever_dataset.sh — fetch an example Qleverfile as a starting
# point, then pause for you to review/edit it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

export PATH="$HOME/.local/bin:$PATH"
command -v qlever >/dev/null 2>&1 || die "qlever CLI not found on PATH. Run ./01_install_qlever.sh first (and open a new shell if needed)."

mkdir -p "$QLEVER_WORKDIR"
cd "$QLEVER_WORKDIR" || die "Could not cd into $QLEVER_WORKDIR"

if [[ -f "Qleverfile" ]]; then
    log "Qleverfile already exists in $QLEVER_WORKDIR — leaving it as-is."
else
    log "Fetching example Qleverfile for dataset '$DATASET_NAME'..."
    qlever setup-config "$DATASET_NAME" || die "qlever setup-config failed. Run 'qlever setup-config --help' for valid dataset names, or set DATASET_NAME in config.sh."
fi

pause_for_manual_step "Open and review: ${QLEVER_WORKDIR}/Qleverfile
  - Set PORT (or SERVER_PORT, depending on version) to ${QLEVER_PORT} — must match what Apache proxies to.
  - Adjust MEMORY_FOR_QUERIES / CACHE_MAX_SIZE_GB for this machine (8 cores, 33G RAM).
  - If using your own data instead of the '${DATASET_NAME}' example, point RDF_FILES at it.
Suggested editor:  nano ${QLEVER_WORKDIR}/Qleverfile"

next_step "run ./06_index_and_start.sh"
