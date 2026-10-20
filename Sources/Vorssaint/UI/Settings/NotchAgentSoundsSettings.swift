// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Portions Copyright (c) 2026 Mustafa Halabi and Mohammad Hammoud (MIT).
// Adapted from Agents Island, commit 275f5e8bb7984dc25fc0b9ed10b48d1eecb3603c.
// See Resources/AgentsIsland-LICENSE.txt for the original license.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchAgentSoundsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsSoundsEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchAgentsSoundVolume) private var volume = 0.5
    @AppStorage(DefaultsKey.notchAgentsQuietHoursEnabled) private var quietEnabled = false
    @AppStorage(DefaultsKey.notchAgentsQuietHoursStart) private var quietStart = 22 * 60
    @AppStorage(DefaultsKey.notchAgentsQuietHoursEnd) private var quietEnd = 8 * 60
    @State private var customSounds: [String] = []
    @State private var fileFailed = false
    private let service = AgentSessionSoundService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text(.title)).font(.subheadline.weight(.medium))
            SettingsRow(symbol: "speaker.wave.2", title: text(.enabled)) {
                Toggle(text(.enabled), isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(symbol: "speaker.wave.1", title: text(.volume)) {
                HStack(spacing: 8) {
                    Slider(value: $volume, in: 0...1) { editing in
                        if !editing {
                            let name = UserDefaults.standard.string(forKey: DefaultsKey.notchAgentsSoundTaskComplete) ?? "Glass"
                            service.preview(name == AgentSessionSoundService.off ? "Glass" : name)
                        }
                    }.frame(width: 130).accessibilityLabel(text(.volume))
                    Text(volume.formatted(.percent.precision(.fractionLength(0)).locale(l10n.language.formattingLocale())))
                        .font(.caption).monospacedDigit().frame(width: 42, alignment: .trailing)
                }
            }
            ForEach(AgentSessionSoundEvent.allCases) { event in
                NotchAgentSoundPicker(event: event, customSounds: customSounds)
            }
            Text(text(.hookHint)).font(.caption).foregroundStyle(.secondary)

            Text(text(.quietHours)).font(.subheadline.weight(.medium))
            SettingsRow(symbol: "moon", title: text(.quietHours)) {
                Toggle(text(.quietHours), isOn: $quietEnabled).labelsHidden().toggleStyle(.switch)
            }
            timeRow(.from, selection: $quietStart)
            timeRow(.until, selection: $quietEnd)
            Text(text(.quietHint)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(text(.mySounds)).font(.subheadline.weight(.medium))
            ForEach(customSounds, id: \.self) { name in
                SettingsRow(symbol: "waveform", title: name) {
                    HStack {
                        Button { service.preview(AgentSessionSoundLibrary.customPrefix + name) } label: {
                            Image(systemName: "play.circle")
                        }.help(text(.preview)).accessibilityLabel(text(.preview))
                        Button {
                            service.stopPlaying()
                            fileFailed = !service.library.removeSound(named: name)
                            customSounds = service.library.names
                        } label: { Image(systemName: "trash") }
                            .help(text(.remove)).accessibilityLabel(text(.remove))
                    }
                }
            }
            Button(text(.addSound), action: importSound)
            if fileFailed { Text(text(.fileFailed)).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { customSounds = service.library.names }
        .onChange(of: enabled) { _, on in if !on { service.stopPlaying() } }
    }

    private func text(_ key: NotchAgentSoundText) -> String {
        NotchAgentStrings.sound(key, language: l10n.language)
    }

    private func timeRow(_ key: NotchAgentSoundText, selection: Binding<Int>) -> some View {
        SettingsRow(symbol: "clock", title: text(key)) {
            Picker(text(key), selection: selection) {
                ForEach(0..<48, id: \.self) { slot in
                    Text(String(format: "%02d:%02d", locale: l10n.language.formattingLocale(), slot / 2, (slot % 2) * 30))
                        .tag(slot * 30)
                }
            }.labelsHidden().fixedSize().disabled(!quietEnabled)
        }
    }

    private func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        fileFailed = false
        for url in panel.urls where !service.library.importSound(from: url) { fileFailed = true }
        customSounds = service.library.names
    }
}

private struct NotchAgentSoundPicker: View {
    let event: AgentSessionSoundEvent
    let customSounds: [String]
    @ObservedObject private var l10n = L10n.shared
    @AppStorage private var selection: String

    init(event: AgentSessionSoundEvent, customSounds: [String]) {
        self.event = event
        self.customSounds = customSounds
        _selection = AppStorage(wrappedValue: event.defaultSound, event.preferenceKey)
    }

    var body: some View {
        SettingsRow(symbol: "waveform", title: title) {
            HStack(spacing: 8) {
                Picker(title, selection: $selection) {
                    Text(FeatureStrings.notchAgents(l10n.language).off).tag(AgentSessionSoundService.off)
                    ForEach(customSounds, id: \.self) { name in
                        Text("♪ " + name).tag(AgentSessionSoundLibrary.customPrefix + name)
                    }
                    ForEach(AgentSessionSoundService.systemSounds, id: \.self) { name in Text(name).tag(name) }
                }.labelsHidden().frame(width: 130)
                Button { AgentSessionSoundService.shared.preview(selection) } label: {
                    Image(systemName: "play.circle")
                }
                .help(NotchAgentStrings.sound(.preview, language: l10n.language))
                .accessibilityLabel(NotchAgentStrings.sound(.preview, language: l10n.language))
                .disabled(selection == AgentSessionSoundService.off)
            }
        }
        .onChange(of: selection) { _, name in AgentSessionSoundService.shared.preview(name) }
    }

    private var title: String {
        let key: NotchAgentSoundText
        switch event {
        case .started: key = .started
        case .completed: key = .completed
        case .acknowledged: key = .acknowledged
        case .approvalNeeded: key = .approvalNeeded
        }
        return NotchAgentStrings.sound(key, language: l10n.language)
    }
}
