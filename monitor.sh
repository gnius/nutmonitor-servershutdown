#!/bin/bash
set -euo pipefail

: "${NUT_UPS:?}"
: "${XCP_HOST:?}"

XCP_USER="${XCP_USER:-nutshutdown}"
RUNTIME_THRESHOLD_SECONDS="${RUNTIME_THRESHOLD_SECONDS:-600}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-30}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/run/secrets/id_ed25519}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH:-/run/secrets/known_hosts}"

SMTP_ENABLED="${SMTP_ENABLED:-false}"
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_FROM="${SMTP_FROM:-}"
SMTP_TO="${SMTP_TO:-}"

shutdown_sent=0

log() { echo "[$(date -Is)] $*"; }

get_var() {
  upsc "${NUT_UPS}" 2>/dev/null | awk -F': ' -v key="$1" '$1 == key {print $2}'
}

remote_cmd() {
  ssh -i "$SSH_KEY_PATH" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$KNOWN_HOSTS_PATH" \
    "$XCP_USER@$XCP_HOST" "$1"
}

send_email() {
  if [[ "$SMTP_ENABLED" != "true" ]]; then
    return
  fi

  cat <<EOF > /tmp/msmtprc
account default
host $SMTP_HOST
port $SMTP_PORT
auth on
user $SMTP_USER
password $SMTP_PASS
tls on
tls_starttls on
from $SMTP_FROM
EOF

  echo -e "Subject: UPS-triggered shutdown\n\nShutdown initiated on $XCP_HOST due to low UPS runtime." \
    | msmtp --file=/tmp/msmtprc "$SMTP_TO"
}

while true; do
  status="$(get_var ups.status || true)"
  runtime="$(get_var battery.runtime || true)"

  if [[ -z "$status" ]]; then
    log "Unable to read UPS status"
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi

  if [[ "$status" == *"OL"* ]]; then
    shutdown_sent=0
    sleep "$POLL_INTERVAL_SECONDS"
    continue
  fi

  if [[ "$status" == *"OB"* || "$status" == *"LB"* ]]; then
    log "On battery: runtime=$runtime"

    if [[ "$runtime" =~ ^[0-9]+$ ]] && (( runtime <= RUNTIME_THRESHOLD_SECONDS )); then
      if [[ "$shutdown_sent" -eq 0 ]]; then
        log "Threshold reached. Sending shutdown command."
        send_email
        remote_cmd shutdown
        shutdown_sent=1
      fi
    fi
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
