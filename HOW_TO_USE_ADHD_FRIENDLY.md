# How To Use This Project

This guide is the simple version.

Goal: install QLever on an Ubuntu server, put it behind Apache, add HTTPS, and verify the public SPARQL endpoint works.

## Before You Start

You need:

- [ ] An Ubuntu server
- [ ] SSH access to that server
- [ ] `sudo` access on that server
- [ ] A domain name you control
- [ ] DNS access for that domain
- [ ] This project copied onto the server

Do not rush the DNS step. HTTPS will fail if the domain does not point at the server.

## The Big Picture

You will run the scripts in number order:

```bash
./00_check_config.sh
./01_install_qlever.sh
./02_setup_apache.sh
./03_configure_ufw.sh
./04_request_certificate.sh
./05_setup_qlever_dataset.sh
./06_index_and_start.sh
./07_verify.sh
```

If a script says `MANUAL STEP REQUIRED`, stop and do that thing before continuing.

## Step 0: Make The Scripts Runnable

Run this once:

```bash
chmod +x *.sh
```

## Step 1: Edit The Config

Open `config.sh`:

```bash
nano config.sh
```

Change these two values:

```bash
DOMAIN="your.domain.com"
CERT_EMAIL="you@example.com"
```

Example:

```bash
DOMAIN="sparql.example.com"
CERT_EMAIL="admin@example.com"
```

Usually leave this alone:

```bash
QLEVER_PORT="7000"
```

For a test install, this is fine:

```bash
DATASET_NAME="olympics"
```

Save and exit:

- Press `Ctrl+O`
- Press `Enter`
- Press `Ctrl+X`

## Step 2: Check The Config

Run:

```bash
./00_check_config.sh
```

If it says the config looks OK, continue.

If it says your domain or email is still fake, go back to Step 1.

## Step 3: Install QLever And Dependencies

Run:

```bash
./01_install_qlever.sh
```

This installs things like Docker, pipx, curl, and the `qlever` command.

Important: if the script adds your user to the `docker` group, log out of SSH and log back in before Step 8.

## Step 4: Set Up Apache

Run:

```bash
./02_setup_apache.sh
```

This creates an Apache reverse proxy.

What that means:

- Public traffic goes to Apache.
- Apache forwards requests to QLever on `127.0.0.1:7000`.
- Port `7000` does not need to be public.

## Step 5: Configure The Firewall

Run:

```bash
./03_configure_ufw.sh
```

This opens:

- `22/tcp` for SSH
- `80/tcp` for HTTP
- `443/tcp` for HTTPS

It does not open QLever's internal port.

If the script pauses before enabling ufw, read the rules carefully:

```bash
sudo ufw status numbered
```

Make sure SSH is allowed before enabling ufw.

Then run:

```bash
sudo ufw enable
```

## Step 6: Point DNS At The Server

In your DNS provider, create an `A` record:

```text
sparql.example.com -> your server public IPv4 address
```

If you use IPv6 too, create an `AAAA` record.

Check DNS from your own computer:

```bash
dig +short sparql.example.com
```

The result should be your server's public IP.

Wait until this works before continuing.

## Step 7: Request HTTPS Certificate

Run:

```bash
./04_request_certificate.sh
```

This asks Let's Encrypt for a certificate.

If this fails, the usual causes are:

- DNS does not point to this server yet.
- Port `80` is blocked.
- Apache is not running.
- The domain was typed wrong in `config.sh`.

Fix the issue, then rerun:

```bash
./04_request_certificate.sh
```

## Step 8: Create The QLever Dataset Config

Run:

```bash
./05_setup_qlever_dataset.sh
```

This creates a `Qleverfile` in:

```bash
~/qlever-data
```

The script will pause and ask you to review it.

Open it:

```bash
nano ~/qlever-data/Qleverfile
```

Check:

- The QLever port matches `7000`
- Memory settings look reasonable
- Dataset files are correct if you are using your own data

For the example install, the default `olympics` dataset is fine.

## Step 9: Build The Index And Start QLever

Run:

```bash
./06_index_and_start.sh
```

This can take a while.

For a big dataset, use `tmux` or `screen` so the job keeps running if your SSH session drops.

Simple `tmux` version:

```bash
tmux
./06_index_and_start.sh
```

To detach from tmux:

- Press `Ctrl+B`
- Press `D`

To come back later:

```bash
tmux attach
```

## Step 10: Verify Everything

Run:

```bash
./07_verify.sh
```

Success looks like:

- Local QLever check returns HTTP `200`
- HTTPS endpoint check returns HTTP `200`

Your final endpoint will be:

```text
https://YOUR_DOMAIN/api/sparql
```

Example:

```text
https://sparql.example.com/api/sparql
```

## If Something Breaks

First, rerun the script that failed.

Then check the likely problem area:

### Apache

```bash
sudo apache2ctl configtest
sudo systemctl status apache2
sudo journalctl -u apache2 --no-pager -n 50
```

### Firewall

```bash
sudo ufw status numbered
```

### QLever

```bash
cd ~/qlever-data
qlever status
qlever log
```

### DNS

```bash
dig +short YOUR_DOMAIN
```

## Safe Reruns

The scripts are meant to be rerun.

If a step fails:

1. Fix the problem.
2. Rerun the same script.
3. Continue from there.

You do not need to start from the beginning every time.

## Quick Checklist

- [ ] `config.sh` has real `DOMAIN`
- [ ] `config.sh` has real `CERT_EMAIL`
- [ ] DNS points to the server
- [ ] `./00_check_config.sh` passes
- [ ] `./01_install_qlever.sh` finishes
- [ ] Log out and back in if Docker group changed
- [ ] `./02_setup_apache.sh` finishes
- [ ] `./03_configure_ufw.sh` finishes
- [ ] SSH is allowed in ufw
- [ ] `./04_request_certificate.sh` finishes
- [ ] `./05_setup_qlever_dataset.sh` creates/reuses `Qleverfile`
- [ ] `./06_index_and_start.sh` finishes
- [ ] `./07_verify.sh` returns HTTP `200`

