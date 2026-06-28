#!/bin/bash
# post-install script for PicoClaw

set -e

# Ensure systemd user session variables are defined (required for systemctl --user commands)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    uid=$(id -u)
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
fi

# Run under the nimbus user session
# Probes Lemonade, sets up the model, and configures the gateway host to bind to 0.0.0.0.

LEMONADE_API="http://127.0.0.1:13305/api/v1"

log() {
    echo "PicoClaw Post-Install: $1"
}

# 1. Wait for Lemonade to be ready
log "Waiting for Lemonade to be ready..."
for i in {1..30}; do
    if curl -sf --connect-timeout 2 "${LEMONADE_API}/models" >/dev/null; then
        log "Lemonade is ready."
        break
    fi
    sleep 2
done

# 2. Probe models
MODELS=$(curl -sf --connect-timeout 3 "${LEMONADE_API}/models" 2>/dev/null \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

# 3. Select best model or fallback
pick_best() {
    local best_id=""
    local best_score=-999
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        # Score model
        local lower=$(echo "$id" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            *flux*|*sdxl*|*stable?diff*) continue ;;
            *kokoro*|*whisper*|*tts*|*speech*) continue ;;
            *embed*|*retriev*|*rerank*) continue ;;
        esac
        local score=0
        case "$lower" in *flm*) score=$((score + 20)) ;; esac
        case "$lower" in *gguf*) score=$((score + 10)) ;; esac
        case "$lower" in *instruct*|*-it-*|*chat*) score=$((score + 5)) ;; esac
        
        if [ "$score" -ge 0 ] && [ "$score" -gt "$best_score" ]; then
            best_score="$score"
            best_id="$id"
        fi
    done <<EOF
$MODELS
EOF
    echo "$best_id"
}

SELECTED=$(pick_best)
if [ -z "$SELECTED" ]; then
    SELECTED=$(echo "$MODELS" | head -n 1)
fi

if [ -z "$SELECTED" ]; then
    # Fallback default model if Lemonade returned absolutely nothing or wasn't reachable
    SELECTED="Qwen3.5-9B-Q4_K_M.gguf"
fi

log "Configuring PicoClaw default model to: $SELECTED"
# Ensure config file exists
mkdir -p "$HOME/.picoclaw"
if [ ! -f "$HOME/.picoclaw/config.json" ]; then
    /snap/bin/picoclaw onboard >/dev/null 2>&1 || true
fi

# Run picoclaw model add
/snap/bin/picoclaw --no-color model add \
    -b "$LEMONADE_API" -k lemonade -m "$SELECTED" -n "lemonade-${SELECTED}" >/dev/null 2>&1 || true

# Set gateway host to 0.0.0.0
log "Binding gateway host to 0.0.0.0"
cfg="$HOME/.picoclaw/config.json"
if [ -f "$cfg" ]; then
    python3 -c "
import json, sys
p = sys.argv[1]
with open(p) as f:
    c = json.load(f)
c.setdefault('gateway', {})['host'] = '0.0.0.0'
with open(p, 'w') as f:
    json.dump(c, f, indent=2)
    f.write('\n')
" "$cfg" || true
fi

# Inject ExecStop to clean up orphaned processes in the transient snap scope
svc_file="$HOME/.config/systemd/user/picoclaw.service"
if [ -f "$svc_file" ]; then
    if ! grep -q "ExecStop=" "$svc_file"; then
        log "Injecting ExecStop to picoclaw.service"
        sed -i '/ExecStart=/a ExecStop=/usr/bin/pkill -f picoclaw' "$svc_file"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
fi

log "Restarting PicoClaw service..."
systemctl --user restart picoclaw >/dev/null 2>&1 || true

# Wait for the PicoClaw chat service to be ready.
log "Waiting for PicoClaw chat service to be ready..."
for i in {1..30}; do
    if curl -sf --connect-timeout 2 "http://127.0.0.1:18790/" >/dev/null 2>&1; then
        log "PicoClaw chat service is ready."
        break
    fi
    sleep 2
done
log "PicoClaw post-install completed."
