#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_dir=Sources/Vorssaint/Services/AgentSessions
run() {
    local name="$1"; shift
    local sources=()
    for file in "$@"; do sources+=("$source_dir/$file.swift"); done
    echo "▸ $name"
    swiftc "${sources[@]}" "Tests/AgentSessions/${name}Tests.swift" -o "$work/$name"
    "$work/$name"
}
run AgentDetection Agent
run QuestionParse Agent TailRead ClaudeSessions
run ProjectPath Agent TailRead ClaudeSessions
run LastPrompt Agent TailRead ClaudeSessions
run TailRead TailRead
run ProcessNaming ProcessNaming
run HookSettings HookSettings
run RolloutAssignment Agent TailRead RolloutAssignment CodexSessions
run CodexPhase Agent TailRead RolloutAssignment CodexSessions
run Conversation Agent TailRead RolloutAssignment ClaudeSessions CodexSessions
run Preview Agent
run Sound Agent AgentSessionSoundSupport
run WorkClock Agent AgentWorkClock
run WorkTiming Agent TailRead RolloutAssignment ClaudeSessions CodexSessions
echo "▸ Monitor"
swiftc "$source_dir/Agent.swift" "$source_dir/AgentSessionSoundSupport.swift" "$source_dir/AgentWorkClock.swift" "$source_dir/AgentMonitor.swift" \
    "$source_dir/ApprovalCenter.swift" "$source_dir/TerminalBridge.swift" \
    "$source_dir/ClaudeSessions.swift" "$source_dir/CodexSessions.swift" \
    "$source_dir/TailRead.swift" "$source_dir/RolloutAssignment.swift" \
    "$source_dir/ProcessNaming.swift" "$source_dir/HookSettings.swift" \
    Tests/AgentSessions/HostSupport.swift Tests/AgentSessions/MonitorTests.swift -o "$work/Monitor"
"$work/Monitor"
echo "▸ SoundLibrary"
swiftc "$source_dir/AgentSessionSoundLibrary.swift" Sources/Vorssaint/Services/PrivateFileStore.swift \
    Tests/AgentSessions/SoundLibraryTests.swift -o "$work/SoundLibrary"
"$work/SoundLibrary"
