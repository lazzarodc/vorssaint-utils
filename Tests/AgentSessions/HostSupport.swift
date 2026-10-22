// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

// Only the host preference adapter is replaced in standalone session tests.
// Readers, monitor, approval center and terminal bridge are production sources.
enum NotchAgentSupport {
    enum Card { case live }
    static func cards(in defaults: UserDefaults) -> [Card] { defaults.bool(forKey: "hidden") ? [] : [.live] }
    enum Provider { case claude, codex }
    static func isEnabled(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: "enabled") }
    static func providers(in defaults: UserDefaults) -> [Provider] {
        [defaults.bool(forKey: "claude") ? .claude : nil,
         defaults.bool(forKey: "codex") ? .codex : nil].compactMap { $0 }
    }
}

final class AgentSessionSoundService {
    static let shared = AgentSessionSoundService()
    func update(agents: [AgentSession]) {}
    func stop() {}
    var events: [AgentSessionSoundEvent] = []
    func playEvent(_ event: AgentSessionSoundEvent) { events.append(event) }
}
