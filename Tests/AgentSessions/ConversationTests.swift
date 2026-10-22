// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct ConversationTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("session-conversation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, _ entries: [[String: Any]]) throws -> String {
            let data = try entries.map { try JSONSerialization.data(withJSONObject: $0) }
                .reduce(into: Data()) { $0.append($1); $0.append(10) }
            let file = root.appendingPathComponent(name)
            try data.write(to: file)
            return file.path
        }
        func user(_ text: String) -> [String: Any] {
            ["type": "user", "message": ["role": "user", "content": text]]
        }
        func assistant(_ text: String) -> [String: Any] {
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]
        }
        let path = try write("claude.jsonl", [
            user("Please explain **this**"), assistant("First answer"),
            user("<local-command-stdout>  **literal output**\n<keep-this>\n\n</local-command-stdout>"),
            assistant("After the command"),
            user("<command-name>/model</command-name><command-message>model</command-message><command-args>opus</command-args>"),
            user("<local-command-stderr>Command failed</local-command-stderr>"),
            ["type": "user", "message": ["content": [["type": "tool_result", "content": "tool output"]]]],
            user("<local-command-caveat>Internal instructions</local-command-caveat>"),
            user("A real follow-up"), assistant("Final"), assistant("More detail")
        ])
        let messages = ClaudeSessions.recentMessages(path: path)
        precondition(messages.map(\.source) == [.user, .assistant, .terminal, .assistant, .terminal, .terminal, .user, .assistant],
                     "conversation authors distinguish local terminal output and do not merge it into an assistant answer")
        precondition(messages[2].text == "  **literal output**\n<keep-this>\n\n" && messages[4].text == "/model opus"
                     && messages[5].text == "Command failed" && messages.last?.text == "Final\n\nMore detail",
                     "only transport tags are removed; output syntax and assistant grouping survive")
        precondition(ClaudeSessions.recentMessages(path: path, limit: 2).map(\.source) == [.user, .assistant],
                     "the recent-message cap still applies after source classification")
        let codex = try write("codex.jsonl", [
            ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Question"]]]],
            ["type": "response_item", "payload": ["type": "function_call_output", "output": "shell output"]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Answer"]]]]
        ])
        precondition(CodexSessions.recentMessages(path: codex).map(\.source) == [.user, .assistant],
                     "Codex tool output is not attributed to the user or assistant")
        precondition(CodexSessions.tailInfo(path: codex).lastMessage == "Answer",
                     "the Codex list preview receives the assistant response already visible in details")
        let largeResult = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
            "type": "function_call_output", "output": String(repeating: "x", count: 600_000)]])
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: codex))
        try handle.seekToEnd()
        try handle.write(contentsOf: largeResult + Data([10]))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: codex)
        let afterLargeResult = CodexSessions.tailInfo(path: codex)
        precondition(afterLargeResult.lastMessage == "Answer" && afterLargeResult.lastPrompt == "Question",
                     "large appended tool results cannot erase an already observed preview or prompt")
        let replacement = try write("codex.jsonl", [
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "  New answer\n"]]],
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": " \n"]]],
            ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Next question"]]],
            ["type": "function_call_output", "output": "tool result"]
        ])
        let replacedInfo = CodexSessions.tailInfo(path: replacement)
        precondition(replacedInfo.lastMessage == "New answer" && replacedInfo.lastPrompt == "Next question",
                     "flat messages update the preview; empty assistant text, user text and tools cannot replace the answer")
        let truncated = try write("codex.jsonl", [["type": "event_msg", "payload": ["type": "task_started"]]])
        precondition(CodexSessions.tailInfo(path: truncated).lastMessage == nil,
                     "a truncated transcript cannot inherit a cached assistant response")
        print("✅ ConversationTests: authors, terminal output, tool filtering and recent-message cap passed")
    }
}
