// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import Foundation

/// Reading and rewriting Claude Code's `~/.claude/settings.json` to register
/// (or remove) the Vorssaint notification hook.
///
/// Split out of ApprovalCenter and kept free of any app dependencies so the
/// merge logic can be exercised directly by scripts/tests. That matters here
/// more than most places: this code rewrites a file the user did not create and
/// does not expect us to own. Their permission rules, env, and model settings
/// all live in it.
enum HookSettings {

    /// Every command we install contains this, so our entries can be found
    /// again for upgrade and uninstall without matching the exact path.
    static let marker = "/.claude/vorssaint/notify-hook.sh"

    /// Hook events we register. PermissionRequest is the rich one (carries
    /// tool_name); Notification is the fallback on older Claude versions; the
    /// AskUserQuestion pair tracks a prompt opening and being answered.
    static let events: [(name: String, matcher: String?)] = [
        ("PermissionRequest", nil),
        ("Notification", nil),
        ("PreToolUse", "AskUserQuestion"),
        ("PostToolUse", "AskUserQuestion"),
    ]

    /// What we found on disk.
    ///
    /// `unreadable` exists specifically so a settings file we cannot parse is
    /// never treated as an empty one. Merging into an empty dictionary and
    /// writing it back silently destroys everything the user had configured —
    /// which is exactly what this code used to do.
    enum Load: Equatable {
        case missing                    // no file yet — safe to create
        case parsed([String: Any])      // valid JSON object
        case unreadable                 // present but not a JSON object — do not touch

        static func == (a: Load, b: Load) -> Bool {
            switch (a, b) {
            case (.missing, .missing), (.unreadable, .unreadable): return true
            case let (.parsed(x), .parsed(y)):
                return NSDictionary(dictionary: x).isEqual(to: y)
            default: return false
            }
        }
    }

    static func load(data: Data?) -> Load {
        guard let data else { return .missing }
        // An empty file is a normal "nothing configured yet" state, not damage.
        if data.isEmpty { return .missing }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return .unreadable }
        return .parsed(root)
    }

    /// Add our hook to `root`, leaving every other key untouched. Idempotent:
    /// re-running never appends a second copy.
    static func merged(into root: [String: Any], hookPath: String) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var entries = hooks[event.name] as? [[String: Any]] ?? []
            let alreadyThere = entries.contains { containsOurHook($0) }
            if !alreadyThere {
                var entry: [String: Any] = [
                    "hooks": [["type": "command", "command": hookPath, "async": true]]
                ]
                if let matcher = event.matcher { entry["matcher"] = matcher }
                entries.append(entry)
            }
            hooks[event.name] = entries
        }

        root["hooks"] = hooks
        return root
    }

    /// Strip our hook, preserving any other hooks the user registered on the
    /// same events.
    static func removed(from root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }

        for event in events {
            guard var entries = hooks[event.name] as? [[String: Any]] else { continue }
            entries = entries.compactMap { entry in
                guard let commands = entry["hooks"] as? [[String: Any]] else { return entry }
                let remaining = commands.filter { !isOurCommand($0) }
                guard !remaining.isEmpty else { return nil }
                var kept = entry
                kept["hooks"] = remaining
                return kept
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event.name)
            } else {
                hooks[event.name] = entries
            }
        }

        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }

    private static func containsOurHook(_ entry: [String: Any]) -> Bool {
        ((entry["hooks"] as? [[String: Any]]) ?? [])
            .contains(where: isOurCommand)
    }

    private static func isOurCommand(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }

    /// Serialized the same way every time so re-running produces no diff noise
    /// in a file the user may have under version control.
    static func serialize(_ root: [String: Any]) -> Data? {
        try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
