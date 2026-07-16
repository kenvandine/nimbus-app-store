#!/bin/sh
set -e

# Ensure systemd user session variables are defined (required for systemctl --user commands)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    uid=$(id -u)
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
fi

# Probe lemonade models to find what's loaded
LEMONADE_API="http://127.0.0.1:13305/api/v1"
CURL="/snap/hermes-agent/current/usr/bin/curl"
[ -f "$CURL" ] || CURL="curl"

ALL_MODELS=$("$CURL" -sf --connect-timeout 3 --max-time 5 "${LEMONADE_API}/models" 2>/dev/null \
  | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

score_model() {
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *flux*|*sdxl*|*stable?diff*) printf '%s\n' -30; return ;;
    *kokoro*|*whisper*|*tts*|*speech*) printf '%s\n' -20; return ;;
    *embed*|*retriev*|*rerank*) printf '%s\n' -20; return ;;
  esac
  score=0
  case "$lower" in *flm*)               score=$((score + 20)) ;; esac
  case "$lower" in *gguf*)              score=$((score + 10)) ;; esac
  case "$lower" in *instruct*|*-it-*|*chat*) score=$((score + 5)) ;; esac
  printf '%s\n' "$score"
}

pick_best() {
  best_id=""; best_score=-999
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    s=$(score_model "$id")
    if [ "$s" -ge 0 ] && [ "$s" -gt "$best_score" ]; then
      best_score="$s"; best_id="$id"
    fi
  done
  [ -n "$best_id" ] && printf '%s\n' "$best_id"
}

is_non_chat() {
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *flux*|*sdxl*|*stable?diff*) return 0 ;;
    *kokoro*|*whisper*|*tts*|*speech*) return 0 ;;
    *embed*|*retriev*|*rerank*) return 0 ;;
  esac
  return 1
}

MODELS=""
for m in $ALL_MODELS; do
  is_non_chat "$m" && continue
  MODELS="${MODELS}${m}
"
done
MODELS=$(printf '%s' "$MODELS" | sed '/^$/d')

# Prefer Nimbus's router collection if it's registered — it already encodes
# the local/cloud routing policy, so claw apps should address it by name
# rather than picking a specific backend model themselves.
SELECTED=""
if printf '%s\n' "$MODELS" | grep -qi '^NimbusModel$'; then
    SELECTED="user.NimbusModel"
fi

[ -z "$SELECTED" ] && SELECTED=$(printf '%s\n' "$MODELS" | pick_best)
[ -z "$SELECTED" ] && SELECTED=$(printf '%s\n' "$MODELS" | head -1)

# Fallback model ID if no models are detected
[ -z "$SELECTED" ] && SELECTED="Qwen3.5-9B-Q4_K_M.gguf"

echo "Configuring Hermes Agent with model: $SELECTED"

# Set provider to custom, model, base_url, and override context length to 64K
hermes-agent config set model.provider custom
hermes-agent config set model.base_url "$LEMONADE_API"
hermes-agent config set model.api_key lemonade
hermes-agent config set model.model "$SELECTED"
hermes-agent config set model.context_length 65536

# Restart the service
systemctl --user restart hermes-agent || true
echo "Hermes Agent configuration completed successfully."
