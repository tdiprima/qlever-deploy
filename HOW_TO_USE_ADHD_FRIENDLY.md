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
./02b_patch_apache_proxy.sh
./03_configure_ufw.sh
./04_request_certificate.sh
./04_install_certificate.sh
./05_setup_qlever_dataset.sh
./06_index_and_start.sh
./07_verify.sh
```

If a script says `MANUAL STEP REQUIRED`, stop and do that thing before continuing.

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

This step means:

> Make the domain name from `config.sh` point to this server's public IP address.

### What domain should you use?

Use the real domain or subdomain where you want QLever to live.

Examples:

```text
qlever.yourdomain.com
sparql.yourdomain.com
data.yourdomain.com
```

`sparql.example.com` is only an example. Do not literally use
`sparql.example.com` unless you own `example.com`, which you almost certainly do
not.

Whatever you choose here must also be the value in `config.sh`:

```bash
DOMAIN="qlever.yourdomain.com"
```

### What is your DNS provider?

Your DNS provider is the place where your domain's DNS records are managed.

It is often one of these:

- The company where you bought the domain, like Namecheap, GoDaddy, Squarespace,
  Cloudflare, Porkbun, Hover, or Google Domains/Squarespace Domains
- Your hosting provider
- Cloudflare, if you moved the domain's nameservers there
- Your company's IT/admin portal, if this is a company-owned domain

If you do not know where DNS is managed, check the domain's nameservers:

```bash
dig NS yourdomain.com
```

The result often hints at the provider.

Examples:

```text
cloudflare.com     -> DNS is probably in Cloudflare
domaincontrol.com  -> DNS is probably in GoDaddy
registrar-servers.com -> DNS is probably in Namecheap
```

### What record should you create?

In that DNS provider's dashboard, create an `A` record:

```text
Name: qlever
Type: A
Value: your server public IPv4 address
```

That makes this domain work:

```text
qlever.yourdomain.com
```

If you chose `sparql.yourdomain.com`, use this instead:

```text
Name: sparql
Type: A
Value: your server public IPv4 address
```

If your DNS dashboard wants the full name instead of just `qlever`, enter:

```text
qlever.yourdomain.com
```

If your server has IPv6 and you want to use it, also create an `AAAA` record
pointing to the server's public IPv6 address. If you are not sure, skip IPv6.

Check DNS from your own computer:

```bash
dig +short qlever.yourdomain.com
```

The result should be your server's public IP.

Wait until this works before continuing.

NOTE for X: this step is already done. `REDACTED`
is an existing A record pointing at 129.49.255.36. You do not need to create
anything, and you do not need a Help Desk ticket for DNS.

## Step 7: Install The HTTPS Certificate

Let's Encrypt does NOT work on the Stony Brook network. The campus
perimeter firewall blocks the `acme-protocol` application by User-Agent and
answers with a 503 "Application Blocked" page before the request ever
reaches Apache. You can see it yourself:

```bash
curl -A "Mozilla/5.0 (compatible; Let's Encrypt validation server; +https://www.letsencrypt.org)" \
  http://REDACTED/
```

That returns 503, while the same URL with any other User-Agent returns
normally. Nothing on the server can fix this.

So the certificate is issued out-of-band, the same way
`vulcan.bmi.stonybrook.edu` does it. Ask Eric who issues them.

Put the three files somewhere readable, then set their paths in
`config.sh`:

```bash
CERT_FILE=""
CERT_KEY_FILE=""
CERT_CHAIN_FILE="$HOME/certs/chain.crt"
```

Then run:

```bash
./04_install_certificate.sh
```

Before changing anything it checks that the key matches the certificate,
that the certificate actually covers your domain, and that it has not
expired. Any of those failing stops it with an explanation.

Once you are happy that HTTPS works, force all traffic to it:

```bash
./04_install_certificate.sh --redirect-http
```

Rerun this same script to install a renewed certificate later.

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
- [ ] `./02b_patch_apache_proxy.sh` finishes (REQUIRED before step 04)
- [ ] `./03_configure_ufw.sh` finishes
- [ ] SSH is allowed in ufw
- [ ] `./04_install_certificate.sh` finishes
- [ ] `./05_setup_qlever_dataset.sh` creates/reuses `Qleverfile`
- [ ] `./06_index_and_start.sh` finishes
- [ ] `./07_verify.sh` returns HTTP `200`

<br>
