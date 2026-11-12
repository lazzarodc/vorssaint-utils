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
    private var titles: NotchAgentSessionSettingsStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text(.title)).font(.subheadline.weight(.medium))
            SettingsRow(symbol: "speaker.wave.2", title: titles.soundsEnabled) {
                Toggle(text(.enabled), isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(symbol: "speaker.wave.1", title: titles.soundVolume) {
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
            soundRow(titles.sessionStartedSound, event: .started)
            soundRow(titles.taskCompletedSound, event: .completed)
            soundRow(titles.taskAcknowledgedSound, event: .acknowledged)
            soundRow(titles.approvalNeededSound, event: .approvalNeeded)
            Text(text(.hookHint)).font(.caption).foregroundStyle(.secondary)

            Text(text(.quietHours)).font(.subheadline.weight(.medium))
            SettingsRow(symbol: "moon", title: titles.quietHours) {
                Toggle(text(.quietHours), isOn: $quietEnabled).labelsHidden().toggleStyle(.switch)
            }
            timeRow(titles.quietFrom, selection: $quietStart)
            timeRow(titles.quietUntil, selection: $quietEnd)
            Text(text(.quietHint)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(text(.mySounds)).font(.subheadline.weight(.medium))
            ForEach(customSounds, id: \.self) { name in
                // A file the person added names no setting, so it is not a searchable row.
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(.secondary).frame(width: 20)
                    Text(name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
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

    private func soundRow(_ title: String, event: AgentSessionSoundEvent) -> some View {
        SettingsRow(symbol: "waveform", title: title) {
            NotchAgentSoundPicker(event: event, title: title, customSounds: customSounds)
        }
    }

    private func timeRow(_ title: String, selection: Binding<Int>) -> some View {
        SettingsRow(symbol: "clock", title: title) {
            Picker(title, selection: selection) {
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
    let title: String
    let customSounds: [String]
    @ObservedObject private var l10n = L10n.shared
    @AppStorage private var selection: String

    init(event: AgentSessionSoundEvent, title: String, customSounds: [String]) {
        self.event = event
        self.title = title
        self.customSounds = customSounds
        _selection = AppStorage(wrappedValue: event.defaultSound, event.preferenceKey)
    }

    var body: some View {
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
        .onChange(of: selection) { _, name in AgentSessionSoundService.shared.preview(name) }
    }

}
