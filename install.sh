#!/usr/bin/env bash
# Installs the agent notch: Omarchy overlay plugin + backend + Claude Code hooks.
#   ./install.sh [--name NAME]    NAME prefixes the backend and plugin id (default: myzk)
set -euo pipefail
cd "$(dirname "$0")"
. ./name.sh
notch_name "$@"

PLUGIN_DIR="$HOME/.config/omarchy/plugins/$N.notch"
BIN="$HOME/.local/bin/$N-agents"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }
[ -d "$HOME/.config/omarchy" ] || { echo "This needs Omarchy (~/.config/omarchy not found)"; exit 1; }

# Renamed since the last install: drop the old plugin/backend/hooks, keep the state (chats, history).
if [ -n "$PREV" ] && [ "$PREV" != "$N" ]; then
  echo "→ renaming $PREV → $N"
  NOTCH_NAME="$PREV" NOTCH_NO_RESTART=1 ./uninstall.sh >/dev/null
  STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
  if [ -d "$STATE/$PREV-agents" ] && [ ! -e "$STATE/$N-agents" ]; then
    mv "$STATE/$PREV-agents" "$STATE/$N-agents"
  fi
fi

echo "→ plugin  $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp plugin/* "$PLUGIN_DIR/"
apply_name "$PLUGIN_DIR"/*.qml "$PLUGIN_DIR/manifest.json" "$PLUGIN_DIR/record-demo.sh"

CONFIG="$HOME/.config/agent-notch/config.json"
if [ ! -f "$CONFIG" ]; then
  echo "→ config  $CONFIG"
  mkdir -p "$(dirname "$CONFIG")"
  cp config.example.json "$CONFIG"
else
  echo "→ config  $CONFIG (kept yours)"
fi
echo "$N" > "$NAME_FILE"

echo "→ backend $BIN"
mkdir -p "$(dirname "$BIN")"
install -m 755 bin/myzk-agents "$BIN"
# usage meters + the client window's git/checksum/paste helpers
install -m 755 bin/claude-usage "$(dirname "$BIN")/claude-usage"
install -m 755 bin/agent-notch-tools "$(dirname "$BIN")/agent-notch-tools"
apply_name "$BIN" "$(dirname "$BIN")/agent-notch-tools"

python3 - "$SHELL_JSON" "$CLAUDE_SETTINGS" "$BIN" "$N.notch" <<'PY'
import json, os, shutil, sys
shell_json, settings, bin_path, plugin_id = sys.argv[1:]

def load(p):
    if os.path.exists(p):
        shutil.copy(p, p + ".bak-notch")
        with open(p) as f:
            return json.load(f)
    return {}

def save(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")

# Enable the overlay plugin in the Omarchy shell.
s = load(shell_json)
plugins = s.setdefault("plugins", [])
if not any(p.get("id") == plugin_id for p in plugins):
    plugins.append({"id": plugin_id})
save(shell_json, s)
print("→ enabled", plugin_id, "in", shell_json)

# Wire Claude Code hooks (merged, never replacing existing ones).
c = load(settings)
hooks = c.setdefault("hooks", {})
cmd = bin_path + " claude-hook"
for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
              "Notification", "Stop", "SessionEnd", "PreCompact"]:
    groups = hooks.setdefault(event, [])
    if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
        continue
    group = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
    if event in ("PreToolUse", "PostToolUse"):
        group = {"matcher": "*", **group}
    groups.append(group)
save(settings, c)
print("→ Claude Code hooks added to", settings)
PY

if command -v omarchy >/dev/null; then
  echo "→ restarting shell"
  omarchy restart shell || echo "  (restart it yourself: omarchy restart shell)"
fi
echo "Done. Backend: $N-agents · IPC: $N.notch · Settings: $CONFIG"
