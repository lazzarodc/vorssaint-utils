// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island; see Resources/AgentsIsland-LICENSE.txt.
// Tests for mapping Codex processes to their rollout (transcript) files.
//
// The bug these cover: the pid → rollout cache was never pruned. Rollout files
// are never deleted, so `fileExists` never expired an entry, and macOS recycles
// pids — a new codex session landing on a retired pid inherited the previous
// session's rollout and showed its conversation. Separately, every cached
// rollout counted as "claimed" forever, so a fresh session in a directory that
// had an earlier one found its own rollout reserved by a dead pid and fell back
// to the older conversation.
//
// Compiled against the real RolloutAssignment.swift by scripts/run-tests.sh.
import Foundation

@main
struct RolloutAssignmentTests {
    static var failures = 0

    static func fail(_ message: String, _ line: Int = #line) {
        failures += 1
        print("FAIL:\(line)  \(message)")
    }

    static let roll1 = "/Users/me/.codex/sessions/2026/07/18/rollout-1.jsonl"
    static let roll2 = "/Users/me/.codex/sessions/2026/07/18/rollout-2.jsonl"
    static let roll3 = "/Users/me/.codex/sessions/2026/07/19/rollout-3.jsonl"

    static func main() {
        let folder = "/repo"
        let records: [(String, [String: Any])] = [
            (roll1, ["cwd": folder, "source": ["subagent": ["thread_spawn": [:]]]]),
            (roll2, ["cwd": folder, "source": "vscode"]),
            (roll3, ["cwd": folder, "source": "cli"])
        ]
        if RolloutAssignment.conversationCwd(["cwd": folder, "source": ["internal": "review"]]) != nil {
            fail("an internal approval/review transcript must not be assigned to the interactive session")
        }
        let rootCandidates = records.filter { RolloutAssignment.conversationCwd($0.1) == folder }.map(\.0)
        if RolloutAssignment.select(candidates: rootCandidates, assigned: []) != roll2 {
            fail("a newer helper rollout must not displace the main conversation; an IDE-origin conversation can be resumed in CLI")
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        if !RolloutAssignment.cacheIsFresh(checkedAt: now.addingTimeInterval(-2), now: now)
            || RolloutAssignment.cacheIsFresh(checkedAt: now.addingTimeInterval(-31), now: now)
            || RolloutAssignment.cacheIsFresh(checkedAt: nil, now: now) {
            fail("a live PID must revalidate its transcript binding after 30 seconds, not retain an inferred conversation forever")
        }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let largeMetadata: [String: Any] = ["type": "session_meta", "payload": [
            "cwd": folder, "source": "cli", "instructions": String(repeating: "é", count: 23_000)
        ]]
        let header = try! JSONSerialization.data(withJSONObject: largeMetadata)
        try! (header + Data("\n{\"type\":\"event_msg\"}\n".utf8)).write(to: fixture)
        if CodexSessions.metaCwd(path: fixture.path) != folder {
            fail("a root transcript with metadata larger than 16 KB must remain discoverable")
        }
        // Exercise the production cache/discovery path with a controlled clock.
        let pid: Int32 = 901
        CodexSessions.prune(livePids: [])
        func resolve(_ age: TimeInterval, _ discovered: String?, valid: Bool = true) -> String? {
            CodexSessions.resolveRollout(pid: pid, now: now.addingTimeInterval(age),
                                        isValid: { _ in valid }, discover: { discovered })
        }
        if resolve(0, roll1) != roll1 || resolve(2, roll2) != roll1 {
            fail("a fresh association should be retained until its lease expires")
        }
        if resolve(31, roll2) != roll2 {
            fail("an expired live association must discover the replacement transcript")
        }
        if resolve(62, nil) != roll2 {
            fail("an existing root transcript older than the search window must survive an empty refresh")
        }
        if resolve(93, nil, valid: false) != nil {
            fail("a missing or helper transcript must not survive an empty refresh")
        }
        CodexSessions.prune(livePids: [])
        // --- pruning retires dead pids ---------------------------------------
        let cache: [Int32: String] = [100: roll1, 200: roll2, 300: roll3]

        let afterExit = RolloutAssignment.pruned(cache, livePids: [200, 300])
        if afterExit[100] != nil { fail("exited pid 100 kept its mapping") }
        if afterExit[200] != roll2 || afterExit[300] != roll3 {
            fail("pruning dropped a live pid's mapping")
        }

        if !RolloutAssignment.pruned(cache, livePids: []).isEmpty {
            fail("no live codex processes should empty the cache")
        }
        if RolloutAssignment.pruned([:], livePids: [1, 2]).count != 0 {
            fail("pruning an empty cache should stay empty")
        }
        if RolloutAssignment.pruned(cache, livePids: [100, 200, 300]).count != 3 {
            fail("pruning dropped mappings while every pid was still alive")
        }

        // --- the pid-reuse scenario ------------------------------------------
        // pid 100 held roll1 and exited. macOS recycles 100 for a brand-new
        // codex session. After a scan prunes, 100 must have no mapping at all,
        // so the caller performs a fresh lookup instead of inheriting roll1.
        let recycled = RolloutAssignment.pruned(cache, livePids: [200, 300])
        if recycled[100] != nil {
            fail("recycled pid would inherit the previous session's rollout")
        }

        // --- the starvation scenario ------------------------------------------
        // One directory has two rollouts. roll1 (the newest) was claimed by
        // pid 100, which has since exited; roll2 was never claimed.
        let candidates = [roll1, roll2]                 // newest first
        let deadPidCache: [Int32: String] = [100: roll1]

        // Unpruned, the dead pid still holds roll1, so the new session is
        // pushed onto the older conversation. This is the bug.
        let stale = Set(deadPidCache.values)
        if RolloutAssignment.select(candidates: candidates, assigned: stale) != roll2 {
            fail("precondition: an unpruned cache should starve the new session onto roll2")
        }

        // Pruned against an empty live set, roll1 is released and the new
        // session gets the rollout it should have had.
        let live = Set(RolloutAssignment.pruned(deadPidCache, livePids: []).values)
        if RolloutAssignment.select(candidates: candidates, assigned: live) != roll1 {
            fail("after pruning, the newest free rollout should be selected")
        }

        // A rollout held by a *live* pid stays reserved — pruning must not
        // hand one session's transcript to another.
        let stillLive = Set(RolloutAssignment.pruned(deadPidCache, livePids: [100]).values)
        if RolloutAssignment.select(candidates: candidates, assigned: stillLive) != roll2 {
            fail("a live pid's rollout must stay claimed")
        }

        // --- selection basics --------------------------------------------------
        if RolloutAssignment.select(candidates: [], assigned: []) != nil {
            fail("no candidates should yield nil")
        }
        if RolloutAssignment.select(candidates: [roll1, roll2], assigned: []) != roll1 {
            fail("with nothing claimed, the newest should win")
        }
        // Genuinely contended: both claimed by *live* processes. Falling back to
        // the newest is deliberate — showing the most recent conversation beats
        // showing none.
        if RolloutAssignment.select(candidates: [roll1, roll2],
                                    assigned: [roll1, roll2]) != roll1 {
            fail("all-claimed should fall back to the newest candidate")
        }

        if failures == 0 {
            print("✅ RolloutAssignmentTests: all passed (dead pids no longer hold rollouts)")
        } else {
            print("❌ RolloutAssignmentTests: \(failures) failure(s)"); exit(1)
        }
    }
}
