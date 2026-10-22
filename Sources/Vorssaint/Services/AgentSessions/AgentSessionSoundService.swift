// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import AppKit

extension AgentSessionSoundEvent {
    var preferenceKey: String {
        switch self {
        case .started: return DefaultsKey.notchAgentsSoundSessionStart
        case .completed: return DefaultsKey.notchAgentsSoundTaskComplete
        case .acknowledged: return DefaultsKey.notchAgentsSoundAcknowledge
        case .approvalNeeded: return DefaultsKey.notchAgentsSoundApprovalNeeded
        }
    }
}

/// Playback follows the reference's event sounds, volume, preview and quiet
/// hours. It does not post notifications or listen to usage completion events.
final class AgentSessionSoundService {
    static let shared = AgentSessionSoundService()
    static let off = "Off"
    private var current: NSSound?
    private var tracker = AgentSessionSoundTracker()
    private let defaults = UserDefaults.standard
    let library = AgentSessionSoundLibrary()

    func update(agents: [AgentSession]) {
        for event in tracker.update(agents, approvalPids: Set(ApprovalCenter.shared.pending.keys)) { playEvent(event) }
    }

    func stop() {
        tracker.reset()
        stopPlaying()
    }

    func stopPlaying() {
        current?.stop()
        current = nil
    }

    func playEvent(_ event: AgentSessionSoundEvent) {
        guard NotchAgentSupport.isEnabled(), NotchAgentSupport.cards().contains(.live),
              defaults.bool(forKey: DefaultsKey.notchAgentsSoundsEnabled), !inQuietHours else { return }
        play(defaults.string(forKey: event.preferenceKey) ?? event.defaultSound)
    }

    /// Explicit previews bypass the master switch and quiet hours, as in the
    /// reference, and use the configured volume.
    func preview(_ name: String) { play(name) }

    private func play(_ name: String) {
        guard name != Self.off else { return }
        let sound: NSSound?
        if name.hasPrefix(AgentSessionSoundLibrary.customPrefix) {
            sound = library.url(named: String(name.dropFirst(AgentSessionSoundLibrary.customPrefix.count)))
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
        } else {
            sound = NSSound(named: name)
        }
        guard let sound else { return }
        sound.volume = AgentSessionSoundPolicy.volume(defaults.double(forKey: DefaultsKey.notchAgentsSoundVolume))
        stopPlaying()
        if sound.isPlaying { sound.stop() }
        current = sound
        sound.play()
    }

    private var inQuietHours: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return AgentSessionSoundPolicy.isQuiet(minute: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            enabled: defaults.bool(forKey: DefaultsKey.notchAgentsQuietHoursEnabled),
            start: min(1439, max(0, defaults.integer(forKey: DefaultsKey.notchAgentsQuietHoursStart))),
            end: min(1439, max(0, defaults.integer(forKey: DefaultsKey.notchAgentsQuietHoursEnd))))
    }

    static var systemSounds: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
            .map { ($0 as NSString).deletingPathExtension }.sorted()
    }
}
