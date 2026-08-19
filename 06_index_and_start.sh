#!/usr/bin/env bash
# 06_index_and_start.sh — download data, build the QLever index, start the server.
# Indexing a large dataset can take a long time; this script does not
# background itself, so consider running it inside tmux/screen for big jobs.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

export PATH="$HOME/.local/bin:$PATH"
cd "$QLEVER_WORKDIR" || die "Could not cd into $QLEVER_WORKDIR. Run ./05_setup_qlever_dataset.sh first."

if [[ ! -f Qleverfile ]]; then
    die "No Qleverfile found in $QLEVER_WORKDIR. Run ./05_setup_qlever_dataset.sh first."
fi

log "Fetching dataset (qlever skips this automatically if already downloaded)..."
qlever get-data || warn "get-data reported an issue — it may already be complete. Check output above."

log "Building the index (qlever skips this if one already exists)..."
qlever index || die "Indexing failed. Check the log output above for details."

log "Starting the QLever server..."
qlever start || warn "qlever start reported an issue — it may already be running. Check with: qlever status"

next_step "run ./07_verify.sh"
