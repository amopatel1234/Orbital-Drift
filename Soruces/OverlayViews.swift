//
//  BigButton.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

struct BigButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.horizontal, 36).padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PauseCard: View {
    let resume: () -> Void
    let restart: () -> Void
    let mainMenu: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Paused").font(.title2.bold())
            HStack {
                Button("Resume", action: resume).buttonStyle(.borderedProminent)
                Button("Restart", action: restart).buttonStyle(.bordered)
                Button("Main Menu", action: mainMenu).buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GameOverCard: View {
    let score: Int
    let highScore: Int
    let restart: () -> Void
    let goMenu: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text("Game Over").font(.title2.bold())
            Text("Score \(score)").monospacedDigit()
            Text("Best \(highScore)").monospacedDigit().foregroundStyle(.secondary)
            Button("Play Again", action: restart).buttonStyle(.borderedProminent)
            Button("Menu", action: goMenu).buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
