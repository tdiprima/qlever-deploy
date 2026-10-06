# qlever-deploy

Installs QLever, puts it behind Apache on 443, and opens the right ufw
ports — without disturbing anything you've already got configured.

Two modes, chosen by `SHARED_HOST` in `config.sh`:

* `"true"` — only ports 80 and 443 exist and publication-review already
  owns them for `DOMAIN`. QLever gets paths inside that site:
  `https://DOMAIN/sparql/` (engine) and `https://DOMAIN/qlever` (Web UI).
  The certificate is publication-review's; skip the `04_*` scripts.
* `"false"` — QLever is the only site and is served at `https://DOMAIN/`.

## Before you start

1. Edit **`config.sh`** — set `DOMAIN`, `CERT_EMAIL`, `SHARED_HOST`, and
   optionally `QLEVER_UI_SLUG` / `QLEVER_PORT` / `DATASET_NAME` /
   `QLEVER_WORKDIR`.
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
./04_request_certificate.sh              # Let's Encrypt        ┐ not on a
./04_generate_selfsigned_certificate.sh  # OR: self-signed      │ shared
./04_install_certificate.sh              # install either one   ┘ host
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

## Starting over

`./uninstall.sh` removes the QLever vhosts and `/etc/apache2/qlever-proxy.conf`
(add `--certs` for the installed certificate and key, `--dry-run` to
preview). QLever, its index and the firewall are left alone. Rerun the
numbered scripts from `02_setup_apache.sh` afterwards.

## Architecture

Shared host (`SHARED_HOST="true"`):

```
Internet ──443/tcp──> Apache, publication-review's vhost
                        /sparql/                      ──> 127.0.0.1:7000 QLever engine
                        /qlever, /default, /api/,
                        /admin/, /static/             ──> 127.0.0.1:8176 QLever Web UI
                        everything else               ──> publication-review
Internet ──80/tcp───> Apache (redirects to 443)
Internet ──7000/tcp─> blocked by ufw (not needed — Apache reaches it over localhost)
```

QLever alone (`SHARED_HOST="false"`):

```
Internet ──443/tcp──> Apache (TLS) ──proxy──> QLever engine and Web UI
Internet ──80/tcp───> Apache (serves ACME challenges, optional redirect to 443)
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

<!--
  sudo apt-get install -y unzip
  sudo usermod -aG docker $USER
  newgrp docker
  ./06_index_and_start.sh
-->

<br>
