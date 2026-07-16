#!/bin/bash
# post-install script for ZeroClaw

set -e

# Runs under the nimbus user session
# Installs systemd service, waits for Lemonade, writes config, and starts service on port 3000.

export XDG_RUNTIME_DIR=/run/user/1001
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus

LEMONADE_API="http://127.0.0.1:13305/api/v1"
CONFIG_DIR="$HOME/.zeroclaw"
CONFIG_FILE="$CONFIG_DIR/config.toml"

log() {
    echo "ZeroClaw Post-Install: $1"
}

# 1. Install/register the systemd user service unit manually (bypassing failed snap script)
SERVICE_NAME="zeroclaw"
UNIT_SRC="/snap/zeroclaw/current/share/systemd/user/${SERVICE_NAME}.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_DST="${UNIT_DIR}/${SERVICE_NAME}.service"

if [ -f "$UNIT_SRC" ]; then
    log "Installing systemd user unit for ZeroClaw..."
    mkdir -p "$UNIT_DIR"
    cp "$UNIT_SRC" "$UNIT_DST"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1 || true
fi

# 2. Wait for Lemonade to be ready
log "Waiting for Lemonade to be ready..."
for i in {1..30}; do
    if curl -sf --connect-timeout 2 "${LEMONADE_API}/models" >/dev/null; then
        log "Lemonade is ready."
        break
    fi
    sleep 2
done

# 3. Probe models
MODELS=$(curl -sf --connect-timeout 3 "${LEMONADE_API}/models" 2>/dev/null \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

# 4. Select best model or fallback
pick_best() {
    local best_id=""
    local best_score=-999
    while IFS= read -r id; do
        [ -z "$id" ] && continue
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

# Prefer Nimbus's router collection if it's registered — it already encodes
# the local/cloud routing policy, so claw apps should address it by name
# rather than picking a specific backend model themselves.
SELECTED=""
if echo "$MODELS" | grep -qi '^NimbusModel$'; then
    SELECTED="user.NimbusModel"
fi

if [ -z "$SELECTED" ]; then
    SELECTED=$(pick_best)
fi
if [ -z "$SELECTED" ]; then
    SELECTED=$(echo "$MODELS" | head -n 1)
fi

if [ -z "$SELECTED" ]; then
    SELECTED="Qwen3.5-9B-Q4_K_M.gguf"
fi

log "Writing configuration to $CONFIG_FILE with model $SELECTED"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << ZEROCLAW_CFG
default_provider = "openai"
api_url = "http://127.0.0.1:13305"
api_path = "/api/v1/chat/completions"
default_model = "${SELECTED}"
api_key = "lemonade"

[gateway]
host = "0.0.0.0"
port = 3000
allow_public_bind = true
ZEROCLAW_CFG

log "Restarting ZeroClaw service..."
systemctl --user enable --now zeroclaw >/dev/null 2>&1 || true
systemctl --user restart zeroclaw >/dev/null 2>&1 || true
log "ZeroClaw post-install completed."
