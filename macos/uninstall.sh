#!/usr/bin/env bash
LABEL="com.agentnotch.mac"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/agent-notch"
echo "Removed the notch app. Hooks stay in ~/.claude/settings.json (restore *.bak-notch or remove entries with 'myzk-agents claude-hook')."
