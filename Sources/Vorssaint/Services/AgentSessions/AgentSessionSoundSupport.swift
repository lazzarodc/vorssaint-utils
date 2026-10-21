// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import Foundation

enum AgentSessionSoundEvent: String, CaseIterable, Identifiable {
    case started, completed, acknowledged, approvalNeeded
    var id: String { rawValue }
    var defaultSound: String {
        switch self {
        case .started, .acknowledged: return "Off"
        case .completed: return "Glass"
        case .approvalNeeded: return "Ping"
        }
    }
}

/// Sound transitions are independent of usage notifications. The first scan
/// after launch/resume is a baseline, so existing sessions do not all announce.
struct AgentSessionSoundTracker {
    private var previous: [Int32: AgentSession]?

    mutating func reset() { previous = nil }

    mutating func update(_ agents: [AgentSession]) -> [AgentSessionSoundEvent] {
        let current = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        defer { previous = current }
        guard let previous else { return [] }
        return agents.compactMap { agent in
            guard let old = previous[agent.id], old.kind == agent.kind else { return .started }
            if agent.kind == .codex, agent.status == .waiting,
               old.transcriptPath == agent.transcriptPath,
               let completed = agent.completedTurnID, completed != old.completedTurnID {
                return .completed
            }
            switch (old.status, agent.status) {
            case (.working, .waiting): return agent.kind == .claude ? .completed : nil
            case (.waiting, .working), (.idle, .working): return .acknowledged
            default: return nil
            }
        }
    }
}

enum AgentSessionSoundPolicy {
    static func isQuiet(minute: Int, enabled: Bool, start: Int, end: Int) -> Bool {
        guard enabled, start != end else { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static func shouldAnnounceApproval(writtenAt: Date?, monitoringStartedAt: Date) -> Bool {
        guard let writtenAt else { return false }
        return writtenAt >= monitoringStartedAt
    }

    static func volume(_ value: Double) -> Float {
        value.isFinite ? Float(min(1, max(0, value))) : 0.5
    }
}
