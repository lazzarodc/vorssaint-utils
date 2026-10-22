// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main struct WorkTimingTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let claude = directory.appendingPathComponent("claude.jsonl")
        let codex = directory.appendingPathComponent("codex.jsonl")
        func write(_ lines: [String], to path: URL, append: Bool = false) throws {
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            if append {
                let handle = try FileHandle(forWritingTo: path)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else { try data.write(to: path) }
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(data.count))], ofItemAtPath: path.path)
        }
        let start = "2026-10-22T10:00:00.000Z"
        let end = "2026-10-22T10:02:00.000Z"
        try write([
            #"{"type":"user","uuid":"request-a","timestamp":"\#(start)","message":{"content":"same prompt"}}"#,
            #"{"type":"user","isSidechain":true,"uuid":"helper","timestamp":"\#(start)","message":{"content":"helper prompt"}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"done"}]}}}"#
        ], to: claude)
        let first = ClaudeSessions.tailInfo(path: claude.path).workTurn
        precondition(first?.id == "request-a" && first?.startedAt == AgentWorkTurn.date(start))
        let padding = #"{"type":"progress","data":""# + String(repeating: "x", count: 600_000) + #""}"#
        try write([padding, #"{"type":"progress"}"#], to: claude, append: true)
        precondition(ClaudeSessions.tailInfo(path: claude.path).workTurn?.id == "request-a",
                     "the request must survive falling outside the transcript tail")
        try write([
            #"{"type":"assistant","timestamp":"\#(end)","message":{"stop_reason":"end_turn","content":[]}}"#,
            #"{"type":"system","subtype":"turn_duration","timestamp":"\#(end)","durationMs":120000}"#
        ], to: claude, append: true)
        let finished = ClaudeSessions.tailInfo(path: claude.path).workTurn
        precondition(finished?.endedAt == AgentWorkTurn.date(end) && finished?.reportedDuration == 120)
        try write([#"{"type":"user","uuid":"request-b","timestamp":"\#(end)","message":{"content":"same prompt"}}"#], to: claude, append: true)
        let next = ClaudeSessions.tailInfo(path: claude.path).workTurn
        precondition(next?.id == "request-b" && next?.endedAt == nil && next?.reportedDuration == nil,
                     "identical user text in a new request still resets the clock")

        try write([#"{"type":"user","uuid":"request-xml","timestamp":"\#(end)","message":{"content":"<task>Explain this code</task>"}}"#], to: claude, append: true)
        precondition(ClaudeSessions.tailInfo(path: claude.path).workTurn?.id == "request-xml",
                     "a real XML or HTML user request starts a new clock")

        try write([#"{"type":"event_msg","timestamp":"\#(start)","payload":{"type":"task_started","turn_id":"a","root_turn_id":"a"}}"#], to: codex)
        precondition(CodexSessions.tailInfo(path: codex.path).workTurn?.id == "a")
        try write([padding, #"{"type":"event_msg","payload":{"type":"item_completed"}}"#], to: codex, append: true)
        let running = CodexSessions.tailInfo(path: codex.path)
        precondition(running.phase == .working && running.workTurn?.id == "a",
                     "tool completion and a truncated start must not pause an active root turn")
        try write([#"{"type":"event_msg","timestamp":"\#(end)","payload":{"type":"task_complete","turn_id":"a","root_turn_id":"a","duration_ms":120000}}"#], to: codex, append: true)
        precondition(CodexSessions.tailInfo(path: codex.path).workTurn?.reportedDuration == 120)
        try write([#"{"type":"event_msg","timestamp":"\#(end)","payload":{"type":"task_complete","turn_id":"b","root_turn_id":"b","duration_ms":4000}}"#], to: codex, append: true)
        precondition(CodexSessions.tailInfo(path: codex.path).workTurn?.id == "b",
                     "a completion whose start was missed must not inherit another turn's identity")
        print("✅ WorkTimingTests: request identity, native duration and large transcript continuity passed")
    }
}
