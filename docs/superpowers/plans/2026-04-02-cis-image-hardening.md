# CIS Image Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the app-apache-php base image against CIS Docker Benchmark Section 4 (Container Images) controls, taking advantage of Fargate's host-level coverage to focus purely on image hygiene.

**Architecture:** Pre-install all optional packages (ssmtp, postfix) at build time so entrypoints are configuration-only. Remove unnecessary tools (sudo, vim). Add HEALTHCHECK and strip SUID/SGID bits.

**Deferred:** Port 8080 + gosu privilege drop — requires coordinated changes across 6 downstream consumers (app-drupal, app-wordpress, app-laravel, app-symfony, app-statamic, app-craft-cms). Tracked separately.

**Tech Stack:** Docker, Debian (trixie), Apache 2.4, PHP 8.4, gosu, postfix, ssmtp

---

### Task 1: Pre-install ssmtp and postfix in Dockerfile

**Files:**
- Modify: `Dockerfile:6-107` (main RUN block)

Currently ssmtp and postfix are installed at runtime in entrypoint scripts. Move them into the build-time package list so every image ships with them pre-installed.

- [ ] **Step 1: Add ssmtp, postfix, and libsasl2-modules to the apt-get install block**

In `Dockerfile`, add to the `apt-get install -y --no-install-recommends` list (after `openssl`):

```dockerfile
        postfix \
        libsasl2-modules \
        ssmtp \
```

Also remove `sudo` and `vim` from this same list (lines 28-29). Remove `git` as well — Composer can fetch packages as zip archives from Packagist without git. Downstream images that need git for VCS-based Composer dependencies can install it themselves.

The full package list becomes:

```dockerfile
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        default-mysql-client \
        gettext \
        ghostscript \
        gosu \
        libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libmagickwand-dev \
        libpng-dev \
        libpq-dev \
        libsasl2-modules \
        libwebp-dev \
        libzip-dev \
        openssl \
        postfix \
        ssmtp \
        unzip \
```

Note: postfix will prompt during install. We need to preconfigure it. Add this before the `apt-get install` block:

```dockerfile
RUN set -ex; \
    # Preconfigure postfix to avoid interactive prompts during install
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections && \
    echo "postfix postfix/mailname string localhost" | debconf-set-selections && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
```

Actually, since this is all one RUN block, add the debconf lines right after `apt-get update`:

```dockerfile
RUN set -ex; \
    apt-get update && \
    # Preconfigure postfix to avoid interactive prompts
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections && \
    echo "postfix postfix/mailname string localhost" | debconf-set-selections && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
```

- [ ] **Step 2: Build the image to verify packages install correctly**

```bash
cd /Users/stuart/apps/quant-templates/app-apache-php
docker build -t test-apache-php:hardening .
```

Expected: Build succeeds. Verify packages are present:

```bash
docker run --rm test-apache-php:hardening which ssmtp
docker run --rm test-apache-php:hardening which postconf
docker run --rm test-apache-php:hardening which sudo && echo "FAIL: sudo still present" || echo "PASS: sudo removed"
docker run --rm test-apache-php:hardening which vim && echo "FAIL: vim still present" || echo "PASS: vim removed"
docker run --rm test-apache-php:hardening which git && echo "FAIL: git still present" || echo "PASS: git removed"
```

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "build: pre-install ssmtp/postfix, remove sudo/vim/git

Move ssmtp, postfix, and libsasl2-modules from runtime entrypoint
installation to build-time. Remove sudo, vim, and git from the
image to reduce attack surface. Downstream images that need git
for VCS-based Composer dependencies can install it themselves."
```

---

### Task 2: Simplify entrypoint scripts to configuration-only

**Files:**
- Modify: `quant/entrypoints/00-ssmtp.sh`
- Modify: `quant/entrypoints/00-smtp-relay.sh`

Remove all `apt-get install` blocks from entrypoints. They should only configure packages that are already installed.

- [ ] **Step 1: Rewrite 00-ssmtp.sh**

Replace the entire file with:

```bash
#!/bin/bash

# Configure ssmtp (lightweight sendmail replacement) if SMTP relay is NOT enabled
if [ -n "$QUANT_SMTP_HOST" ] && [ "$QUANT_SMTP_RELAY_ENABLED" != "true" ]; then
    echo "Configuring ssmtp with host: $QUANT_SMTP_HOST"

    # Ensure config directory exists with correct permissions
    mkdir -p /etc/ssmtp
    chmod 755 /etc/ssmtp

    # Configure ssmtp
    cat <<EOL > /etc/ssmtp/ssmtp.conf
root=$QUANT_SMTP_FROM
mailhub=$QUANT_SMTP_HOST:$QUANT_SMTP_PORT
AuthUser=$QUANT_SMTP_USERNAME
AuthPass=$QUANT_SMTP_PASSWORD
UseTLS=YES
AuthMethod=LOGIN
FromLineOverride=YES
EOL

    echo "ssmtp configured - PHP mail() will work"
fi
```

- [ ] **Step 2: Rewrite 00-smtp-relay.sh**

Replace the entire file with:

```bash
#!/bin/bash

# Configure Postfix SMTP relay if explicitly enabled
if [ -n "$QUANT_SMTP_HOST" ] && [ "$QUANT_SMTP_RELAY_ENABLED" = "true" ]; then
    echo "Configuring Postfix SMTP relay with host: $QUANT_SMTP_HOST"

    # Configure domain from QUANT_SMTP_FROM_DOMAIN or extract from QUANT_SMTP_FROM
    if [ -n "$QUANT_SMTP_FROM_DOMAIN" ]; then
        DOMAIN="$QUANT_SMTP_FROM_DOMAIN"
    elif [ -n "$QUANT_SMTP_FROM" ]; then
        DOMAIN=$(echo "$QUANT_SMTP_FROM" | cut -d@ -f2)
    else
        DOMAIN="quantcdn.io"
    fi

    POSTFIX_HOSTNAME="${QUANT_SMTP_HOSTNAME:-apache-php.$DOMAIN}"

    # Ensure Postfix queue directories exist with correct ownership
    mkdir -p /var/spool/postfix/{maildrop,public,pid}
    chown -R postfix:postdrop /var/spool/postfix/maildrop
    chown -R postfix:postdrop /var/spool/postfix/public
    chown -R root:root /var/spool/postfix/pid
    chmod 730 /var/spool/postfix/maildrop
    chmod 710 /var/spool/postfix/public
    chmod 755 /var/spool/postfix/pid

    # Ensure postdrop has correct setgid permissions
    chgrp postdrop /usr/sbin/postdrop
    chmod 2755 /usr/sbin/postdrop

    postconf -e "myhostname=$POSTFIX_HOSTNAME"
    postconf -e "mydomain=$DOMAIN"
    postconf -e "myorigin=\$mydomain"
    postconf -e "inet_interfaces=127.0.0.1"
    postconf -e "inet_protocols=ipv4"
    postconf -e "mydestination="
    postconf -e "local_transport=error:local delivery disabled"
    postconf -e "relayhost=[$QUANT_SMTP_HOST]:$QUANT_SMTP_PORT"

    # Configure TLS
    postconf -e "smtp_tls_security_level=secure"
    postconf -e "smtp_tls_note_starttls_offer=yes"

    postconf -e "smtp_sasl_auth_enable=yes"
    postconf -e "smtp_sasl_security_options=noanonymous"
    postconf -e "smtp_sasl_password_maps=hash:/etc/postfix/sasl_passwd"
    postconf -e "smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt"

    # Create SASL password file
    echo "[$QUANT_SMTP_HOST]:$QUANT_SMTP_PORT $QUANT_SMTP_USERNAME:$QUANT_SMTP_PASSWORD" > /etc/postfix/sasl_passwd
    chmod 600 /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd

    # Copy DNS files to Postfix chroot
    mkdir -p /var/spool/postfix/etc
    cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf 2>/dev/null || true
    cp /etc/hosts /var/spool/postfix/etc/hosts 2>/dev/null || true

    # Start Postfix
    echo "Starting Postfix..."
    postfix start || postfix reload

    sleep 2

    if postfix status >/dev/null 2>&1; then
        echo "Postfix SMTP relay configured and started"
        echo "  Relay host: $QUANT_SMTP_HOST:$QUANT_SMTP_PORT"
        echo "  From domain: $DOMAIN"
    else
        echo "Warning: Postfix may not have started correctly"
    fi
fi
```

- [ ] **Step 3: Build and test SMTP entrypoints**

```bash
docker build -t test-apache-php:hardening .

# Test ssmtp config (no SMTP relay)
docker run --rm \
  -e QUANT_SMTP_HOST=smtp.example.com \
  -e QUANT_SMTP_PORT=587 \
  -e QUANT_SMTP_FROM=test@example.com \
  -e QUANT_SMTP_USERNAME=user \
  -e QUANT_SMTP_PASSWORD=pass \
  --entrypoint docker-entrypoint.sh \
  test-apache-php:hardening \
  bash -c "cat /etc/ssmtp/ssmtp.conf"
```

Expected: ssmtp.conf is generated with correct values, no `apt-get install` output.

```bash
# Test postfix config (relay enabled)
docker run --rm \
  -e QUANT_SMTP_HOST=smtp.example.com \
  -e QUANT_SMTP_PORT=587 \
  -e QUANT_SMTP_FROM=test@example.com \
  -e QUANT_SMTP_USERNAME=user \
  -e QUANT_SMTP_PASSWORD=pass \
  -e QUANT_SMTP_RELAY_ENABLED=true \
  --entrypoint docker-entrypoint.sh \
  test-apache-php:hardening \
  bash -c "postconf relayhost"
```

Expected: Shows `relayhost = [smtp.example.com]:587`, no `apt-get install` output.

- [ ] **Step 4: Commit**

```bash
git add quant/entrypoints/00-ssmtp.sh quant/entrypoints/00-smtp-relay.sh
git commit -m "refactor: simplify SMTP entrypoints to configuration-only

Remove apt-get install from entrypoint scripts. ssmtp and postfix
are now pre-installed at build time. Entrypoints only write config
files and start services."
```

---

### Task 3: Add HEALTHCHECK to Dockerfile

**Files:**
- Modify: `Dockerfile` (add HEALTHCHECK instruction before ENTRYPOINT)

- [ ] **Step 1: Add HEALTHCHECK instruction**

Add before the `EXPOSE` line in `Dockerfile`:

```dockerfile
# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost:80/ || exit 1
```

Note: We use `curl` which is already installed. The `-fsS` flags: fail silently on HTTP errors, show errors on curl failures, suppress progress.

- [ ] **Step 2: Build and verify healthcheck**

```bash
docker build -t test-apache-php:hardening .
docker run -d --name healthcheck-test test-apache-php:hardening
sleep 5
docker inspect --format='{{.State.Health.Status}}' healthcheck-test
```

Expected: `healthy` (after start period)

```bash
docker stop healthcheck-test && docker rm healthcheck-test
```

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "build: add HEALTHCHECK instruction for container health monitoring"
```

---

### Task 4: Switch Apache to port 8080 and drop privileges with gosu

**Files:**
- Modify: `Dockerfile` (EXPOSE, Apache port config, gosu setup)
- Modify: `quant/docker-entrypoint.sh` (privilege drop)
- Modify: `docker-compose.yml` (port mapping)
- Modify: `docker-compose.override.yml.example` (port mapping documentation)

This is the highest-impact CIS change. The entrypoint runs as root for configuration, then drops to www-data via gosu before exec'ing Apache on port 8080.

- [ ] **Step 1: Configure Apache to listen on 8080 in Dockerfile**

Add after the existing `a2enconf remoteip` block (around line 80 area), within the same RUN layer or in the UID/GID remapping RUN layer:

Add a new RUN instruction after the UID/GID remap block:

```dockerfile
# Switch Apache to port 8080 (allows running as non-root)
RUN sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf && \
    sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf && \
    # Ensure www-data can write to required directories
    chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 2>/dev/null || true && \
    mkdir -p /var/lock/apache2 && chown www-data:www-data /var/lock/apache2
```

- [ ] **Step 2: Update EXPOSE and HEALTHCHECK**

Change the EXPOSE directive:

```dockerfile
EXPOSE 8080
```

Update the HEALTHCHECK (from Task 3):

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost:8080/ || exit 1
```

- [ ] **Step 3: Update docker-entrypoint.sh to drop privileges with gosu**

Replace the entire file:

```bash
#!/bin/bash
# Custom entrypoint for Apache+PHP that runs initialization scripts
# Entrypoint runs as root for configuration, then drops to www-data via gosu

set -e

# Run custom entrypoint scripts if they exist (as root, for config tasks)
if [ -d "/quant-entrypoint.d" ]; then
    for script in /quant-entrypoint.d/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            echo "Running $(basename "$script")..."
            "$script"
        fi
    done
fi

# Drop privileges and pass control to docker-php-entrypoint as www-data
exec gosu www-data docker-php-entrypoint "$@"
```

- [ ] **Step 4: Update docker-compose.yml port mapping**

Change port mapping in `docker-compose.yml`:

```yaml
    ports:
      - "80:8080"
```

Update the healthcheck test URL:

```yaml
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/ || exit 1"]
```

- [ ] **Step 5: Update docker-compose.override.yml.example**

No port changes needed in the override file (it doesn't define ports). No changes required.

- [ ] **Step 6: Build and test non-root operation**

```bash
docker build -t test-apache-php:hardening .

# Verify Apache listens on 8080
docker run -d --name port-test -p 8888:8080 test-apache-php:hardening
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/
```

Expected: `200`

```bash
# Verify Apache workers run as www-data, not root
docker exec port-test ps aux | grep apache
```

Expected: Apache processes running as `www-data` (master included, thanks to gosu).

```bash
# Verify no root process for apache
docker exec port-test sh -c 'ps -eo user,comm | grep apache | grep -v www-data' && echo "FAIL: root apache process found" || echo "PASS: no root apache processes"

docker stop port-test && docker rm port-test
```

- [ ] **Step 7: Commit**

```bash
git add Dockerfile quant/docker-entrypoint.sh docker-compose.yml
git commit -m "security: switch to port 8080 and drop privileges via gosu

Apache now listens on 8080 instead of 80, allowing the main process
to run as www-data instead of root. Entrypoint scripts still run as
root for configuration, then gosu drops to www-data before exec'ing
Apache. Fargate task definitions map external ports independently."
```

---

### Task 5: Strip SUID/SGID bits

**Files:**
- Modify: `Dockerfile` (add SUID/SGID cleanup near end of build)

- [ ] **Step 1: Add SUID/SGID strip after all package installs**

Add a RUN instruction after the Composer COPY and before the entrypoint COPY lines:

```dockerfile
# Strip SUID/SGID bits from all binaries (CIS 4.8)
# Exception: gosu needs SUID to drop privileges in entrypoint
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true && \
    chmod u+s /usr/sbin/gosu 2>/dev/null || true
```

Wait — gosu actually uses `setuid` bit on some installs, but the Docker-official gosu binary typically doesn't need SUID because it's called as root. Let's verify by just stripping everything:

```dockerfile
# Strip SUID/SGID bits from all binaries (CIS 4.8)
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true
```

However, `postdrop` needs SGID for postfix queue access. Since postfix is configured at runtime in the entrypoint (which runs as root), the entrypoint already sets `chmod 2755 /usr/sbin/postdrop`. So stripping at build time and re-setting at runtime is fine.

- [ ] **Step 2: Build and verify**

```bash
docker build -t test-apache-php:hardening .

# Check for remaining SUID/SGID binaries
docker run --rm test-apache-php:hardening find / -perm /6000 -type f 2>/dev/null
```

Expected: Empty output (no SUID/SGID binaries).

- [ ] **Step 3: Verify postfix entrypoint still works**

```bash
docker run --rm \
  -e QUANT_SMTP_HOST=smtp.example.com \
  -e QUANT_SMTP_PORT=587 \
  -e QUANT_SMTP_FROM=test@example.com \
  -e QUANT_SMTP_USERNAME=user \
  -e QUANT_SMTP_PASSWORD=pass \
  -e QUANT_SMTP_RELAY_ENABLED=true \
  --entrypoint docker-entrypoint.sh \
  test-apache-php:hardening \
  bash -c "postfix status && echo PASS || echo 'postfix not running (expected in quick test)'"
```

Expected: Postfix starts (entrypoint re-sets SGID on postdrop before starting).

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "security: strip SUID/SGID bits from all binaries (CIS 4.8)"
```

---

### Task 6: Final integration test

**Files:** None (verification only)

- [ ] **Step 1: Clean build from scratch**

```bash
docker build --no-cache -t test-apache-php:hardening .
```

- [ ] **Step 2: Run full integration test**

```bash
# Start container
docker run -d --name integration-test -p 8888:8080 \
  -e QUANT_SMTP_HOST=smtp.example.com \
  -e QUANT_SMTP_PORT=587 \
  -e QUANT_SMTP_FROM=test@example.com \
  -e QUANT_SMTP_USERNAME=user \
  -e QUANT_SMTP_PASSWORD=pass \
  test-apache-php:hardening

sleep 5

# 1. HTTP responds
echo "=== HTTP check ==="
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/

# 2. No root apache processes
echo -e "\n=== Process check ==="
docker exec integration-test ps -eo user,comm | grep -E '(apache|httpd)'

# 3. No SUID/SGID (at build time, postdrop gets re-set at runtime by entrypoint)
echo -e "\n=== SUID/SGID check ==="
docker exec integration-test find / -perm /6000 -type f 2>/dev/null | head -5

# 4. No sudo
echo -e "\n=== sudo check ==="
docker exec integration-test which sudo && echo "FAIL" || echo "PASS: no sudo"

# 5. No vim
echo -e "\n=== vim check ==="
docker exec integration-test which vim && echo "FAIL" || echo "PASS: no vim"

# 6. No git
echo -e "\n=== git check ==="
docker exec integration-test which git && echo "FAIL" || echo "PASS: no git"

# 7. Healthcheck
echo -e "\n=== Healthcheck ==="
docker inspect --format='{{.State.Health.Status}}' integration-test

# 8. ssmtp present
echo -e "\n=== ssmtp check ==="
docker exec integration-test which ssmtp && echo "PASS" || echo "FAIL: ssmtp missing"

# 9. postfix present
echo -e "\n=== postfix check ==="
docker exec integration-test which postconf && echo "PASS" || echo "FAIL: postfix missing"

docker stop integration-test && docker rm integration-test
```

Expected: All checks pass. HTTP 200, www-data processes, no sudo/vim/git, healthy status.

- [ ] **Step 3: Test with docker-compose**

```bash
cd /Users/stuart/apps/quant-templates/app-apache-php
docker compose up -d --build
sleep 10
curl -s -o /dev/null -w "%{http_code}" http://localhost/
docker compose down
```

Expected: HTTP 200 via port 80 -> 8080 mapping.
