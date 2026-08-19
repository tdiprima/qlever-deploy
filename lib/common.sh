#!/usr/bin/env bash
# lib/common.sh — shared helpers sourced by every script in this project.
# Not meant to be run directly.

LOG_PREFIX="${LOG_PREFIX:-[qlever-deploy]}"

log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARNING: $*" >&2; }
err()  { echo "${LOG_PREFIX} ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# Pause and require the user to physically go do something outside these
# scripts (edit DNS, edit a config file, etc.) before continuing.
pause_for_manual_step() {
    echo
    echo "-------------------------------------------------------------------"
    echo "MANUAL STEP REQUIRED"
    echo "-------------------------------------------------------------------"
    echo "$1"
    echo "-------------------------------------------------------------------"
    read -rp "Press Enter once you've done this (Ctrl+C to stop here and come back later)... " _
}

# Print a clear "what to run next" banner at the end of a script.
next_step() {
    echo
    echo "====================================================================="
    echo "NEXT: $*"
    echo "====================================================================="
}
