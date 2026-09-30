#!/usr/bin/env bash
# Installs the agent notch: Omarchy overlay plugin + myzk-agents backend + Claude Code hooks.
set -euo pipefail
cd "$(dirname "$0")"

PLUGIN_DIR="$HOME/.config/omarchy/plugins/myzk.notch"
BIN="$HOME/.local/bin/myzk-agents"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }
[ -d "$HOME/.config/omarchy" ] || { echo "This needs Omarchy (~/.config/omarchy not found)"; exit 1; }

echo "→ plugin  $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp plugin/* "$PLUGIN_DIR/"

CONFIG="$HOME/.config/agent-notch/config.json"
if [ ! -f "$CONFIG" ]; then
  echo "→ config  $CONFIG"
  mkdir -p "$(dirname "$CONFIG")"
  cp config.example.json "$CONFIG"
else
  echo "→ config  $CONFIG (kept yours)"
fi

echo "→ backend $BIN"
mkdir -p "$(dirname "$BIN")"
install -m 755 bin/myzk-agents "$BIN"

python3 - "$SHELL_JSON" "$CLAUDE_SETTINGS" "$BIN" <<'PY'
import json, os, shutil, sys
shell_json, settings, bin_path = sys.argv[1:]

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
if not any(p.get("id") == "myzk.notch" for p in plugins):
    plugins.append({"id": "myzk.notch"})
save(shell_json, s)
print("→ enabled myzk.notch in", shell_json)

# Wire Claude Code hooks (merged, never replacing existing ones).
c = load(settings)
hooks = c.setdefault("hooks", {})
cmd = bin_path + " claude-hook"
for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
              "Notification", "Stop", "SessionEnd"]:
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
echo "Done. Open a Claude Code session and watch the notch. Settings: $CONFIG"
