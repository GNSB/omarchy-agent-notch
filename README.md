# Agent Notch for Omarchy

A dynamic-island style notch that hangs under the Omarchy bar and shows, live, what your
**Claude Code** sessions (and optionally **Grok Bots**) are doing — animated faces that think,
work, wait for you, celebrate when done and shake on errors. You can also ask Claude something
straight from the notch.

▶️ **[Watch the demo](assets/demo.mp4)**

## Features

- **Collapsed**: an orb for your Claude session on the left, a 2×2 cluster of other agents on the right.
- **Hover / click**: focus card with a step carousel + one chip per agent.
- **Alerts**: peeks open on its own when an agent is waiting for input, finishes or fails.
- **Ask from the notch**: click the Claude orb → type a prompt → runs headless `claude -p`,
  the answer renders in the notch (reply, or continue it in a terminal). `+` cycles the working dir over `~/Projects/*`.
- **Fully configurable**: language (en/es), names, colours, timings, monitor, project dirs — one JSON file, live-reloaded.
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

Everything lives in **`~/.config/agent-notch/config.json`** (created from
[`config.example.json`](config.example.json) on install). It's **live-reloaded** — save and the notch updates;
no shell restart needed. Missing keys fall back to defaults.

| key | default | what it does |
|---|---|---|
| `language` | `"en"` | UI language: `en`, `es` (add more in `i18n.json`) |
| `assistantName` | `"Claude"` | what your Claude sessions are called in the notch |
| `grokName` | `"Grok"` | label for bots reporting via MCP |
| `screen` | `""` | monitor name from `hyprctl monitors`; empty = first screen |
| `placement` | `"below"` | `"below"`: hangs under the bar. `"bar"`: sits **inside** the bar like a Mac notch and only drops over windows when it opens (see below) |
| `faceStyle` | `"orb"` | face design: `"orb"` (glossy ball), `"cat"` (ears, whiskers, swishing tail), `"dog"` (floppy ears, snout, tongue, wagging tail) or `"hamster"` (round ears, stuffed cheeks, buck teeth) |
| `grokFaceStyle` | = `faceStyle` | same, but only for Grok Bots (e.g. cat Claude, orb bots) |
| `accessory` | `[]` | head gear, one name or a list: `hat`, `cowboy`, `crown`, `party`, `bow`, `headphones`, `helmet`, `mask`, `glasses`, `shades` (e.g. `["crown", "shades"]`) |
| `grokAccessory` | = `accessory` | same, for Grok Bots |
| `accessories` | `{}` | per-bot override by name, e.g. `{"Researcher": "glasses"}` |
| `greetOnStart` | `true` | play the hello animation when the shell starts |
| `projectDirs` | `["~/Projects/*"]` | globs the `+` button cycles through as working dir for asks |
| `claudeCommand` | `"claude"` | Claude Code binary |
| `permissionMode` | `"auto"` | `--permission-mode` for asks from the notch (`default`, `acceptEdits`, `plan`, `auto`…) |
| `systemPrompt` | `""` | extra system prompt for notch asks; empty = the language's default |
| `terminal` | `"xdg-terminal-exec --app-id=org.omarchy.terminal"` | used by "Continue in terminal" |
| `sleepAfter` | `600` | seconds idle before an orb dozes off |
| `doneGlow` | `90` | seconds a finished agent stays happy |
| `alertMs` | `7000` | how long alerts stay open (ms) |
| `errorLoud` | `120` | seconds an error keeps shaking |
| `fontFamily` | `"Noto Sans"` | |
| `notchColor` / `cardColor` | `#000000` / `#18181B` | notch and card background |
| `claudeColor` | `#E0784F` | Claude's orb tint |
| `palette` | 10 colours | colours handed out to other agents |
| `strings` | `{}` | override any UI text by key, e.g. `{"ask.button": "✎  Hey {name}"}` |

**Customize panel.** Click **⚙ Customize** in the expanded notch (or
`qs -p /usr/share/omarchy/shell ipc call myzk.notch customize`): pick the style, accessories and colour for your
assistant or for the Grok Bots, with a live preview you can cycle through every mood and poke. Each click is saved to
`config.json` right away.

**Moods & reactions.** Faces show `idle`, `thinking`, `working`, `upload` (Claude runs `git push`, `scp`,
`rsync`, `npm publish`… or an MCP upload), `restart` (`/clear`, compaction, resume), `waiting`, `done`,
`error` and `sleep`. They also react to you: the eyes follow the cursor, three quick clicks annoy them,
six clicks or shaking the cursor over them make them dizzy. Try it with
`qs -p /usr/share/omarchy/shell ipc call myzk.notch react dizzy` (or `annoyed`). Grok Bots can report
`upload` and `restart` through `report_status` too.

**Notch inside the bar** (`"placement": "bar"`): the collapsed notch takes the bar's height and covers
its center, so nothing hangs over your browser tabs. Move whatever you have in the bar's center section
out of the way first, e.g. `omarchy bar move omarchy.clock --section left` (repeat for each center widget;
the list is under `bar.layout.center` in `~/.config/omarchy/shell.json`). Only top bars are supported.

**Texts / translations**: all strings are in [`plugin/i18n.json`](plugin/i18n.json) (shared by the UI and the
backend). Add a new language block and set `language` to it, or override single keys with `strings`.
`{name}` is replaced with `assistantName`.

**Deeper changes**: sizes and animations are in `plugin/Notch.qml` (widths near the top),
the faces in `plugin/AgentFace.qml`. After editing QML run `omarchy restart shell`.

Environment overrides: `AGENT_NOTCH_CONFIG` (config path), `AGENT_NOTCH_BACKEND` (backend path),
`AGENT_NOTCH_I18N` (strings file for the backend).

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

- Asking from the notch runs `claude -p` headless with `permissionMode` (default `auto`) — set it to `default` or `plan` if you want it more careful.
- New translations in `i18n.json` are very welcome as PRs.
- `plugin/record-demo.sh OUT.mp4` records the showcase video with fake agents (needs `gpu-screen-recorder`).

## License

MIT
