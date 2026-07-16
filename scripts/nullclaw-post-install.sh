#!/bin/bash
# post-install script for NullClaw

set -e

# Runs under the nimbus user session
# Wait for Lemonade, set default model, and configure gateway host to 0.0.0.0.

export XDG_RUNTIME_DIR=/run/user/1001
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus

LEMONADE_API="http://127.0.0.1:13305/api/v1"
CONFIG_DIR="$HOME/.nullclaw"
CONFIG_FILE="$CONFIG_DIR/config.json"
WORKSPACE="$HOME/workspace"

log() {
    echo "NullClaw Post-Install: $1"
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
cat > "$CONFIG_FILE" << NULLCLAW_CFG
{
  "models": {
    "providers": {
      "lemonade": {"base_url": "http://127.0.0.1:13305", "api_key": "lemonade"}
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "lemonade/${SELECTED}"
      },
      "workspace": "${WORKSPACE}"
    }
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 3002,
    "require_pairing": false,
    "allow_public_bind": true
  }
}
NULLCLAW_CFG

log "Restarting NullClaw service..."
systemctl --user enable --now nullclaw >/dev/null 2>&1 || true
systemctl --user restart nullclaw >/dev/null 2>&1 || true
log "Starting NullClaw UI service..."
systemctl --user enable --now nullclaw-ui >/dev/null 2>&1 || true
systemctl --user restart nullclaw-ui >/dev/null 2>&1 || true
log "NullClaw post-install completed."
