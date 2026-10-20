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

## Session sounds

AI Agents settings include the reference sound mechanism: session start and
acknowledgement are Off, task completion is Glass, and Claude approval is Ping.
Sounds are enabled with volume 50%. Each event has a system/custom sound picker
and preview. Quiet hours default to disabled, with a configurable 22:00–08:00
interval. Explicit previews bypass quiet hours and the master switch.

Only interactive session transitions trigger these sounds; usage notifications
keep their existing visual path. Existing sessions stay silent on the first scan
after launch or resume. Repeated scans of the same state do not repeat a sound.
Duplicate permission events already pending on the same session do not play twice.
Disabling AI Agents or hiding Live stops playback and resets the sound baseline.

Imported AIFF, WAV, MP3, M4A and CAF files are copied into the bundle-specific
private Application Support container under `AgentSounds`. Removing an imported
sound leaves its original file untouched. Preferences follow settings backups;
audio files stay on this Mac. Reimport matching custom sound names when restoring
preferences on another Mac. Developer and normal builds have separate libraries.

`Tools/test-agent-sessions.sh` also checks sound transitions, quiet-hour boundaries,
volume bounds, audio imports, invalid-file preservation and owned-file removal.
To check playback manually, use the preview buttons and then a real working →
waiting turn and a Claude permission hook. No automated test plays audible audio.

## Acceptance run — 2026-10-20

Checked the Developer build on the target Mac using isolated Claude and Codex
CLI sessions in the same temporary project, without sending input to existing
user sessions.

- Both sessions appeared separately in the island after fixing process discovery.
  A Codex editor backend previously suppressed its interactive child, while
  terminal-less app-server processes appeared as sessions. The real scanner
  missed the test PID before the fix and found it afterward. Regression fixtures
  also cover independent TTYs and same-TTY fork helpers.
- The Claude reply field accepted an unsent draft and retained keyboard focus;
  the draft was cleared. The transcript detail showed the isolated conversation.
- The module and Claude/Codex switches could be turned off and restored. Their
  scan lifecycle is covered separately by the automated monitor tests.
- Both test cards disappeared after their CLI processes exited; existing Claude
  cards and usage cards remained visible.
- Hook installation/removal worked through settings. After removal, Claude
  settings matched their saved original JSON semantically. Sound preferences
  remained at their original values. Glass and Ping previews were invoked;
  audible playback was not independently observed.
- `./build.sh --test` passed 113,127 host checks, all 12 session suites and the
  preference cleanup/uninstall/developer isolation checks. The Developer build
  and `./build/VorssaintDeveloper --selftest` passed. The self-test required normal
  host access for memory and uptime readings denied by the execution sandbox.

Still unverified: sending replies/approvals through a native terminal, the live
approval card lifecycle, audible event playback, and sleep/wake or lock/unlock.
Computer Use refused access to iTerm. The isolated tool PTYs were identified as
VS Code, so island submission was not used to avoid typing into an unrelated
editor window. Claude produced real Bash permission prompts, but this run did
not establish their island display/clear lifecycle. Its AskUserQuestion tool was
unavailable even with the default tool set, so no real question interaction was
validated. These limitations are not counted as passing acceptance checks.
