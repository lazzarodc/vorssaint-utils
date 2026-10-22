// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct VSCodeBridgeTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 100)
        func registration(_ pid: Int32, updated: Double = 100) -> VSCodeTerminalBridge.Registration {
            .init(version: 1, extensionPid: 999, shellPids: [pid], updatedAt: updated)
        }
        let entries = [("window-one", registration(10)), ("window-two", registration(20))]
        let target = VSCodeTerminalBridge.target(agentPid: 42, parents: [42: 41, 41: 20, 20: 2], registrations: entries, now: now)
        precondition(target == .init(socketPath: "window-two", shellPid: 20),
                     "a nested agent resolves to its shell in the correct window, without a cwd")
        precondition(VSCodeTerminalBridge.target(agentPid: 10, parents: [:], registrations: entries, now: now)?.shellPid == 10,
                     "an agent exec'd in place of its shell still resolves")
        precondition(VSCodeTerminalBridge.target(agentPid: 42, parents: [42: 41, 41: 42], registrations: entries, now: now) == nil,
                     "cyclic or exited process trees do not authorize an unrelated terminal")
        precondition(VSCodeTerminalBridge.target(agentPid: 42, parents: [42: 20], registrations: [("stale", registration(20, updated: 54))], now: now) == nil,
                     "stale registrations cannot target recycled process IDs")
        precondition(VSCodeTerminalBridge.target(agentPid: 42, parents: [42: 20], registrations: [("one", registration(20)), ("two", registration(20))], now: now) == nil,
                     "ambiguous ownership fails instead of picking the first window")
        if CommandLine.arguments.count == 2 {
            let socket = CommandLine.arguments[1]
            precondition(VSCodeTerminalBridge.request(.focus, target: .init(socketPath: socket, shellPid: 202)))
            precondition(VSCodeTerminalBridge.request(.sendText, target: .init(socketPath: socket, shellPid: 202), text: "Olá\nworld"))
            precondition(!VSCodeTerminalBridge.request(.sendKey, target: .init(socketPath: socket, shellPid: 404), text: "1"))
        }
        print("✅ VSCodeBridgeTests: process ancestry, stale sessions and ambiguous windows passed")
    }
}
