// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import Foundation
import Combine

/// Polls the process table and Claude Code's session registry, publishing
/// the list of recognized coding agent sessions.
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    @Published private(set) var agents: [AgentSession] = []

    private let scanner: (Set<AgentKind>, () -> Bool) -> [AgentSession]

    init(scanner: ((Set<AgentKind>, () -> Bool) -> [AgentSession])? = nil) {
        self.scanner = scanner ?? Self.findAgents
    }

    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
    private var cancellation = Cancellation()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.vorssaint.agent-sessions", qos: .utility)
    private var generation = 0
    private var scanning = false
    private var enabled: Set<AgentKind> = []

    /// Called with the host's preferences, on the main thread. The usage
    /// service remains the sole source of completion notifications.
    func syncWithPreferences(in defaults: UserDefaults = .standard) {
        guard NotchAgentSupport.isEnabled(in: defaults), NotchAgentSupport.cards(in: defaults).contains(.live) else { stop(); return }
        let providers = NotchAgentSupport.providers(in: defaults)
        let wanted = Set<AgentKind>([providers.contains(.claude) ? .claude : nil,
                                    providers.contains(.codex) ? .codex : nil].compactMap { $0 })
        guard !wanted.isEmpty else { stop(); return }
        if enabled != wanted {
            generation += 1
            cancellation.cancel()
            cancellation = Cancellation()
            enabled = wanted
            agents.removeAll { !wanted.contains($0.kind) }
        }
        if wanted.contains(.claude) { ApprovalCenter.shared.start() }
        else { ApprovalCenter.shared.stop() }
        guard timer == nil else { return }
        scanNow()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
    }

    func stop() {
        generation += 1
        cancellation.cancel()
        enabled = []
        timer?.invalidate()
        timer = nil
        agents = []
        ApprovalCenter.shared.stop()
    }

    func scanNow() {
        guard !enabled.isEmpty, !scanning else { return }
        scanning = true
        let token = generation
        let providers = enabled
        let cancellation = cancellation
        queue.async { [weak self] in
            guard let self else { return }
            guard !cancellation.isCancelled else {
                DispatchQueue.main.async { self.scanning = false }
                return
            }
            let found = self.scanner(providers, { cancellation.isCancelled })
            DispatchQueue.main.async {
                self.scanning = false
                guard token == self.generation, !self.enabled.isEmpty else { return }
                if self.agents != found { self.agents = found }
                ApprovalCenter.shared.sync(agents: found)
            }
        }
    }

    // MARK: - Scanning

    private struct ProcInfo {
        let ppid: Int32
        let command: String // full path or command name (ps comm)
    }

    private static func findAgents(enabled: Set<AgentKind>, isCancelled: () -> Bool) -> [AgentSession] {

        // Full process table: pid, ppid, cpu, tty, etime, args — one pass.
        let output = run("/bin/ps", ["-axwwo", "pid=,ppid=,pcpu=,tty=,etime=,args="])
        var procs: [Int32: ProcInfo] = [:]
        var candidates: [(pid: Int32, ppid: Int32, cpu: Double, tty: String?, etime: String, args: String, kind: AgentKind)] = []

        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count == 6,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]) else { continue }
            let tty = parts[3] == "??" ? nil : String(parts[3])
            let args = String(parts[5])
            // Store the full args, not a space-split first token: app bundle
            // paths contain spaces, and truncating there lost VS Code, Cursor
            // and Windsurf entirely. See ProcessNaming.
            procs[pid] = ProcInfo(ppid: ppid, command: args)
            if let kind = detect(args: args), enabled.contains(kind), !isHeadless(tty: tty, args: args) {
                candidates.append((pid, ppid, cpu, tty, String(parts[4]), args, kind))
            }
        }

        // Drop children whose parent is the same agent (forked helpers).
        let agentKindByPid = Dictionary(uniqueKeysWithValues: candidates.map { ($0.pid, $0.kind) })
        let rows = candidates.filter {
            // Drop forked helpers of the same agent…
            agentKindByPid[$0.ppid] != $0.kind
            // …and GUI background helpers, which Electron names after the app
            // itself so they match an agent alias. See ProcessNaming.
            && !ProcessNaming.isGUIHelper(tty: $0.tty, parentCommand: procs[$0.ppid]?.command)
        }

        // Retire pid → rollout mappings for codex processes that have exited.
        // Left unpruned, a recycled pid inherits the previous session's rollout
        // and the card shows that conversation instead. See RolloutAssignment.
        CodexSessions.prune(livePids: Set(rows.filter { $0.kind == .codex }.map(\.pid)))

        guard !isCancelled() else { return [] }
        let claudeMetas = enabled.contains(.claude) ? ClaudeSessions.sessionsByPid() : [:]
        let needCwd = rows.filter { $0.kind != .claude || claudeMetas[$0.pid] == nil }.map(\.pid)
        let cwds = cwdByPid(needCwd)

        var sessions: [AgentSession] = []
        for row in rows {
            guard !isCancelled() else { return [] }
            let bypass = row.args.contains("bypassPermissions")
                || row.args.contains("--dangerously-skip-permissions")
                || row.args.contains("--yolo")
            let terminal = terminalApp(for: row.pid, procs: procs)

            var session = AgentSession(
                id: row.pid,
                kind: row.kind,
                cpu: row.cpu,
                elapsed: prettyElapsed(row.etime),
                cwd: cwds[row.pid],
                status: row.cpu > 3.0 ? .working : .idle,
                terminalApp: terminal,
                tty: row.tty,
                bypassPermissions: bypass
            )

            if row.kind == .claude, let meta = claudeMetas[row.pid] {
                session.cwd = meta.cwd
                let path = ClaudeSessions.transcriptPath(for: meta)
                session.transcriptPath = path
                let info = ClaudeSessions.tailInfo(path: path)
                // meta.name carries a hash suffix ("myproj-0d") — prefer the AI
                // title, then fall back to the clean cwd basename in the view.
                session.title = info.title
                session.lastPrompt = info.lastPrompt
                session.lastMessage = info.lastMessage
                session.model = info.model
                session.subagents = info.subagents
                session.plan = info.plan
                session.pendingQuestion = info.question
                // Task store is the current system; TodoWrite in the
                // transcript is the legacy fallback.
                let storeTasks = ClaudeSessions.tasks(sessionId: meta.sessionId)
                session.todos = storeTasks.isEmpty ? info.todos : storeTasks

                let idleAge = meta.statusUpdatedAt.map {
                    Date().timeIntervalSince1970 - $0 / 1000
                } ?? 0
                if meta.status == "busy" {
                    session.status = .working
                    session.activity = info.activity ?? "Thinking…"
                } else {
                    session.status = idleAge > 30 * 60 ? .idle : .waiting
                }
            } else if row.kind == .codex,
                      let path = CodexSessions.rolloutPath(pid: row.pid, cwd: cwds[row.pid]) {
                let info = CodexSessions.tailInfo(path: path)
                session.transcriptPath = path
                session.lastPrompt = info.lastPrompt
                session.model = info.model
                session.todos = info.todos

                let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
                let idleAge = mtime.map { Date().timeIntervalSince($0) } ?? 0
                switch info.phase {
                case .working:
                    session.status = .working
                    session.activity = info.activity ?? "Thinking…"
                case .waiting:
                    session.status = idleAge > 30 * 60 ? .idle : .waiting
                case .unknown:
                    // No task events parsed — trust the CPU heuristic, but
                    // still demote/hide long-quiet sessions by rollout age.
                    if session.status != .working {
                        session.status = idleAge > 30 * 60 ? .idle : .waiting
                    }
                }
            }

            // Model fallback from the command line (-m / --model).
            if session.model == nil { session.model = argsModel(row.args) }
            sessions.append(session)
        }


        return sessions.sorted {
            (sortRank($0.status), $0.kind.rawValue, $0.id) < (sortRank($1.status), $1.kind.rawValue, $1.id)
        }
    }

    private static func sortRank(_ status: AgentStatus) -> Int {
        switch status {
        case .working: return 0
        case .waiting: return 1
        case .idle: return 2
        }
    }

    /// Background / programmatic agents: no controlling terminal AND driven over
    /// a piped protocol (`stream-json`) or in print mode (`-p` / `--print`).
    /// These are SDK / orchestrator runs (e.g. FleetView sessions under
    /// ~/.slock/agents) — the island can neither jump to nor reply into them, and
    /// counting them inflates the session badge with sessions the user never
    /// opened in a terminal. Interactive agents always own a pty, so a live tty
    /// keeps them visible.
    private static func isHeadless(tty: String?, args: String) -> Bool {
        guard tty == nil else { return false }
        if args.contains("stream-json") || args.contains("--print") { return true }
        return args.split(separator: " ").contains("-p")
    }

    /// Model from the command line: `-m x`, `--model x`, or `--model=x`.
    static func argsModel(_ args: String) -> String? {
        let tokens = args.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            if token == "-m" || token == "--model",
               index + 1 < tokens.count, !tokens[index + 1].hasPrefix("-") {
                return tokens[index + 1]
            }
            if token.hasPrefix("--model=") { return String(token.dropFirst("--model=".count)) }
        }
        return nil
    }

    /// Recognize an agent from its full command line. Matches the executable
    /// basename directly, or the script argument when run via an interpreter.
    /// Binaries inside .app bundles are GUI apps, not CLI agents — the Claude
    /// Desktop app's binary is literally named "Claude" and would ghost in.
    static func detect(args: String) -> AgentKind? {
        let tokens = args.split(separator: " ")
        guard let first = tokens.first, !first.contains(".app/") else { return nil }
        let exe = basename(String(first))

        if let kind = AgentKind(matching: exe) { return kind }

        let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "uv", "npx"]
        if interpreters.contains(exe.lowercased()) {
            for token in tokens.dropFirst() {
                if token.hasPrefix("-") || token.contains(".app/") { continue }
                if let kind = AgentKind(matching: basename(String(token))) { return kind }
            }
        }
        return nil
    }

    /// Walk up the parent chain to find the hosting terminal / editor app.
    private static func terminalApp(for pid: Int32, procs: [Int32: ProcInfo]) -> String? {
        var current = pid
        for _ in 0..<40 {
            guard let info = procs[current], info.ppid > 1 else { return nil }
            current = info.ppid
            guard let parent = procs[current] else { return nil }

            if let appName = ProcessNaming.appBundleName(fromCommand: parent.command) {
                return appName
            }
            let base = ProcessNaming.executableBasename(parent.command)
            if ["tmux", "screen", "zellij"].contains(base) { return base }
        }
        return nil
    }

    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// One lsof call for all pids: `p<pid>` lines followed by `n<path>` lines.
    private static func cwdByPid(_ pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let output = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fn"])

        var result: [Int32: String] = [:]
        var currentPid: Int32?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// ps etime is [[dd-]hh:]mm:ss — condense to "3m", "1h 12m", "2d 4h".
    static func prettyElapsed(_ etime: String) -> String {
        var days = 0
        var rest = etime
        if let dash = rest.firstIndex(of: "-") {
            days = Int(rest[..<dash]) ?? 0
            rest = String(rest[rest.index(after: dash)...])
        }
        let comps = rest.split(separator: ":").compactMap { Int($0) }
        var hours = 0, minutes = 0
        if comps.count == 3 { hours = comps[0]; minutes = comps[1] }
        else if comps.count == 2 { minutes = comps[0] }

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }
        // Read before waiting so a full pipe buffer can't deadlock us.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
