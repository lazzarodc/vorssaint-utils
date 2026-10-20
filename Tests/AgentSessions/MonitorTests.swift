// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct MonitorTests {
    static func main() {
        precondition(AgentMonitor.detect(args: "/usr/local/bin/claude --model opus") == .claude)
        precondition(AgentMonitor.detect(args: "node /opt/bin/codex --model=gpt-5") == .codex)
        precondition(AgentMonitor.detect(args: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        precondition(AgentMonitor.detect(args: "echo codex") == nil)
        precondition(AgentMonitor.argsModel("codex --model=gpt-5") == "gpt-5")

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
        print("✅ MonitorTests: detection, provider filtering and in-flight stop passed")
    }
}
