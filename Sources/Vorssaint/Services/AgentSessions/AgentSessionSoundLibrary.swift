// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import AppKit

/// Imported audio is machine-local content, outside settings backups. The
/// bundle-specific private container keeps Developer and release sounds apart.
struct AgentSessionSoundLibrary {
    static let customPrefix = "custom:"
    let directory: URL?

    init(directory: URL? = PrivateFileStore.containerURL?.appendingPathComponent("AgentSounds", isDirectory: true)) {
        self.directory = directory
    }

    var files: [URL] {
        guard let directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true
                    && Self.extensions.contains($0.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var names: [String] { Array(Set(files.map { $0.deletingPathExtension().lastPathComponent })).sorted() }

    func url(named name: String) -> URL? {
        files.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    @discardableResult
    func importSound(from url: URL) -> Bool {
        guard let directory, Self.extensions.contains(url.pathExtension.lowercased()),
              NSSound(contentsOf: url, byReference: false) != nil,
              let data = try? Data(contentsOf: url),
              PrivateFileStore.createDirectory(at: directory) else { return false }
        return PrivateFileStore.write(data, to: directory.appendingPathComponent(url.lastPathComponent))
    }

    @discardableResult
    func removeSound(named name: String) -> Bool {
        let owned = files.filter { $0.deletingPathExtension().lastPathComponent == name }
        for file in owned {
            do { try FileManager.default.removeItem(at: file) }
            catch { return false }
        }
        return true
    }

    private static let extensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
}
