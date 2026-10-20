# Interactive sessions in AI Agents

The existing Vorssaint island owns the page, window, focus and presentation.
`AgentMonitor` discovers terminal processes every two seconds and enriches
Claude Code and Codex CLI sessions independently of `AgentUsageService`.
Process IDs identify cards, so sessions in the same project remain separate.
Usage, accounts, limits and completion notifications keep their existing source.
The monitor deliberately emits no second set of completion notifications.

The Live card preference controls the interactive session list. Sessions follow the existing card order, and appear while usage history is still loading. The host
bounds the page height and the page scrolls. The conversation chevron opens a
detail view; Escape returns through the host's page-layer mechanism. Clicking
a card or its terminal button opens the external terminal. The detail supports
conversation, tasks, subagents, plans and messages. Cards surface Claude hook
questions and approvals and offer a quick reply while waiting.

## Claude hook

Installation and removal are explicit actions in Dynamic Island → AI Agents
settings. The installer registers only Vorssaint's hook in
`~/.claude/settings.json`, backs up existing settings to
`settings.json.vorssaint-backup`, and refuses invalid JSON. Its script and event
spool live under `~/.claude/vorssaint/`. This installation is distinct from the
original Agents Island hook. Removing it preserves unrelated commands, including
commands sharing a hook entry. These external Claude settings are not Vorssaint
preferences and are not exported in a Vorssaint settings backup. Conversation
content, process IDs and the spool are transient machine state.

Terminal targeting and state heuristics follow the reference. iTerm, Terminal,
tmux, WezTerm and kitty have their respective routes; generic terminals use
activation and simulated typing into their front window. macOS Automation or
Accessibility permissions may be needed. Codex has no hook approval route.
Disabling AI Agents stops polling and hook draining; suspending the island pauses
this work too. Hiding the Live card also stops process and hook polling. A stopped scan cannot publish a late result. Provider preferences
control which registries and transcripts are read.

## Source and validation

Adapted from [Agents Island](https://github.com/mustafahalabi/agents-island),
commit `275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c`. The original MIT notice is in
`Resources/AgentsIsland-LICENSE.txt` and is included in the app bundle. Adapted
sources carry both the original attribution and the Vorssaint GPL header.

Run `Tools/test-agent-sessions.sh` for identification, transcript, hook settings,
rollout assignment and monitor lifecycle tests. The full `./build.sh --test`
also runs these suites. Run `./build.sh --test-suite=agents` for existing usage
and AI Agents regressions, `./build.sh` for the app, and
`./build/Vorssaint --selftest` for its health checks.

A build and logic tests do not demonstrate native terminal interaction. Manual
acceptance still requires checking on the target Mac:

- Claude Code and Codex CLI launched outside Vorssaint, including two sessions
  in one project, appear separately and disappear when their processes exit.
- Reply fields retain keyboard focus and submit through each supported terminal.
- Automation/Accessibility authorization and generic front-window targeting.
- Claude questions and permission requests, including a response made directly
  in the terminal and subsequent removal of the pending request.
- Disable/re-enable the module and each provider; sleep/wake or lock/unlock.
- Existing usage cards, accounts, notifications and other island tabs remain usable.

No hook installation or live terminal input is part of the automated test suites.
