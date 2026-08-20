# qlever-deploy

Installs QLever, puts it behind Apache with a Let's Encrypt certificate on
443, and opens the right ufw ports — without disturbing anything you've
already got configured.

## Before you start

1. Edit **`config.sh`** — set `DOMAIN`, `CERT_EMAIL`, and optionally
   `QLEVER_PORT` / `DATASET_NAME` / `QLEVER_WORKDIR`.
2. Make sure a DNS A (or AAAA) record for `DOMAIN` points at this
   server's public IP. It doesn't have to be live yet for the first few
   scripts, but it must be live before step 4.

## Run order
You will run the scripts in number order:

```bash
./00_check_config.sh
./01_install_qlever.sh
./02_setup_apache.sh
./02b_patch_apache_proxy.sh
./03_configure_ufw.sh
./04_request_certificate.sh              # Let's Encrypt
./04_generate_selfsigned_certificate.sh  # OR: self-signed, for testing only
./04_install_certificate.sh
./05_setup_qlever_dataset.sh
./06_index_and_start.sh
./07_verify.sh
```

If a script says `MANUAL STEP REQUIRED`, stop and do that thing before continuing.

## Re-running

Every script is written to be safe to re-run: it checks what's already
installed/configured/running and skips or updates rather than failing.
If something goes wrong partway through, fix the issue and just re-run
that same script — you don't need to start over.

## Architecture

```
Internet ──443/tcp──> Apache (TLS via certbot) ──proxy──> 127.0.0.1:7000 QLever
Internet ──80/tcp───> Apache (redirects to 443, serves ACME challenges)
Internet ──7000/tcp─> blocked by ufw (not needed — Apache reaches it over localhost)
```

## Warning ⚠️

These scripts do real server things: they install packages, edit Apache
configuration, change ufw firewall rules, request TLS certificates, and start
Docker/QLever services.

They are meant to be careful and re-runnable, but they are not magical. Please
read each script before running it, especially anything involving DNS, firewall
rules, or certificates.

Use this at your own risk. If your server locks you out, your DNS points to the
wrong place, or Apache decides today is character-building day, that is between
you, your backups, and the logs. The author is not responsible for downtime,
lockouts, data loss, misconfiguration, security issues, or other problems caused
by running these scripts.

<br>
