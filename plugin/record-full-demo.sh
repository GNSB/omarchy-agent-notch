#!/bin/bash
# Full showcase: notch + agents view + customization + chat client + git,
# recorded on an empty workspace of the main screen with demo data only
# (no real agents run). Usage: record-full-demo.sh OUT.mp4
set -u
OUT="$1"
D="$HOME/.local/state/myzk-notch-demo"
Q="qs -p /usr/share/omarchy/shell ipc call myzk.notch"
MON="${MON:-$(python3 -c "import json;print(json.load(open('$HOME/.config/agent-notch/config.json')).get('screen','DP-2'))")}"
REPO="${REPO:-$HOME/Projects/omarchy-agent-notch}"
CFG="$HOME/.config/agent-notch/config.json"
CHAT_KEY="claude:showcase-1"
CHAT_FILE="$HOME/.local/state/myzk-agents/chats/claude-showcase-1.json"
S() { XDG_STATE_HOME="$D" "$HOME/.local/bin/myzk-agents" set "$@"; }
z() { python3 -c "import time;time.sleep($1)"; }
# Direct edits of the demo board for fields `set` doesn't cover.
J() { python3 - "$D/myzk-agents/summary.json" "$REPO" "$@" <<'EOF'
import json, sys, time, os
path, repo, op = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path)); a = d["agents"]; now = time.time()
if op == "meta":                      # cwd + model badges
    a["claude:main"].update(cwd=repo, model="opus", route="rules")
    a["claude:showcase-1"].update(cwd=repo, model="sonnet", route="auto", source="notch")
    a["codex:gpt"].update(model="gpt-5", route="rules")
elif op == "answer":
    a["claude:showcase-1"].update(state="done", since=now, updated=now, source="notch",
        detail="README y capturas listas",
        answer="**Listo:**\n\n- README con la ventana *Agent Notch* y el inspector Git\n"
               "- 4 capturas nuevas en `assets/`\n- Rama `configurable-name` al día ✅\n\n¿Abro el PR?")
elif op == "sleepall":
    for e in a.values(): e.update(state="idle", updated=now - 900, since=now - 900)
tmp = path + ".tmp"; json.dump(d, open(tmp, "w"), ensure_ascii=False); os.replace(tmp, path)
EOF
}
# Live config tweaks for the customization segment (restored on exit).
C() { python3 - "$CFG" "$@" <<'EOF'
import json, sys, os
path, style, gear, color = sys.argv[1:5]
c = json.load(open(path)); a = c.setdefault("agents", {}).setdefault("claude", {})
a["faceStyle"] = style; a["accessory"] = [g for g in gear.split(",") if g]
if color: a["color"] = color
tmp = path + ".tmp"; json.dump(c, open(tmp, "w"), ensure_ascii=False, indent=2); os.replace(tmp, path)
EOF
}

BAK=$(mktemp); cp "$CFG" "$BAK"
PREV_WS=$(hyprctl monitors -j | python3 -c "import json,sys;print([m for m in json.load(sys.stdin) if m['name']=='$MON'][0]['activeWorkspace']['id'])")
PREV_MON=$(hyprctl monitors -j | python3 -c "import json,sys;print([m for m in json.load(sys.stdin) if m['focused']][0]['name'])")
cleanup() {
  [ -n "${REC:-}" ] && kill -INT "$REC" 2>/dev/null && wait "$REC" 2>/dev/null
  cp "$BAK" "$CFG"; rm -f "$BAK" "$CHAT_FILE"
  $Q close >/dev/null; $Q demo false >/dev/null
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$PREV_WS\" })" >/dev/null
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$PREV_MON\" })" >/dev/null
}
trap cleanup EXIT

rm -rf "$D"; mkdir -p "$D" "$(dirname "$CHAT_FILE")"
S claude main idle --name omarchy-agent-notch --detail "Sesión abierta"
S claude showcase-1 idle --name "README nuevo" --task "Actualiza el README con capturas"
S codex gpt idle --name GPT --detail "Sesión abierta"
for b in investigador ventas soporte redes; do S grok "$b" idle --name "$b"; done
J meta
cat > "$CHAT_FILE" <<'EOF'
[{"q": "¿Qué cambió en el notch esta semana?", "a": "**Esta semana:**\n\n- Ventana *Agent Notch* con chats e inspector Git\n- Router de modelos (reglas → caché → Haiku)\n- Personalización por agente: estilo, accesorios y color\n\nTodo en `main` salvo la rama `configurable-name`.", "t": 1790860000, "error": false},
 {"q": "Actualiza el README con capturas nuevas", "a": "Hecho ✅ — agregué 4 GIFs en `assets/` y una sección **Cliente y Git**. Los cambios están sin commitear para que los revises.", "t": 1790860300, "error": false}]
EOF

hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
# The client window opens wherever it was last mapped: close it so it maps here.
client_up() { hyprctl clients -j | python3 -c "import json,sys;print(any(c['title']=='Agent Notch' for c in json.load(sys.stdin)))"; }
[ "$(client_up)" = True ] && $Q client && z 0.8
$Q demo true; z 1.5

gpu-screen-recorder -w "$MON" -f 60 -k h264 -q very_high -cursor no -o "$OUT" >/dev/null 2>&1 &
REC=$!; z 1.5

# 1. Greeting, agents come alive
$Q greet; z 4.5
S claude main working --task "Inspector Git en vivo" --detail "Leyendo ClientWindow.qml"; z 1.4
S grok investigador working --task "Tendencias en X" --detail "Leyendo hilos"; z 0.9
S codex gpt thinking --task "Revisar tests"; z 0.9
S grok ventas thinking --task "Resumen semanal"; z 1.6

# 2. Expanded: focus card + chips + Grok capsule
$Q toggle; z 1.6
S claude main working --detail "Editando agent-notch-tools"; z 1.6
S claude main working --detail "Ejecutando git status"; z 1.6
$Q grok; z 3.0
$Q grok; z 1.2
$Q toggle; z 1.2

# 3. Agents view: which coding CLIs are installed
$Q agents; z 4.5
$Q close; z 1.0

# 4. Customization: live preview of style, gear and colour
$Q customize; z 2.0
C cat "party,glasses" ""; z 1.8
C dog "crown" "#4FB3E0"; z 1.8
C orb "headphones,shades" "#8BE04F"; z 1.8
C hamster "helmet" "#E0784F"; z 1.8
$Q react dizzy; z 2.4
cp "$BAK" "$CFG"; $Q close; z 1.2

# 5. Ask from the notch (model picker + badge)
$Q ask; z 1.0
wtype -d 40 "Actualiza el README con capturas nuevas"; z 0.8
wtype -k Return; z 1.8
S claude showcase-1 working --detail "Leyendo README.md"; z 1.5
S claude showcase-1 working --detail "Generando GIFs"; z 1.5
J answer; z 1.5
$Q last; z 4.5
$Q close; z 1.0

# 6. Client window: chat transcript + live Git inspector
$Q chat "$CHAT_KEY"; z 7.0
$Q chat "claude:main"; z 4.0
$Q tools; z 6.0
[ "$(client_up)" = True ] && $Q client; z 1.2

# 7. Alerts, then everyone dozes off
S grok soporte waiting --task "Ticket #214" --detail "¿Reembolso o cambio?"; z 3.8
S grok redes error --task "Publicar reel" --detail "Formato rechazado"; z 3.8
S claude main done --detail "Inspector Git listo"; z 4.0
J sleepall; z 4.5

kill -INT $REC; wait $REC 2>/dev/null; REC=""
echo "done: $OUT"
