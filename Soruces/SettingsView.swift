//
//  SettingsView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") var theme: Theme = .classic
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            Section("Feedback") {
                Toggle("Sound", isOn: $soundEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            }
        }
        .navigationTitle("Settings")
    }
}