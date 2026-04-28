#!/bin/bash
set -uo pipefail

export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
export SUPPRESS_LABEL_WARNING=True

# ─── Configuration ────────────────────────────────────────────────────────────
# Required — set via environment variables or export before running
COMPARTMENT_ID="${OCI_COMPARTMENT_ID:?'OCI_COMPARTMENT_ID is not set'}"
IMAGE_ID="${OCI_IMAGE_ID:?'OCI_IMAGE_ID is not set'}"
SUBNET_ID="${OCI_SUBNET_ID:?'OCI_SUBNET_ID is not set'}"

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/oracle_key.pub}"
LOG_FILE="${LOG_FILE:-$HOME/oracle_sniper.log}"
ERROR_LOG="${ERROR_LOG:-$HOME/oracle_unknown_error.log}"

# 0 = unlimited. Set > 0 to cap attempts (e.g. MAX_ATTEMPTS=50)
MAX_ATTEMPTS="${MAX_ATTEMPTS:-0}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-60}"   # seconds between attempts on "no capacity"

# Optional: push notifications via ntfy.sh
# Example: export NTFY_TOPIC="my-oracle-sniper-xyz123"
NTFY_TOPIC="${NTFY_TOPIC:-}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
INDEX=0
COUNT=1
START_TIME=$(date +%s)

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

notify() {
    local msg="$1"
    log "NOTIFY" "$msg"
    if [[ -n "$NTFY_TOPIC" ]]; then
        curl -s --max-time 10 -d "$msg" "ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true
    fi
    command -v notify-send &>/dev/null && notify-send "Oracle Cloud" "$msg" 2>/dev/null || true
}

elapsed_min() {
    echo $(( ($(date +%s) - START_TIME) / 60 ))
}

cleanup() {
    local attempts=$(( COUNT - 1 ))
    log "INFO" "Stopped. Attempts: $attempts | Elapsed: $(elapsed_min) min"
    notify "Oracle Sniper stopped after $attempts attempts"
    rm -f /tmp/oci_last_attempt.log
    exit 0
}
trap cleanup SIGINT SIGTERM

check_prereqs() {
    local ok=true

    if ! command -v oci &>/dev/null; then
        log "ERROR" "OCI CLI not found. Install with: pip install oci-cli"
        ok=false
    fi

    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log "ERROR" "SSH public key not found: $SSH_KEY_PATH"
        ok=false
    fi

    [[ "$ok" == "false" ]] && exit 1

    if ! oci iam region list --output table &>/dev/null; then
        log "ERROR" "OCI CLI not authenticated. Check ~/.oci/config"
        exit 1
    fi

    log "INFO" "Prerequisites OK. OCI CLI is ready."
}

# ─── Start ───────────────────────────────────────────────────────────────────
check_prereqs

log "INFO" "=== Oracle Sniper v4 | Target: VM.Standard.A1.Flex 1 OCPU / 6 GB ==="
[[ $MAX_ATTEMPTS -gt 0 ]] && log "INFO" "Attempt limit: $MAX_ATTEMPTS"
[[ -n "$NTFY_TOPIC" ]]    && log "INFO" "Notifications: ntfy.sh/$NTFY_TOPIC"

# Fetch availability domains dynamically — works for any region
log "INFO" "Fetching availability domains..."
mapfile -t ADS < <(oci iam availability-domain list \
    --compartment-id "$COMPARTMENT_ID" \
    --output json | jq -r '.data[].name')

if [[ ${#ADS[@]} -eq 0 ]]; then
    log "ERROR" "Failed to fetch availability domains. Check your compartment ID and region."
    exit 1
fi

log "INFO" "Found ${#ADS[@]} availability domain(s): ${ADS[*]}"

# ─── Main loop ───────────────────────────────────────────────────────────────
while true; do
    if [[ $MAX_ATTEMPTS -gt 0 && $COUNT -gt $MAX_ATTEMPTS ]]; then
        log "INFO" "Attempt limit reached ($MAX_ATTEMPTS). Exiting."
        notify "Oracle Sniper: $MAX_ATTEMPTS attempts with no result"
        exit 0
    fi

    CURRENT_AD="${ADS[$INDEX]}"
    log "INFO" "Attempt #$COUNT | AD: $CURRENT_AD"

    OCI_OUTPUT=$(oci compute instance launch \
        --availability-domain      "$CURRENT_AD" \
        --compartment-id           "$COMPARTMENT_ID" \
        --shape                    "VM.Standard.A1.Flex" \
        --shape-config             '{"ocpus":1,"memoryInGBs":6}' \
        --display-name             "dev-server-2026" \
        --image-id                 "$IMAGE_ID" \
        --subnet-id                "$SUBNET_ID" \
        --assign-public-ip         true \
        --ssh-authorized-keys-file "$SSH_KEY_PATH" \
        --boot-volume-size-in-gbs  50 \
        2>&1) || true
    OCI_EXIT=$?

    echo "$OCI_OUTPUT"
    echo "$OCI_OUTPUT" > /tmp/oci_last_attempt.log

    if [[ "$OCI_OUTPUT" == *"Out of host capacity"* || "$OCI_OUTPUT" == *"InternalError"* ]]; then
        log "INFO" "No capacity in $CURRENT_AD. Rotating..."
        INDEX=$(( (INDEX + 1) % ${#ADS[@]} ))
        COUNT=$(( COUNT + 1 ))
        sleep "$SLEEP_INTERVAL"

    elif [[ $OCI_EXIT -eq 0 && "$OCI_OUTPUT" == *'"lifecycleState": "PROVISIONING"'* ]]; then
        log "INFO" "SUCCESS! Instance provisioning. Attempts: $COUNT | Elapsed: $(elapsed_min) min"
        notify "Oracle Cloud: instance created! Attempts: $COUNT, AD: $CURRENT_AD, elapsed: $(elapsed_min) min"
        break

    elif [[ "$OCI_OUTPUT" == *"LimitExceeded"* ]]; then
        log "ERROR" "LimitExceeded — resource limit reached. Check Oracle console."
        notify "Oracle Cloud: LimitExceeded — check OCI console"
        exit 2

    elif [[ "$OCI_OUTPUT" == *"NotAuthorizedOrNotFound"* ]]; then
        log "ERROR" "NotAuthorizedOrNotFound — check OCIDs and IAM policies."
        notify "Oracle Cloud: authorization error (NotAuthorizedOrNotFound)"
        exit 3

    else
        log "WARN" "Unknown response (exit=$OCI_EXIT). Pausing 10 min..."
        {
            echo "=== Attempt #$COUNT | AD: $CURRENT_AD | $(date) | exit=$OCI_EXIT ==="
            echo "$OCI_OUTPUT"
            echo "────────────────────────────────────────────────────"
        } >> "$ERROR_LOG"
        COUNT=$(( COUNT + 1 ))
        sleep 600
    fi
done

log "INFO" "=== Completed successfully. Attempts: $COUNT | Elapsed: $(elapsed_min) min ==="
