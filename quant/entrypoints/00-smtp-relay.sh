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
