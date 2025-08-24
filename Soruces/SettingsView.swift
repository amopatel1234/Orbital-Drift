//
//  SettingsView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("theme") var theme: Theme = .classic
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true
    @AppStorage("seenTutorial") private var seenTutorial = false
    @AppStorage("musicEnabled") private var musicEnabled: Bool = true
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.rawImageName.capitalized).tag($0) } // or .rawValue if you kept that
                }
            }
            Section("Feedback") {
                Toggle("Sound", isOn: $soundEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
            Section("Tutorial") {
                Button("View Tutorial") { router.go(.tutorial) }
                Button("Show on Next Launch") {
                    confirmReset = true
                }
                .foregroundStyle(.orange)
            }
            Section("Audio") {
                Toggle("Sound Effects", isOn: $soundEnabled)
                Toggle("Music", isOn: $musicEnabled)
                    .onChange(of: musicEnabled) { on in
                        if on { MusicLoop.shared.playIfNeeded(); MusicLoop.shared.fade(to: 0.6) }
                        else  { MusicLoop.shared.fade(to: 0);   MusicLoop.shared.stop() }
                    }
            }
            Section("About") {
                LabeledContent("Version",
                               value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Show tutorial on next launch?",
                            isPresented: $confirmReset,
                            actions: {
                                Button("Yes", role: .none) { seenTutorial = false }
                                Button("Cancel", role: .cancel) { }
                            })
    }
}

private extension Theme {
    // helper if you don’t have display names
    var rawImageName: String { rawValue }
}
