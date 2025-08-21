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
        DOMAIN="quantcdn.io"  # fallback
    fi
    
    POSTFIX_HOSTNAME="${QUANT_SMTP_HOSTNAME:-apache-php.$DOMAIN}"
    
    # Install Postfix if not already installed
    if ! command -v postconf >/dev/null 2>&1; then
        echo "Installing Postfix with SASL support..."
        # Pre-configure Postfix to avoid interactive prompts
        export DEBIAN_FRONTEND=noninteractive
        echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
        echo "postfix postfix/mailname string $POSTFIX_HOSTNAME" | debconf-set-selections
        apt-get update && apt-get install -y --no-install-recommends postfix ca-certificates libsasl2-modules
    fi
    postconf -e "myhostname=$POSTFIX_HOSTNAME"
    postconf -e "mydomain=$DOMAIN"
    postconf -e "myorigin=\$mydomain"
    postconf -e "inet_interfaces=127.0.0.1"
    postconf -e "inet_protocols=ipv4"
    postconf -e "mydestination="
    postconf -e "local_transport=error:local delivery disabled"
    postconf -e "relayhost=[$QUANT_SMTP_HOST]:$QUANT_SMTP_PORT"
    
    # Configure TLS per AWS SES documentation
    postconf -e "smtp_use_tls=yes"
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
    
    # Copy DNS files to Postfix chroot (needed for address resolution)
    mkdir -p /var/spool/postfix/etc
    cp /etc/resolv.conf /var/spool/postfix/etc/resolv.conf 2>/dev/null || true
    cp /etc/hosts /var/spool/postfix/etc/hosts 2>/dev/null || true
    
    # Start Postfix master daemon directly
    /usr/lib/postfix/sbin/master -w &
    
    # Wait for Postfix to start
    sleep 2
    
    echo "✅ Postfix SMTP relay configured and started"
fi