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
3. `chmod +x *.sh` (once).

## Run order

Run each script, read its output, then run whatever it tells you to run
next. Several scripts pause and ask you to do something by hand — read the
`MANUAL STEP REQUIRED` block, do it, then press Enter to continue.

| # | Script | What it does | Manual step? |
|---|--------|---------------|---------------|
| 0 | `00_check_config.sh` | Validates `config.sh`, checks OS/arch/sudo | No |
| 1 | `01_install_qlever.sh` | Installs docker, pipx, the `qlever` CLI | **Yes** — if you were just added to the `docker` group, log out and back in before step 6 |
| 2 | `02_setup_apache.sh` | Installs Apache, enables proxy modules, writes a vhost proxying to `127.0.0.1:$QLEVER_PORT` | No |
| 3 | `03_configure_ufw.sh` | Opens 80/tcp and 443/tcp, inserted **above** your existing DENY rules; leaves `$QLEVER_PORT` closed externally | **Yes** — if ufw isn't active yet, you're asked to review the ruleset and run `sudo ufw enable` yourself |
| 4 | `04_request_certificate.sh` | Installs certbot, requests a Let's Encrypt cert, upgrades the Apache vhost to HTTPS on 443 | **Yes** — confirm DNS is actually pointing at this server first |
| 5 | `05_setup_qlever_dataset.sh` | Fetches an example `Qleverfile` into `$QLEVER_WORKDIR` | **Yes** — review/edit the `Qleverfile` (port, memory limits, your own data) |
| 6 | `06_index_and_start.sh` | Downloads data, builds the index, starts QLever | No (but indexing can take a while — consider running inside `tmux`/`screen` for large datasets) |
| 7 | `07_verify.sh` | Curls the local port and the public HTTPS endpoint, prints ufw status | No |

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

These scripts make system-level changes: installing packages, editing Apache
configuration, changing ufw firewall rules, requesting TLS certificates, and
starting Docker/QLever services.

Read each script before running it. Use this at your own risk. The author is not
responsible for downtime, lockouts, data loss, misconfiguration, security issues,
or other problems caused by running these scripts.
