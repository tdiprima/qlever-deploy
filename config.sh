#!/usr/bin/env bash
# config.sh - EDIT THIS FILE FIRST, before running any numbered script.
# Every script in this project sources this file.

# The public domain name pointing at this server (must have an A/AAAA
# record pointing at this machine's public IP before you run
# 04_request_certificate.sh).
DOMAIN="atoz.stonybrookmedicine.edu"

# Contact email for Let's Encrypt certificate expiry notices.
CERT_EMAIL="you@example.com"

# "true" when only ports 80 and 443 are available and another site already
# owns them for DOMAIN — on this host publication-review, through its
# deploy/apache-site.conf, which also holds the certificate. QLever then
# gets paths inside that site instead of vhosts of its own:
#   https://DOMAIN/sparql/   SPARQL engine
#   https://DOMAIN/qlever    Web UI (redirects to /QLEVER_UI_SLUG)
# Skip the 04_* certificate scripts in this mode. Set to "false" on a host
# where QLever is the only site; it is then served at https://DOMAIN/.
SHARED_HOST="true"

# Shared host only: the backend slug of the QLever Web UI, which is the
# path it is opened at. This is UI_CONFIG in the Qleverfile.
QLEVER_UI_SLUG="default"

# Port QLever listens on internally. Apache proxies to this over
# localhost; it never needs to be opened in ufw. Must match PORT in the
# Qleverfile and SPARQL_ENDPOINT in the applications' .env files.
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
