// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

/// Accumulates active portions of one request, never the lifetime of its process.
/// Historical wall-clock seeds are marked approximate because old pauses are unknown.
struct AgentWorkClock {
    private struct State {
        var source: String?
        var turnID: String?
        var seconds: TimeInterval = 0
        var activeSince: Date?
        var observedAt: Date
        var known = false
        var estimated = false
    }
    private var states: [Int32: State] = [:]

    mutating func reset() { states = [:] }

    mutating func update(_ agents: [AgentSession], now: Date, approvals: [Int32: Date] = [:], questions: [Int32: Date] = [:]) -> [AgentSession] {
        let live = Set(agents.map(\.id))
        states = states.filter { live.contains($0.key) }
        return agents.map { input in
            var agent = input
            let turn = agent.workTurn
            let working = agent.status == .working && agent.waitingForPermission != true
                && approvals[agent.id] == nil && questions[agent.id] == nil
                && agent.pendingQuestion == nil && turn?.endedAt == nil
            let previous = states[agent.id]
            let changedTurn = previous?.turnID != nil && turn?.id != nil && previous?.turnID != turn?.id
            let changedSource = previous?.source != nil && agent.transcriptPath != nil && previous?.source != agent.transcriptPath
            var state: State
            if let previous, !changedTurn, !changedSource {
                state = previous
                if let id = turn?.id { state.turnID = id }
                if let source = agent.transcriptPath { state.source = source }
                if let active = state.activeSince, !working {
                    let boundary = approvals[agent.id] ?? questions[agent.id] ?? turn?.endedAt
                        ?? (agent.pendingQuestion == nil ? agent.stateUpdatedAt : nil) ?? now
                    state.seconds += max(0, min(now, boundary).timeIntervalSince(active))
                    state.activeSince = nil
                } else if state.activeSince == nil, working {
                    let boundary = agent.stateUpdatedAt ?? now
                    state.activeSince = min(now, max(state.observedAt, boundary))
                    if !state.known { state.estimated = true }
                    state.known = true
                }
            } else {
                state = State(source: agent.transcriptPath, turnID: turn?.id, observedAt: now)
                if working {
                    let activeSince = turn?.startedAt.map { min(now, $0) } ?? now
                    state.activeSince = activeSince
                    state.known = true
                    state.estimated = turn?.startedAt == nil || now.timeIntervalSince(activeSince) > 3
                } else if let reported = turn?.reportedDuration, reported.isFinite, reported >= 0 {
                    state.seconds = reported
                    state.known = true
                } else if let start = turn?.startedAt,
                          let end = approvals[agent.id] ?? questions[agent.id] ?? turn?.endedAt ?? agent.stateUpdatedAt {
                    state.seconds = max(0, min(now, end).timeIntervalSince(start))
                    state.known = true
                    state.estimated = true
                }
            }
            state.observedAt = now
            states[agent.id] = state
            agent.workDuration = state.known ? state.seconds + (state.activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0) : nil
            agent.workDurationEstimated = state.estimated
            return agent
        }
    }
}
