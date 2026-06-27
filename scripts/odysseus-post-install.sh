#!/bin/bash
# post-install script for Odysseus

set -e

# Runs under the nimbus user session
# Installs systemd service unit, configures env with OLLAMA_BASE_URL, and starts service on port 7000.

export XDG_RUNTIME_DIR=/run/user/1001
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus

ENV_FILE="$HOME/snap/odysseus/common/.env"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_DST="${UNIT_DIR}/odysseus.service"

log() {
    echo "Odysseus Post-Install: $1"
}

# 1. Dynamically write systemd user service unit since the snap doesn't bundle one
log "Creating systemd user unit for Odysseus..."
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DST" << 'EOF'
[Unit]
Description=Odysseus AI Workspace gateway service
After=network.target

[Service]
ExecStart=/snap/bin/odysseus
Restart=on-failure
RestartSec=10s
Environment=HOME=/home/nimbus
Environment=XDG_RUNTIME_DIR=/run/user/1001
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user enable --now odysseus >/dev/null 2>&1 || true

# 2. Write/update OLLAMA_BASE_URL and host/port binding in Odysseus's .env file
log "Writing environment configuration..."
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << 'EOF'
OLLAMA_BASE_URL=http://127.0.0.1:13305
ODYSSEUS_HOST=0.0.0.0
ODYSSEUS_PORT=7000
EOF

log "Restarting Odysseus service..."
systemctl --user restart odysseus >/dev/null 2>&1 || true
log "Odysseus post-install completed."
