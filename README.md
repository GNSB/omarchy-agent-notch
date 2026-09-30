# Agent Notch for Omarchy

A dynamic-island style notch that hangs under the Omarchy bar and shows, live, what your
**Claude Code** sessions (and optionally **Grok Bots**) are doing — animated faces that think,
work, wait for you, celebrate when done and shake on errors. You can also ask Claude something
straight from the notch.

https://github.com/GNSB/omarchy-agent-notch/raw/main/assets/demo.mp4

## Features

- **Collapsed**: an orb for your Claude session on the left, a 2×2 cluster of other agents on the right.
- **Hover / click**: focus card with a step carousel + one chip per agent.
- **Alerts**: peeks open on its own when an agent is waiting for input, finishes or fails.
- **Ask from the notch**: click the Claude orb → type a prompt → runs headless `claude -p`,
  the answer renders in the notch (reply, or continue it in a terminal). `+` cycles the working dir over `~/Projects/*`.
- **Grok Bots** (optional): `myzk-agents mcp` is a stdio MCP server with a `report_status` tool.
- Zero dependencies beyond Omarchy (Quickshell) and `python3`.

## Install

```bash
git clone https://github.com/GNSB/omarchy-agent-notch
cd omarchy-agent-notch
./install.sh
```

It copies the plugin to `~/.config/omarchy/plugins/myzk.notch`, the backend to `~/.local/bin/myzk-agents`,
enables the plugin in `~/.config/omarchy/shell.json`, **merges** the hooks into `~/.claude/settings.json`
(backups saved as `*.bak-notch`) and restarts the shell. Uninstall with `./uninstall.sh`.

## Configure

Knobs live at the top of `~/.config/omarchy/plugins/myzk.notch/Notch.qml`:

| knob | default | |
|---|---|---|
| `screenName` | `""` | monitor to show it on (`hyprctl monitors`); empty = first screen |
| `sleepAfter` | `600` | seconds idle before an orb dozes off |
| `doneGlow` | `90` | seconds a finished agent stays happy |
| `fontFamily` | `Noto Sans` | |

After editing run `omarchy restart shell`.

## IPC

```bash
qs -p /usr/share/omarchy/shell ipc call myzk.notch toggle   # also: grok, ask, greet, close, last, demo true|false
```

## Backend CLI

```bash
myzk-agents list | watch                      # see the board in a terminal
myzk-agents set AGENT ID STATE --task "…"     # report from any script (thinking|working|waiting|done|error)
myzk-agents rm AGENT ID
```

### Grok Bots

Add a stdio MCP server in the Grok Bot app: command `~/.local/bin/myzk-agents`, args `mcp`.
Bots then call `report_status(bot, state, task, detail)`.

## Notes

- The UI strings are in Spanish (the Claude session is called "Claudi") — PRs for i18n welcome.
- Asking from the notch runs `claude -p --permission-mode auto` — only use it if you're fine with that.
- `plugin/record-demo.sh OUT.mp4` records the showcase video with fake agents (needs `gpu-screen-recorder`).

## License

MIT
