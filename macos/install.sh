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
# A real .app with a stable bundle id + signature: macOS (TCC) remembers the folder/file
# permissions you grant it across rebuilds. Ad-hoc binaries get a new identity every build
# and are asked again each time.
APP="$HOME/Applications/Agent Notch.app"
mkdir -p "$APP/Contents/MacOS"
install -m 755 .build/release/AgentNotch "$APP/Contents/MacOS/agent-notch"
cat > "$APP/Contents/Info.plist" <<IP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>Agent Notch</string>
  <key>CFBundleExecutable</key><string>agent-notch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Your agents read and edit projects on the Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Your agents read and edit projects in Documents.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Your agents read files in Downloads.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Your agents read files on external drives.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Your agents read files on network drives.</string>
</dict></plist>
IP
# Sign with a real identity if there is one (Apple Development / Developer ID), else ad-hoc.
IDENT="${AGENT_NOTCH_SIGN:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
if [ -n "$IDENT" ]; then
  codesign --force --sign "$IDENT" --identifier "$LABEL" "$APP" && echo "→ signed with: $IDENT"
else
  codesign --force --sign - --identifier "$LABEL" "$APP"
  echo "→ no signing identity found: ad-hoc (macOS may ask for permissions again after each rebuild)"
fi
rm -f "$BIN/agent-notch"
ln -s "$APP/Contents/MacOS/agent-notch" "$BIN/agent-notch"
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
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/agent-notch</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Done. Control: agent-notch ask|toggle|close|last   Config: $CONF/config.json"
