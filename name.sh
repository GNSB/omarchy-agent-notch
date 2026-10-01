# Sourced by the installers. The name prefixes the backend (<name>-agents), the Omarchy plugin id
# (<name>.notch, also its IPC target) and the state dir (~/.local/state/<name>-agents).
# Picked from: --name X, $NOTCH_NAME, the name of the last install, or "myzk".
NAME_FILE="$HOME/.config/agent-notch/name"

notch_name() {
  N="${NOTCH_NAME:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) N="${2:-}"; shift 2 || shift ;;
      --name=*) N="${1#*=}"; shift ;;
      *) shift ;;
    esac
  done
  PREV="$(cat "$NAME_FILE" 2>/dev/null || true)"
  N="${N:-${PREV:-myzk}}"
  [[ "$N" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "Invalid name '$N' (use a-z, 0-9, - and _)"; exit 1; }
}

# Rewrites the built-in "myzk" names in already-copied files.
apply_name() {
  [ "$N" = myzk ] && return 0
  local f
  for f in "$@"; do
    sed -i.tmp -e "s/myzk\.notch/$N.notch/g" -e "s/myzk-agents/$N-agents/g" -e "s/myzk-notch/$N-notch/g" "$f"
    rm -f "$f.tmp"
  done
}
