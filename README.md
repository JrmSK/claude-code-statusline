# Claude Code Statusline

A rich, two-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows everything you need at a glance.

![screenshot-placeholder](https://via.placeholder.com/800x80?text=Add+screenshot+here)

## What it shows

**Line 1 — Session info**

| Segment | Description |
|---------|-------------|
| Directory | Current working directory |
| Git branch | Branch name + diff stats (+/- lines) |
| Model | Active model (Opus, Sonnet, Haiku) |
| Effort | Reasoning effort level (low / med / high) |
| Agent | Sub-agent name when active |
| Vim mode | INSERT / NORMAL when vim mode is enabled |
| Context window | Progress bar + percentage + token counts (e.g. `ctx ████░░░░ 38% (72k/200k)`) |
| Session duration | Time since session started |

**Line 2 — Rate limits & cost** (collapses to one line if terminal is wide enough)

| Segment | Description |
|---------|-------------|
| 5h limit | 5-hour usage bar + countdown to reset |
| 7d limit | 7-day usage bar + countdown to reset |
| Sonnet limit | Sonnet-specific 7-day usage (if applicable) |
| Cost | Session cost in USD |

Progress bars change color as they fill: green < 50% < yellow < 70% < orange < 90% < red.

## Requirements

- **Claude Code** (with status line support)
- **jq** — JSON processor
- **curl** — for rate limit API calls (usually pre-installed)
- **bash** 4+

## Installation

### Quick install

```bash
git clone https://github.com/JrmSK/claude-code-statusline.git
cd claude-code-statusline
chmod +x install.sh
./install.sh
```

Then restart Claude Code.

### Manual install

1. Copy `statusline-command.sh` to `~/.claude/statusline-command.sh`
2. Make it executable: `chmod +x ~/.claude/statusline-command.sh`
3. Add this to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

### Let Claude do it

You can also ask Claude Code to install it for you:

> Install the Claude Code statusline from https://github.com/JrmSK/claude-code-statusline

Claude will clone the repo, run the installer, and configure everything.

## Platform support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Full support | OAuth token from Keychain, BSD date/stat |
| Linux | Full support | OAuth token from credentials file, GNU date/stat |
| Windows (WSL) | Should work | Same as Linux — not tested |

The script detects your platform automatically and uses the right commands. No configuration needed.

## How rate limits work

The status bar fetches your usage data from the Anthropic API using your existing Claude Code OAuth token (the same one Claude Code uses — no extra authentication needed).

- Cached for 5 minutes to avoid unnecessary API calls
- 10-minute cooldown if the API rate-limits the status bar itself
- Falls back to stale cache gracefully

**No credentials are stored in the script.** The OAuth token is read at runtime from:
1. `CLAUDE_CODE_OAUTH_TOKEN` environment variable (if set)
2. macOS Keychain (`Claude Code-credentials`)
3. `~/.claude/.credentials.json`

## Customization

The script is a single bash file. Adjust colors (ANSI codes at the top), bar widths, or segments directly. Key variables:

- Bar width: `build_bar "$pct" 20` — change `20` to make the context bar wider/narrower
- Rate limit bar width: `build_bar "$fh_int" 10` — change `10`
- Cache duration: `300` seconds (line 212) — increase to reduce API calls
- Session tracking: stored in `~/.claude/statusline-sessions/`

## Credits

Inspired by [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine).

## License

MIT
