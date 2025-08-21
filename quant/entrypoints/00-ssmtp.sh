#!/bin/bash

# Configure ssmtp (lightweight sendmail replacement) if SMTP relay is NOT enabled
if [ -n "$QUANT_SMTP_HOST" ] && [ "$QUANT_SMTP_RELAY_ENABLED" != "true" ]; then
    echo "Configuring lightweight ssmtp with host: $QUANT_SMTP_HOST"
    
    # Install ssmtp if not already installed
    if ! command -v ssmtp >/dev/null 2>&1; then
        echo "Installing ssmtp..."
        apt-get update && apt-get install -y --no-install-recommends ssmtp
    fi
    
    # Ensure we can write to /etc/ssmtp directory
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
    
    echo "✅ ssmtp configured (sendmail replacement) - PHP mail() will work"
fi