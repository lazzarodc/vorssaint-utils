// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

/// One private Unix socket per local VS Code window. No workspace-path matching
/// or typing into an application's frontmost editor is used for this route.
enum VSCodeTerminalBridge {
    struct Registration: Decodable {
        let version: Int
        let extensionPid: Int32
        let shellPids: [Int32]
        let updatedAt: TimeInterval
    }
    struct Target: Equatable {
        let socketPath: String
        let shellPid: Int32
    }
    enum Action: String { case focus, sendText, sendKey }
    static var directory: URL { URL(fileURLWithPath: "/tmp/vorssaint-vscode-\(getuid())", isDirectory: true) }

    static func target(agentPid: Int32, parents: [Int32: Int32], registrations: [(String, Registration)], now: Date) -> Target? {
        var pid = agentPid
        var seen = Set<Int32>()
        while pid > 1, seen.insert(pid).inserted {
            let matches = registrations.filter { _, entry in
                entry.version == 1 && entry.updatedAt.isFinite
                    && (0...45).contains(now.timeIntervalSince1970 - entry.updatedAt)
                    && entry.shellPids.contains(pid)
            }
            // Ambiguous registrations (for example during a window reload) do
            // not authorize a send to whichever window happens to be first.
            if matches.count > 1 { return nil }
            if let match = matches.first { return Target(socketPath: match.0, shellPid: pid) }
            guard let parent = parents[pid] else { return nil }
            pid = parent
        }
        return nil
    }

    static func perform(_ action: Action, agentPid: Int32, text: String? = nil) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,ppid="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let table = String(data: data, encoding: .utf8) else { return false }
        let parents = table.split(separator: "\n").reduce(into: [Int32: Int32]()) { out, line in
            let values = line.split(whereSeparator: \.isWhitespace)
            if values.count == 2, let pid = Int32(values[0]), let parent = Int32(values[1]) { out[pid] = parent }
        }
        guard let target = target(agentPid: agentPid, parents: parents, registrations: registrations(), now: Date()) else { return false }
        return request(action, target: target, text: text)
    }

    private static func registrations() -> [(String, Registration)] {
        guard privateItem(directory, kind: S_IFDIR) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard file.pathExtension == "json", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  privateItem(file, kind: S_IFREG),
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65536,
                  let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(Registration.self, from: data),
                  entry.extensionPid > 1, kill(entry.extensionPid, 0) == 0 else { return nil }
            let socket = file.deletingPathExtension().appendingPathExtension("sock")
            guard privateItem(socket, kind: S_IFSOCK) else { return nil }
            return (socket.path, entry)
        }
    }

    private static func privateItem(_ url: URL, kind: mode_t) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_uid == getuid() && (info.st_mode & S_IFMT) == kind && (info.st_mode & 0o077) == 0
    }

    /// Newline-framed JSON with an acknowledgement. Bounded size and socket
    /// timeouts keep a stopped extension from blocking the caller indefinitely.
    static func request(_ action: Action, target: Target, text: String? = nil) -> Bool {
        let id = UUID().uuidString
        var payload: [String: Any] = ["version": 1, "id": id, "action": action.rawValue, "shellPid": target.shellPid]
        if let text { payload["text"] = text }
        guard var data = try? JSONSerialization.data(withJSONObject: payload), data.count < 65536 else { return false }
        data.append(10)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(target.socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, value) in path.enumerated() { buffer[index] = UInt8(bitPattern: value) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return false }
        let sent = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(fd, base.advanced(by: offset), bytes.count - offset, 0)
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard sent else { return false }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(2)
        while response.count < 65536, Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return false }
            response.append(contentsOf: buffer.prefix(count))
            guard response.count <= 65536 else { return false }
            if let newline = response.firstIndex(of: 10) {
                guard let reply = (try? JSONSerialization.jsonObject(with: response.prefix(upTo: newline))) as? [String: Any] else { return false }
                return reply["version"] as? Int == 1 && reply["id"] as? String == id && reply["ok"] as? Bool == true
            }
        }
        return false
    }
}
