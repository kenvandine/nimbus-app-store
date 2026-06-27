#!/bin/sh
set -e

CONFIG="/home/nimbus/.openclaw/openclaw.json"
if [ ! -f "$CONFIG" ]; then
  echo "openclaw.json not found, bootstrapping default config..."
  # Run the bootstrap command
  openclaw setup --non-interactive --accept-risk --mode local || true
fi

if [ -f "$CONFIG" ]; then
  echo "Patching openclaw.json for insecure auth and host bind..."
  python3 -c "
import json
with open('$CONFIG') as f:
    cfg = json.load(f)
gw = cfg.setdefault('gateway', {})
gw['bind'] = 'lan'
gw.setdefault('controlUi', {})['allowInsecureAuth'] = True
with open('$CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
"
  # Restart openclaw-gateway so the config change takes effect
  systemctl --user restart openclaw-gateway || true
  echo "OpenClaw configuration patched successfully."
else
  echo "Error: openclaw.json still not found"
  exit 1
fi
