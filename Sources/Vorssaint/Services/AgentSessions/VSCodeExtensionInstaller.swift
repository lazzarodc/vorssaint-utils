// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import Foundation

/// The settings button explicitly installs the bundled package into VS Code's
/// current default profile. It never overwrites another publisher's extension.
enum VSCodeExtensionInstaller {
    static func install() -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode"),
              let package = Bundle.main.url(forResource: "vorssaint-terminal-focus", withExtension: "vsix") else { return false }
        let task = Process()
        task.executableURL = app.appendingPathComponent("Contents/Resources/app/bin/code")
        task.arguments = ["--install-extension", package.path, "--force"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        // Installation can download VS Code metadata; do not leave a worker
        // waiting indefinitely if the editor's CLI is unresponsive.
        let deadline = Date().addingTimeInterval(30)
        while task.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if task.isRunning { task.terminate(); return false }
        return task.terminationStatus == 0
    }
}
