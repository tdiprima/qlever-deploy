#!/usr/bin/env bash
# config.sh — EDIT THIS FILE FIRST, before running any numbered script.
# Every script in this project sources this file.

# The public domain name pointing at this server (must have an A/AAAA
# record pointing at this machine's public IP before you run
# 04_request_certificate.sh).
DOMAIN="your.domain.com"

# Contact email for Let's Encrypt certificate expiry notices.
CERT_EMAIL="you@example.com"

# Port QLever listens on internally. Apache proxies to this over
# localhost; it never needs to be opened in ufw.
QLEVER_PORT="7000"

# Port the QLever Web UI listens on. The Web UI is a SEPARATE service from
# the SPARQL engine above (start it with: qlever ui). Apache proxies "/"
# here and "/sparql/" to QLEVER_PORT; neither needs opening in ufw.
QLEVER_UI_PORT="8176"

# Name of an example Qleverfile to start from. See:
#   qlever setup-config --help
# for the full list (e.g. "wikidata", "dblp", "olympics"). Swap this out
# once you're ready to point QLever at your own dataset instead.
DATASET_NAME="olympics"

# --- TLS certificate (institutionally issued) ---------------------------
# Let's Encrypt HTTP-01 validation CANNOT work on this network: Stony
# Brook's perimeter firewall blocks the "acme-protocol" application by
# User-Agent, returning an "Application Blocked" 503 before traffic ever
# reaches Apache. The certificate is therefore issued out-of-band (the
# same way vulcan.bmi.stonybrook.edu does it) and installed by
# ./04_install_certificate.sh.
#
# Point these at the files the issuer gave you. NEVER commit the private
# key to this repo.
#
# No institutional cert yet? Run ./04_generate_selfsigned_certificate.sh
# first — it writes a self-signed pair to these same paths. Leave
# CERT_CHAIN_FILE empty in that case; a self-signed cert has no chain.
CERT_FILE=""
CERT_KEY_FILE=""

# Intermediate/chain bundle from the issuer. Leave empty only if the
# issuer supplied none (rare; browsers will show chain errors without it).
CERT_CHAIN_FILE=""

# Directory where QLever's working files (Qleverfile, downloaded data,
# on-disk index) will live.
QLEVER_WORKDIR="$HOME/qlever-data"
