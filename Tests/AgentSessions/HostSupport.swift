// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import CoreGraphics

// Host preferences, sound output and actual window activation are replaced in
// standalone tests. Readers, monitor, approval center and routing use production sources.
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
    func playEvent(_ event: AgentSessionSoundEvent) {}
}

// Routing tests never raise a user's real window.
enum WindowActivator {
    static func activate(pid: pid_t, windowID: CGWindowID?, appName: String) {
        preconditionFailure("Window activation must not run in standalone routing tests")
    }
}
