# Interactive sessions in AI Agents

The existing Vorssaint island owns the page, window, focus and presentation.
`AgentMonitor` discovers terminal processes every two seconds and enriches
Claude Code and Codex CLI sessions independently of `AgentUsageService`.
Process IDs identify cards, so sessions in the same project remain separate.
Usage, accounts, limits and completion notifications keep their existing source.
The monitor deliberately emits no second set of completion notifications.

The Live preference controls the session-first overview. Waiting sessions and
Claude hook questions/approvals appear first, even while usage history loads.
Rows show a provider mark, project/conversation with elapsed time beside its title,
and activity. Status indicators occupy a fixed column beside the detail chevrons,
outside the terminal button, so longer elapsed times do not shift them. Row and
chevron buttons share one smoothly animated row highlight without scaling, with
side insets before the provider mark and after the chevron. Their click actions
remain separate; moving over the status does not split the highlight.
Active/waiting indicators are filled green/amber; idle is a hollow
gray circle. Localized status text remains available to accessibility and hover.
Session rows have no separators; the limits footer retains its top divider.
The main row area opens the external
terminal; if none is identified, it falls back to details. The chevron is a
separate button that opens a detail without jumping to the terminal. Approval
and question controls also remain outside the terminal button. Terminal access
is additionally available as an icon in the detail. Escape returns through the host's
page-layer mechanism. Detail headers and the reply/approval area stay visible
while the conversation scrolls. Long structured questions scroll with the
conversation so every option and its custom reply remain reachable. Tasks,
subagents and plans remain available there.

Conversation messages render Markdown using the existing native Scratchpad
parser/preview: headings, lists, emphasis, links and code retain their formatting
and selectable content. In conversations the preview fits each message's height
and leaves scrolling to the transcript; the Scratchpad retains its original
independent scrolling. Parsing is repeated only when the message/language changes.
Task boxes in conversation content are read-only and never edit the transcript.
Details load up to 12 recent messages from the last 384 KB of the transcript for
both providers. Consecutive assistant messages are merged before applying the cap.

The overview uses its intrinsic content height up to the configured island
budget, with a fixed footer. The footer shows per-provider limit readings and
renewal times, with provider icons and a plain gauge button. With multiple Codex
profiles it summarizes the most constrained reported session window and names
that account in the tooltip. Missing readings stay unknown; stale readings are
dimmed and dated in the tooltip. The existing used/remaining preference applies.

The gauge opens **Limits and usage**. The panel uses full-width segmented tab
buttons, a fixed-height header that
reserves the period control's space on both tabs, and a trailing content margin
inside the scroll view to keep readings clear of the scrollbar.
Limits shows all configured accounts without account dropdowns, including
failure/staleness and refresh controls.
Session/longer-window meters align to provider marks, with percentage and renewal
on the same row. Codex resets remain explicitly associated with its default
account, including when only other profiles were added.
The resets header keeps the count beside its title and the use action on the
same row. Available reset credits list their expiration date/time and relative
expiry, soonest first; expirations within a day are highlighted. Count-only
answers do not invent dates. Confirmation and redemption handling are unchanged.
**Usage and history** contains spending, trend, models, projects and activity. The period selector
appears only there. Existing visibility and ordering preferences still filter
and order usage sections; Live now controls the dedicated overview rather than
its former position between usage cards. The OpenCode/Copilot live summary and
all existing accounting/notification services remain in use.

Layout reference: approved throwaway prototype on branch
`prototype/ai-agents-layout`, commit `75b7236c`. Prototype code stays off main;
its fictitious account/session data is not used by the native app. Claude/Codex
marks are copied from the MIT reference assets under `Resources/Images`, with
attribution in `Resources/AgentsIsland-LICENSE.txt`.

Implementation validation (2026-10-20): the full suite passed 113,143 host checks,
all 12 standalone session suites and the preference/uninstall/developer-isolation
checks. Review then caught a footer fallback that could present a weekly window
as a session allowance. Two regression checks failed before the correction;
the corrected agents suite passed all 891 checks, also covering model-scoped
windows, multiple accounts, absent readings and preserved observation dates.
Both standards and spec review were rechecked with no remaining findings.
The revised Developer build and self-test passed on macOS 27.0.1, Apple Silicon.
The native overview was opened and its session rows, status indicators and footer
were observed through accessibility. Further Computer Use reads timed out; a
process sample showed the main thread servicing its normal event loop rather
than a blocked layout. End-to-end visual verification of the new panels and
terminal input remains partial; no real user session was sent a message or
permission response during this layout validation.

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
