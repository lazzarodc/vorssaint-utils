// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main struct WorkClockTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var agent = AgentSession(id: 1, kind: .claude, cpu: 0, elapsed: "2d", status: .working, bypassPermissions: false)
        agent.workTurn = AgentWorkTurn(id: "request-a", startedAt: start)
        var clock = AgentWorkClock()
        func seconds(_ age: Double, approvals: [Int32: Date] = [:], questions: [Int32: Date] = [:]) -> TimeInterval? {
            clock.update([agent], now: start.addingTimeInterval(age), approvals: approvals, questions: questions).first?.workDuration
        }
        precondition(seconds(0) == 0)
        precondition(seconds(60) == 60, "work accrues while the request is running")
        agent.status = .waiting
        agent.stateUpdatedAt = start.addingTimeInterval(80)
        precondition(seconds(90) == 80, "the timer stops at the waiting transition")
        precondition(seconds(200) == 80, "waiting for the user must not increase work time")
        agent.status = .working
        agent.stateUpdatedAt = start.addingTimeInterval(230)
        precondition(seconds(240) == 90, "resuming continues the same request without including its pause")
        agent.status = .waiting
        agent.workTurn?.endedAt = start.addingTimeInterval(300)
        precondition(seconds(310) == 150)
        precondition(seconds(1000) == 150, "the finished request remains frozen")
        agent.status = .working
        agent.stateUpdatedAt = nil
        agent.workTurn = AgentWorkTurn(id: "request-b", startedAt: start.addingTimeInterval(1000))
        precondition(seconds(1002) == 2, "a new request starts a new timer despite the same process")
        precondition(seconds(1010, approvals: [1: start.addingTimeInterval(1005)]) == 5,
                     "a permission hook pauses work before the next status update")
        precondition(seconds(1100, approvals: [1: start.addingTimeInterval(1005)]) == 5)
        clock.reset()
        agent.status = .working
        agent.workTurn = AgentWorkTurn(id: "question", startedAt: start.addingTimeInterval(1200))
        precondition(seconds(1200) == 0)
        precondition(seconds(1210, questions: [1: start.addingTimeInterval(1205)]) == 5,
                     "a question hook pauses the clock even while the registry still says working")
        precondition(seconds(1300, questions: [1: start.addingTimeInterval(1205)]) == 5)
        clock.reset()
        agent.workTurn = AgentWorkTurn(id: "transcript-question", startedAt: start.addingTimeInterval(1400))
        _ = seconds(1400)
        agent.pendingQuestion = PendingQuestion(prompt: "Choose", options: ["A"], multiSelect: false)
        precondition(seconds(1410) == 10)
        precondition(seconds(1500) == 10, "a transcript question is also a waiting state")
        agent.pendingQuestion = nil
        clock.reset()
        agent.status = .waiting
        agent.workTurn = AgentWorkTurn(id: "finished", reportedDuration: 960)
        precondition(seconds(2000) == 960, "native historical durations do not become process uptime")
        clock.reset()
        agent.workTurn = nil
        precondition(seconds(2000) == nil, "unknown work time must not fall back to the process's two-day uptime")
        print("✅ WorkClockTests: pause, resume, completion, new requests and unknown history passed")
    }
}
