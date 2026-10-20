// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct MonitorTests {
    static func main() {
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
