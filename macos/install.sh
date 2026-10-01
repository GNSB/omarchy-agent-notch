#!/usr/bin/env bash
# Agent Notch for macOS: native SwiftUI notch + the same Python backend/hooks.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/agent-notch"
LABEL="com.agentnotch.mac"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

command -v swift >/dev/null || { echo "Needs Swift (xcode-select --install)"; exit 1; }
command -v python3 >/dev/null || { echo "Needs python3"; exit 1; }

echo "→ building"
swift build -c release
mkdir -p "$BIN" "$CONF"
install -m 755 .build/release/AgentNotch "$BIN/agent-notch"
install -m 755 "$ROOT/bin/myzk-agents" "$BIN/myzk-agents"
install -m 755 "$ROOT/bin/claude-usage" "$BIN/claude-usage"
cp "$ROOT/plugin/i18n.json" "$CONF/i18n.json"

if [ ! -f "$CONF/config.json" ]; then
  python3 - "$ROOT/config.example.json" "$CONF/config.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c.update({"terminal": "", "fontFamily": "", "projectDirs": ["~/Projects/*"]})
for k in ("screen", "placement"):
    c.pop(k, None)
json.dump(c, open(sys.argv[2], "w"), indent=2, ensure_ascii=False)
PY
  echo "→ config created: $CONF/config.json"
fi

echo "→ wiring Claude Code hooks"
python3 - "$HOME/.claude/settings.json" "$BIN/myzk-agents" <<'PY'
import json, os, shutil, sys
path, bin_path = sys.argv[1:]
d = {}
if os.path.exists(path):
    shutil.copy(path, path + ".bak-notch")
    d = json.load(open(path))
hooks = d.setdefault("hooks", {})
cmd = bin_path + " claude-hook"
for ev in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd", "PreCompact"]:
    groups = hooks.setdefault(ev, [])
    if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
        continue
    g = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
    if ev in ("PreToolUse", "PostToolUse"):
        g = {"matcher": "*", **g}
    groups.append(g)
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(d, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY

echo "→ LaunchAgent (starts at login, restarts if it dies)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN/agent-notch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Done. Control: agent-notch ask|toggle|close|last   Config: $CONF/config.json"
