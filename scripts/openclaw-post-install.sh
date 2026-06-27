#!/bin/bash
set -e

export XDG_RUNTIME_DIR=/run/user/1001
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus

CONFIG="/home/nimbus/.openclaw/openclaw.json"
LEMONADE_API="http://127.0.0.1:13305/api/v1"

log() { echo "OpenClaw Post-Install: $1"; }

# 1. Configure the Lemonade provider.
#    setup-providers.js only knows builtin recipe names (e.g. GLM-4.7-Flash-GGUF).
#    We run --auto here to write the full provider config, then override the
#    primary model in step 2 to point at the user-downloaded Qwen3.5 model.
log "Configuring Lemonade provider..."
/snap/bin/openclaw.lemonade --auto || {
  log "WARNING: Lemonade provider setup failed; continuing with defaults"
}

# 2. Patch openclaw.json:
#    a) gateway.bind: lan          (expose on LAN for the container proxy)
#    b) gateway.controlUi.allowInsecureAuth: true  (token auth over plain HTTP)
#    c) Switch primary model to the best Qwen model Lemonade has downloaded,
#       falling back to GLM if none found.  Qwen models need generous token
#       budgets to finish reasoning before emitting visible content.
if [ -f "$CONFIG" ]; then
  log "Patching config (gateway + model)..."
  python3 << 'PYEOF'
import json, urllib.request

LEMONADE_API = 'http://127.0.0.1:13305/api/v1'
CONFIG_PATH   = '/home/nimbus/.openclaw/openclaw.json'

with open(CONFIG_PATH) as f:
    cfg = json.load(f)

# --- gateway ---
gw = cfg.setdefault('gateway', {})
gw['bind'] = 'lan'
gw.setdefault('controlUi', {})['allowInsecureAuth'] = True

# --- pick best Lemonade model ---
try:
    resp = urllib.request.urlopen(f'{LEMONADE_API}/models', timeout=5)
    data = json.loads(resp.read())
    ids = [m['id'] for m in data.get('data', [])]
    non_builtin = [i for i in ids if not i.startswith('builtin.')]

    def score(i):
        l = i.lower()
        if 'qwen' in l: return 2
        if 'glm'  in l: return 1
        return 0

    ranked = sorted(non_builtin, key=lambda i: (-score(i), i))
    best_id = ranked[0] if ranked else None
except Exception as e:
    print(f'  could not probe Lemonade: {e}')
    best_id = None

if best_id:
    print(f'  selecting model: {best_id}')
    cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('model', {})['primary'] = f'lemonade/{best_id}'

    # Ensure this model id exists in the providers list with correct token limits
    providers = cfg.get('models', {}).get('providers', {}).get('lemonade', {})
    models = providers.get('models', [])
    existing_ids = {m['id'] for m in models}
    if best_id not in existing_ids:
        models.insert(0, {
            'id': best_id,
            'name': best_id,
            'reasoning': False,
            'input': ['text', 'image'],
            'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
            'contextWindow': 131072,
            'maxTokens': 16384,
        })
        print(f'  added model entry for {best_id}')

    # Boost token limits for all thinking-model entries
    for model in models:
        mid = model.get('id', '').lower()
        if 'qwen' in mid or 'glm' in mid:
            model['maxTokens'] = 16384
            model['contextWindow'] = 131072
            model['reasoning'] = False
else:
    print('  no model selected; keeping existing primary')

with open(CONFIG_PATH, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
print('Config patched.')
PYEOF

  log "Restarting OpenClaw gateway..."
  systemctl --user restart openclaw-gateway || true
  log "OpenClaw post-install completed."
else
  log "ERROR: openclaw.json not found after provider setup"
  exit 1
fi
