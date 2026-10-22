// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct MonitorTests {
    static func main() {
        var awaiting = AgentSession(id: 777, kind: .claude, cpu: 0, elapsed: "2m", cwd: "/tmp/test",
                                    status: .waiting, terminalApp: "iTerm", tty: "ttys001", bypassPermissions: false)
        let approval = ApprovalCenter.Approval(sessionId: "test", message: "approval required",
            toolName: "Write", at: Date(), activityAtCreate: "Writing file")
        let center = ApprovalCenter(initialApprovals: [awaiting.id: approval])
        center.sync(agents: [awaiting])
        precondition(center.pending[awaiting.id] != nil,
                     "a Claude session waiting for permission must keep its approval controls after a scan")
        awaiting.status = .working
        awaiting.activity = "Running next tool"
        center.sync(agents: [awaiting])
        precondition(center.pending[awaiting.id] == nil, "work resuming clears an approval answered in the terminal")
        let unchanged = ApprovalCenter(initialApprovals: [awaiting.id: approval])
        awaiting.activity = approval.activityAtCreate
        unchanged.sync(agents: [awaiting])
        precondition(unchanged.hasPending, "the hook can precede the registry waiting state; unchanged work must not drop it")
        unchanged.sync(agents: [])
        precondition(!unchanged.hasPending, "a session that exits must drop its pending approval")
        let stale = ApprovalCenter.Approval(sessionId: "old", message: "old", toolName: "Write",
                                          at: Date().addingTimeInterval(-601), activityAtCreate: nil)
        let expired = ApprovalCenter(initialApprovals: [awaiting.id: stale])
        awaiting.status = .waiting
        expired.sync(agents: [awaiting])
        precondition(!expired.hasPending, "stale approvals expire even while the session is waiting")
        precondition(ApprovalCenter.Action.deny.key == "\u{1B}", "denial cancels with Escape instead of choosing a variable numbered option")
        let early = ApprovalCenter.Approval(sessionId: "early", message: "permission", toolName: "Write",
                                            at: Date(), activityAtCreate: nil)
        var firstScan = awaiting
        firstScan.status = .working
        firstScan.activity = "Thinking…"
        firstScan.waitingForPermission = false
        firstScan.stateUpdatedAt = early.at.addingTimeInterval(-1)
        let beforeRegistry = ApprovalCenter(initialApprovals: [firstScan.id: early])
        beforeRegistry.sync(agents: [firstScan])
        precondition(beforeRegistry.hasPending, "the first busy scan predating the hook must not erase the approval")
        firstScan.status = .waiting
        firstScan.waitingForPermission = true
        firstScan.stateUpdatedAt = early.at.addingTimeInterval(0.1)
        beforeRegistry.sync(agents: [firstScan])
        precondition(beforeRegistry.hasPending, "explicit permission wait keeps the approval")
        firstScan.waitingForPermission = false
        firstScan.stateUpdatedAt = early.at.addingTimeInterval(1)
        beforeRegistry.sync(agents: [firstScan])
        precondition(!beforeRegistry.hasPending, "an answer that finishes between scans must retire the approval while still waiting")
        let alreadyAnswered = ApprovalCenter(initialApprovals: [firstScan.id: early])
        alreadyAnswered.sync(agents: [firstScan])
        precondition(!alreadyAnswered.hasPending, "a resolved registry state newer than the hook retires an already-answered request")
        let legacy = ClaudeSessions.Meta(pid: firstScan.id, sessionId: "legacy", cwd: "/tmp/test", name: nil,
                                        status: "idle", statusUpdatedAt: nil, waitingFor: nil)
        precondition(legacy.waitingForPermission == nil, "missing waitingFor is unknown, not a resolved permission")
        firstScan.waitingForPermission = legacy.waitingForPermission
        let legacyApproval = ApprovalCenter(initialApprovals: [firstScan.id: early])
        legacyApproval.sync(agents: [firstScan])
        precondition(legacyApproval.hasPending, "a legacy idle timestamp newer than the hook must not erase the request")
        let runningNames: [String?] = ["Xcode", "iTerm2", nil, "Visual Studio Code"]
        guard TerminalBridge.activationTargetIndex(appNamed: "VS Code", runningNames: runningNames) == 3,
              TerminalBridge.activationTargetIndex(appNamed: "VS Code", runningNames: ["Xcode", "iTerm2"]) == nil,
              TerminalBridge.activationTargetIndex(appNamed: "Cursor", runningNames: ["Cursor"]) == 0 else {
            print("FAIL: VS Code jump must resolve the running editor's real name without targeting Xcode or iTerm")
            exit(1)
        }
        precondition(AgentMonitor.detect(args: "/usr/local/bin/claude --model opus") == .claude)
        precondition(AgentMonitor.detect(args: "node /opt/bin/codex --model=gpt-5") == .codex)
        precondition(AgentMonitor.detect(args: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        precondition(AgentMonitor.detect(args: "echo codex") == nil)
        precondition(AgentMonitor.argsModel("codex --model=gpt-5") == "gpt-5")

        let table = """
        900 1 0.0 ?? 00:03 /Applications/Code.app/Contents/MacOS/Electron
        901 900 0.0 ?? 00:02 /usr/local/bin/codex --app-server-helper
        902 901 0.0 ttys005 00:01 /usr/local/bin/codex --cd /tmp/project
        903 1 0.0 ttys006 00:01 /usr/local/bin/codex
        904 903 0.0 ttys006 00:01 /usr/local/bin/codex
        905 1 0.0 ?? 00:01 /usr/local/bin/codex app-server
        """
        let candidates = AgentMonitor.processTable(table, enabled: [.codex]).candidates.map(\.pid)
        precondition(candidates == [902, 903], "interactive children survive headless/editor parents; backend servers and fork helpers stay hidden")
        let nested = """
        910 1 0.0 ttys008 00:02 codex
        911 910 0.0 ttys009 00:01 codex
        """
        precondition(AgentMonitor.processTable(nested, enabled: [.codex]).candidates.map(\.pid) == [910, 911],
                     "independent terminal sessions must not be deduplicated by provider alone")
        let domain = "com.vorssaint.tests.sessions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "enabled")
        defaults.set(true, forKey: "codex")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let monitor = AgentMonitor { kinds, _ in
            precondition(kinds == [.codex], "disabled Claude must not be read")
            entered.signal()
            release.wait()
            finished.signal()
            return [Int32(123), 124].map { pid in
                AgentSession(id: pid, kind: .codex, cpu: 0, elapsed: "1m", cwd: "/tmp/project",
                             status: .waiting, terminalApp: "Terminal", tty: "ttys001", bypassPermissions: false)
            }
        }
        monitor.syncWithPreferences(in: defaults)
        precondition(entered.wait(timeout: .now() + 3) == .success)
        monitor.stop()
        release.signal()
        precondition(finished.wait(timeout: .now() + 3) == .success)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(monitor.agents.isEmpty, "a stopped scan cannot republish its result")
        defaults.set(false, forKey: "enabled")
        monitor.syncWithPreferences(in: defaults)
        monitor.scanNow()
        precondition(entered.wait(timeout: .now() + 0.1) == .timedOut, "disabled module must not scan")
        defaults.set(true, forKey: "enabled")
        defaults.set(true, forKey: "hidden")
        monitor.syncWithPreferences(in: defaults)
        precondition(entered.wait(timeout: .now() + 0.1) == .timedOut, "hidden live card must not scan")
        defaults.set(false, forKey: "hidden")
        monitor.syncWithPreferences(in: defaults)
        precondition(entered.wait(timeout: .now() + 3) == .success)
        release.signal()
        precondition(finished.wait(timeout: .now() + 3) == .success)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(monitor.agents.map(\.id) == [123, 124], "two sessions in one project stay separate after resume")
        monitor.stop()
        print("✅ MonitorTests: detection, editor activation routing, provider filtering and in-flight stop passed")
    }
}
