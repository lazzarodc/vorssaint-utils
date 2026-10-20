// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

@main
struct SoundLibraryTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Bell.wav")
        let audio = Data(base64Encoded: "UklGRkQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YSAAAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA==")!
        try audio.write(to: source)
        let library = AgentSessionSoundLibrary(directory: root.appendingPathComponent("Sounds"))
        precondition(library.names.isEmpty)
        precondition(library.importSound(from: source))
        precondition(library.names == ["Bell"])
        precondition((try? Data(contentsOf: library.url(named: "Bell")!)) == audio)
        precondition(library.importSound(from: source), "reimport is safe and idempotent")
        let broken = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let invalid = broken.appendingPathComponent("Bell.wav")
        try Data("invalid audio".utf8).write(to: invalid)
        precondition(!library.importSound(from: invalid))
        precondition((try? Data(contentsOf: library.url(named: "Bell")!)) == audio, "bad imports preserve the old file")
        precondition(library.url(named: "../Bell") == nil)
        precondition(library.removeSound(named: "Bell"))
        precondition(library.names.isEmpty)
        precondition(FileManager.default.fileExists(atPath: source.path), "removal never deletes the original")
        print("✅ SoundLibraryTests: import, reimport, invalid audio and owned-file removal passed")
    }
}
