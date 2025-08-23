//
//  MainMenuView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var scores: ScoresStore
    @AppStorage("theme") var theme: Theme = .classic

    var body: some View {
        ZStack {
            // Reuse theme background if you’ve expanded Theme; fallback to gradient
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.95), location: 0),
                .init(color: Color.purple.opacity(0.2), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Orbital Drift")
                    .font(.system(size: 44, weight: .black, design: .rounded))

                Text("Best: \(scores.best)")
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button {
                        router.go(.game)
                    } label: {
                        Text("Start")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        router.go(.highScores)
                    } label: {
                        Text("High Scores")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        router.go(.settings)
                    } label: {
                        Text("Settings")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 16)
        }
    }
}