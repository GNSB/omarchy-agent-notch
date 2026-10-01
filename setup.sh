#!/usr/bin/env bash
# Picks the right installer: Omarchy (Linux, Quickshell) or macOS (native SwiftUI).
#   ./setup.sh            asks (default: detected from this machine)
#   ./setup.sh omarchy    or: ./setup.sh mac
set -euo pipefail
cd "$(dirname "$0")"

choice="${1:-}"
if [ -z "$choice" ]; then
  [ "$(uname)" = "Darwin" ] && def=mac || def=omarchy
  echo "Agent Notch: which version do you want to install?"
  echo "  1) Omarchy  (Linux, Quickshell plugin)"
  echo "  2) macOS    (native SwiftUI app)"
  [ "$def" = mac ] && d=2 || d=1
  read -r -p "Choice [$d]: " n
  case "${n:-$d}" in 1) choice=omarchy ;; 2) choice=mac ;; *) echo "Invalid choice"; exit 1 ;; esac
fi

case "$choice" in
  omarchy|linux) exec ./install.sh ;;
  mac|macos) [ "$(uname)" = "Darwin" ] || { echo "The macOS version needs macOS"; exit 1; }
             exec ./macos/install.sh ;;
  *) echo "Usage: $0 [omarchy|mac]"; exit 1 ;;
esac
