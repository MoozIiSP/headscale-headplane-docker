#!/bin/sh
set -e

ACME_HOME="/app/acme.sh"
CERT_SAVE_DIR="/etc/letsencrypt"
DOMAIN="$DOMAIN" # Get domain from environment variable

echo "--- Certificate Management & Configuration ---"

# Function to check if certificate exists and is valid
check_certificate() {
    local cert_dir="${CERT_SAVE_DIR}/live/${DOMAIN}"
    local cert_file="${cert_dir}/fullchain.pem"
    local key_file="${cert_dir}/privkey.pem"

    # Check if certificate files exist
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "Certificate files not found in ${cert_dir}"
        return 1
    fi

    # Check if certificate is valid and not expired
    if ! openssl x509 -checkend 86400 -noout -in "$cert_file" >/dev/null 2>&1; then
        echo "Certificate is expired or will expire within 24 hours"
        return 1
    fi

    echo "Valid certificate found"
    return 0
}

# Ensure DOMAIN is exported so envsubst can see it
export DOMAIN

# Check if DOMAIN variable is set and apply envsubst to config files
if [ -z "$DOMAIN" ]; then
  echo "Warning: DOMAIN environment variable is not set."
  echo "Skipping envsubst configuration and certificate issuance/renewal."
  echo "TLS and Headscale server_url might not be configured correctly."
else
  echo "DOMAIN is set to: $DOMAIN"

  # --- Apply envsubst to headscale.yaml ---
  HEADSCALE_CONFIG="/etc/headscale/config.yaml"
  if [ -f "$HEADSCALE_CONFIG" ]; then
    echo "Applying envsubst to $HEADSCALE_CONFIG..."
    # Use a temporary file for atomic update
    envsubst < "$HEADSCALE_CONFIG" > "${HEADSCALE_CONFIG}.tmp" && mv "${HEADSCALE_CONFIG}.tmp" "$HEADSCALE_CONFIG"
    echo "Finished envsubst for $HEADSCALE_CONFIG."
    # Optional: You might need to apply to headplane.yaml if it uses $DOMAIN
    # envsubst < /etc/headplane/config.yaml > /etc/headplane/config.yaml.tmp && mv /etc/headplane/config.yaml.tmp /etc/headplane/config.yaml
  else
    echo "Warning: Headscale config file not found at $HEADSCALE_CONFIG. Skipping envsubst."
  fi

  # Ensure acme.sh is in PATH and HOME is set
  export PATH="${ACME_HOME}:${PATH}"
  export ACME_SH_HOME="${ACME_HOME}"

  # Create certificate save directory
  mkdir -p "${CERT_SAVE_DIR}/live/${DOMAIN}"

  # Check if we need to generate/renew certificates
  if ! check_certificate; then
    echo "Certificate check failed, proceeding with certificate generation/renewal..."

    # For localhost testing, we'll use self-signed certificates
    if [ "$DOMAIN" = "localhost" ]; then
      echo "Using self-signed certificates for localhost..."
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${CERT_SAVE_DIR}/live/${DOMAIN}/privkey.pem" \
        -out "${CERT_SAVE_DIR}/live/${DOMAIN}/fullchain.pem" \
        -subj "/CN=localhost" \
        -addext "subjectAltName = DNS:localhost"
      echo "Self-signed certificates generated successfully."
    else
      # For real domains, use HTTP validation
      if ! acme.sh --issue --standalone -d "$DOMAIN" \
          --fullchain-path "${CERT_SAVE_DIR}/live/${DOMAIN}/fullchain.pem" \
          --key-path "${CERT_SAVE_DIR}/live/${DOMAIN}/privkey.pem" \
          --reloadcmd "echo 'Certificate for $DOMAIN saved to ${CERT_SAVE_DIR}/live/${DOMAIN}/'"
      then
          echo "Error: Certificate issuance or renewal failed for $DOMAIN."
          echo "Please check acme.sh logs and environment variables."
          echo "Exiting. Fix the issue and restart the container."
          exit 1
      fi
    fi

    # Verify the new certificate
    if ! check_certificate; then
      echo "Error: New certificate verification failed"
      exit 1
    fi
  else
    echo "Valid certificate found, skipping generation/renewal"
  fi

  echo "Certificate process finished successfully."
  echo "Certificates saved to ${CERT_SAVE_DIR}/live/${DOMAIN}/"

fi # End if [ -z "$DOMAIN" ] check

echo "--- End Certificate Management & Configuration ---"

# Execute CMD passed to the entrypoint (supervisord)
echo "Executing CMD: $@"
exec "$@"
