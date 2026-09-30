#!/bin/bash
# Scripted recording of the myzk.notch animations on an empty workspace,
# using demo data only (no real agents, no real Claude runs).
set -u
OUT_RAW="$1"
D="$HOME/.local/state/myzk-notch-demo"
Q="qs -p /usr/share/omarchy/shell ipc call myzk.notch"
MON="${MON:-$(hyprctl monitors -j | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['name'])")}"
S() { XDG_STATE_HOME="$D" "$HOME/.local/bin/myzk-agents" set "$@"; }
z() { python3 -c "import time;time.sleep($1)"; }
# Direct edits for fields `set` doesn't cover (answer, ageing).
J() { python3 - "$D/myzk-agents/summary.json" "$@" <<'EOF'
import json, sys, time
path, op = sys.argv[1], sys.argv[2]
d = json.load(open(path))
a = d["agents"]
now = time.time()
if op == "answer":
    e = a["claude:demo-notch"]
    e.update(state="done", source="notch", since=now, updated=now,
             detail="Hoy en tv-launcher: 3 cambios",
             answer="**Hoy en tv-launcher:**\n\n- Dock con animación de rebote al abrir\n"
                    "- *Recientes* ordenados por uso\n- Build de release firmado ✅\n\n"
                    "¿Subo la versión `0.3` al TV?")
elif op == "sleepall":
    for e in a.values():
        e.update(state="idle", updated=now - 900, since=now - 900)
tmp = path + ".tmp"
json.dump(d, open(tmp, "w"), ensure_ascii=False)
import os; os.replace(tmp, path)
EOF
}

rm -rf "$D"; mkdir -p "$D"
S claude main idle --name tv-launcher --detail "Sesión abierta"
for b in investigador ventas soporte calendario redes; do S grok "$b" idle --name "$b"; done

# Empty workspace on the main screen so nothing private is in frame.
PREV_WS=$(hyprctl monitors -j | python3 -c "import json,sys;print([m for m in json.load(sys.stdin) if m['name']=='$MON'][0]['activeWorkspace']['id'])")
PREV_MON=$(hyprctl monitors -j | python3 -c "import json,sys;print([m for m in json.load(sys.stdin) if m['focused']][0]['name'])")
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
$Q demo true
z 1.5

gpu-screen-recorder -w region -region 960x420+480+0 -f 60 -k h264 -q very_high -cursor no -o "$OUT_RAW" >/dev/null 2>&1 &
REC=$!
z 1.5

# 1. Greeting
$Q greet; z 5

# 2. Collapsed: Claudi + cluster come alive
S claude main working --task "Agregar dock animado" --detail "Leyendo Dock.kt"; z 1.6
S grok investigador working --task "Tendencias de TV en X" --detail "Leyendo hilos"; z 1.0
S grok ventas thinking --task "Resumen semanal"; z 1.2
S grok calendario working --task "Agendar visitas" --detail "Revisando huecos"; z 1.8

# 3. Expanded: focus card carousel
$Q toggle; z 1.6
S claude main working --detail "Editando Dock.kt"; z 1.8
S claude main working --detail "Ejecutando ./gradlew build"; z 1.8
S claude main thinking --detail "Pensando…"; z 1.4
S claude main working --detail "Editando DockAnimator.kt"; z 1.6

# 4. Grok capsule unfolds / folds
$Q grok; z 3.2
$Q grok; z 1.6
$Q toggle; z 1.6

# 5. Alerts: needs you, error, done
S grok soporte waiting --task "Ticket #214" --detail "¿Reembolso o cambio de producto?"; z 4.2
S grok redes error --task "Publicar reel" --detail "Instagram rechazó el video (formato)"; z 4.4
S claude main done --detail "Dock animado listo y compilado"; z 4.6

# 6. Talk to Claudi from the notch
$Q ask; z 1.0
wtype -d 45 "Resume los cambios de hoy en tv-launcher"; z 0.9
wtype -k Return; z 2.2
S claude demo-notch working --detail "Leyendo git log"; z 1.8
S claude demo-notch working --detail "Revisando los diffs"; z 1.8
J answer; z 4.0
$Q last; z 5.5
$Q close; z 1.8

# 7. Everyone dozes off
J sleepall; z 5

kill -INT $REC; wait $REC 2>/dev/null
$Q demo false
hyprctl dispatch "hl.dsp.focus({ workspace = \"$PREV_WS\" })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = \"$PREV_MON\" })" >/dev/null
echo "done: $OUT_RAW"
