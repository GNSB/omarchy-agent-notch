#!/usr/bin/env bash
# Removes the agent notch plugin, backend and its Claude Code hooks.
set -euo pipefail
BIN="$HOME/.local/bin/myzk-agents"

rm -rf "$HOME/.config/omarchy/plugins/myzk.notch" "$BIN"
python3 - "$HOME/.config/omarchy/shell.json" "$HOME/.claude/settings.json" "$BIN" <<'PY'
import json, os, sys
shell_json, settings, bin_path = sys.argv[1:]
cmd = bin_path + " claude-hook"
if os.path.exists(shell_json):
    s = json.load(open(shell_json))
    s["plugins"] = [p for p in s.get("plugins", []) if p.get("id") != "myzk.notch"]
    json.dump(s, open(shell_json, "w"), indent=2)
if os.path.exists(settings):
    c = json.load(open(settings))
    hooks = c.get("hooks", {})
    for event in list(hooks):
        for g in hooks[event]:
            g["hooks"] = [h for h in g.get("hooks", []) if h.get("command") != cmd]
        hooks[event] = [g for g in hooks[event] if g["hooks"]]
        if not hooks[event]:
            del hooks[event]
    json.dump(c, open(settings, "w"), indent=2)
PY
command -v omarchy >/dev/null && omarchy restart shell || true
echo "Agent notch removed."
