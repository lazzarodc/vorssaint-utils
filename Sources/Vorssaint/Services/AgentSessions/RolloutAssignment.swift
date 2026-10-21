// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import Foundation

/// Deciding which Codex rollout file belongs to which running process.
///
/// Codex, unlike Claude Code, keeps no pid registry, so the mapping is inferred
/// — from the file the process holds open, or failing that by matching the
/// rollout's recorded cwd. Only root conversations can be inferred by folder;
/// helper histories share their parent's folder. Cached assignments must be
/// revalidated while the process lives and retired when it exits, because
/// rollout files persist and macOS can reuse a PID.
enum RolloutAssignment {
    /// Session origin is historical: a VS Code conversation may be resumed in
    /// a CLI. Exclude spawned helpers, not conversations by their original UI.
    static func conversationCwd(_ metadata: [String: Any]) -> String? {
        if let source = metadata["source"] as? [String: Any], source["subagent"] != nil || source["internal"] != nil { return nil }
        if let source = metadata["source"] as? String, ["subagent", "internal"].contains(source) { return nil }
        return metadata["cwd"] as? String
    }

    static func cacheIsFresh(checkedAt: Date?, now: Date) -> Bool {
        guard let checkedAt else { return false }
        let age = now.timeIntervalSince(checkedAt)
        return age >= 0 && age < 30
    }

    /// Drop mappings whose process is gone.
    ///
    /// macOS recycles pids aggressively, so a retired entry is not merely
    /// stale — a new codex session can land on that pid and inherit the old
    /// session's rollout.
    static func pruned(_ cache: [Int32: String], livePids: Set<Int32>) -> [Int32: String] {
        cache.filter { livePids.contains($0.key) }
    }

    /// Pick a rollout for a session, preferring one not already claimed.
    ///
    /// `candidates` is newest-first. Falling back to the newest claimed rollout
    /// is deliberate: two codex processes in one directory is unusual, and
    /// showing the most recent conversation beats showing none. That fallback
    /// is only sound when `assigned` reflects live processes — see `pruned`.
    static func select(candidates: [String], assigned: Set<String>) -> String? {
        candidates.first { !assigned.contains($0) } ?? candidates.first
    }
}
