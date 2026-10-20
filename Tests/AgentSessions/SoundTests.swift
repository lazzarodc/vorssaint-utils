// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct SoundTests {
    static func session(_ pid: Int32, _ status: AgentStatus) -> AgentSession {
        AgentSession(id: pid, kind: .codex, cpu: 0, elapsed: "1m", cwd: "/tmp/project",
                     status: status, terminalApp: "iTerm", tty: "ttys001", bypassPermissions: false)
    }
    static func main() {
        var tracker = AgentSessionSoundTracker()
        precondition(tracker.update([session(1, .working)]).isEmpty, "launch is silent for existing sessions")
        precondition(tracker.update([session(1, .working), session(2, .idle)]) == [.started])
        precondition(tracker.update([session(1, .waiting), session(2, .idle)]) == [.completed])
        precondition(tracker.update([session(1, .waiting), session(2, .idle)]).isEmpty, "unchanged sessions do not repeat sounds")
        precondition(tracker.update([session(1, .working), session(2, .idle)]) == [.acknowledged])
        precondition(tracker.update([session(1, .idle)]).isEmpty, "quiet CPU and process exits do not mean completion")
        tracker.reset()
        precondition(tracker.update([session(3, .waiting)]).isEmpty, "resume starts with a silent baseline")
        precondition(AgentSessionSoundEvent.completed.defaultSound == "Glass")
        precondition(AgentSessionSoundEvent.approvalNeeded.defaultSound == "Ping")
        precondition(AgentSessionSoundEvent.started.defaultSound == "Off")
        precondition(AgentSessionSoundEvent.acknowledged.defaultSound == "Off")
        for minute in [22 * 60, 23 * 60, 0, 7 * 60 + 59] {
            precondition(AgentSessionSoundPolicy.isQuiet(minute: minute, enabled: true, start: 22 * 60, end: 8 * 60))
        }
        for minute in [8 * 60, 12 * 60, 21 * 60 + 59] {
            precondition(!AgentSessionSoundPolicy.isQuiet(minute: minute, enabled: true, start: 22 * 60, end: 8 * 60))
        }
        precondition(!AgentSessionSoundPolicy.isQuiet(minute: 60, enabled: false, start: 0, end: 120))
        precondition(!AgentSessionSoundPolicy.isQuiet(minute: 60, enabled: true, start: 60, end: 60))
        precondition(AgentSessionSoundPolicy.isQuiet(minute: 60, enabled: true, start: 0, end: 120))
        precondition(AgentSessionSoundPolicy.volume(-1) == 0 && AgentSessionSoundPolicy.volume(2) == 1)
        precondition(AgentSessionSoundPolicy.volume(.nan) == 0.5)
        let start = Date(timeIntervalSince1970: 200)
        precondition(!AgentSessionSoundPolicy.shouldAnnounceApproval(writtenAt: Date(timeIntervalSince1970: 199), monitoringStartedAt: start))
        precondition(AgentSessionSoundPolicy.shouldAnnounceApproval(writtenAt: Date(timeIntervalSince1970: 201), monitoringStartedAt: start))
        precondition(!AgentSessionSoundPolicy.shouldAnnounceApproval(writtenAt: nil, monitoringStartedAt: start))
        print("✅ SoundTests: transitions, first-scan silence, defaults and quiet hours passed")
    }
}
