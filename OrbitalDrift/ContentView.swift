//
//  ContentView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var scores = ScoresStore()

    var body: some View {
        NavigationStack(path: $router.path) {
            MainMenuView()
                .navigationDestination(for: AppScreen.self) { screen in
                    switch screen {
                    case .menu:
                        MainMenuView()
                    case .game:
                        OrbiterGameView()
                            .navigationBarBackButtonHidden(true)
                    case .highScores:
                        HighScoresView()
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .environmentObject(router)
        .environmentObject(scores)
    }
}

#Preview {
    ContentView()
}
