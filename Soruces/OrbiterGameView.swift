//
//  OrbiterGameView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//
import SwiftUI
import UIKit

struct OrbiterGameView: View {
    @State private var game = GameState()
    @EnvironmentObject private var scores: ScoresStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme") private var theme: Theme = .classic

    @State private var size: CGSize = .zero
    @State private var loopTask: Task<Void, Never>?   // async display-link loop

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let proxySize = proxy.size

                Color.clear
                    .onAppear {
                        size = proxySize
                        game.worldCenter = CGPoint(x: proxySize.width/2, y: proxySize.height/2)
                        game.reset(in: proxySize)
                        startLoop(size: proxySize)
                    }
                    .onDisappear { stopLoop() }
                    .onChange(of: proxy.size) {
                        size = proxy.size
                        game.worldCenter = CGPoint(x: proxy.size.width/2, y: proxy.size.height/2)
                    }

                ZStack {
                    // === Playfield rendering (no state mutations here) ===
                    TimelineView(.animation) { _ in
                        Canvas(rendersAsynchronously: true) { context, _ in
                            // Orbit ring (with near-miss flash)
                            let ringPath = Path { p in
                                p.addEllipse(in: CGRect(
                                    x: game.worldCenter.x - game.player.radius,
                                    y: game.worldCenter.y - game.player.radius,
                                    width: game.player.radius * 2,
                                    height: game.player.radius * 2
                                ))
                            }
                            let flash = game.nearMissFlash
                            let ringColor = Color.white.opacity(0.15 + 0.25 * flash)
                            context.stroke(ringPath, with: .color(ringColor), lineWidth: 2 + 1 * flash)

                            // Player
                            let playerPos = game.playerPosition()
                            let playerRect = CGRect(
                                x: playerPos.x - game.player.size,
                                y: playerPos.y - game.player.size,
                                width: game.player.size * 2,
                                height: game.player.size * 2
                            )
                            context.fill(Path(ellipseIn: playerRect), with: .color(.white))

                            // Shield halo (steady when charges > 0, pulsing during i-frames)
                            if game.shieldCharges > 0 || game.invulnerability > 0 {
                                let pulse = game.invulnerabilityPulse
                                let haloSize = game.player.size + 6 + CGFloat(pulse * 6)
                                let halo = CGRect(
                                    x: playerPos.x - haloSize,
                                    y: playerPos.y - haloSize,
                                    width: haloSize * 2, height: haloSize * 2
                                )
                                let opacity = game.invulnerability > 0 ? (0.8 - pulse * 0.3) : 0.6
                                context.stroke(Path(ellipseIn: halo),
                                               with: .color(.white.opacity(opacity)),
                                               lineWidth: 2 + CGFloat(pulse))
                            }

                            // Asteroids
                            for a in game.asteroids {
                                let rect = CGRect(x: a.pos.x - a.size, y: a.pos.y - a.size,
                                                  width: a.size*2, height: a.size*2)
                                context.fill(Path(ellipseIn: rect),
                                             with: .color(.white.opacity(0.85)))
                            }

                            // Powerups
                            for p in game.powerups {
                                let rect = CGRect(x: p.pos.x - p.size, y: p.pos.y - p.size,
                                                  width: p.size*2, height: p.size*2)
                                context.stroke(Path(ellipseIn: rect),
                                               with: .color(.white.opacity(0.9)), lineWidth: 2)
                            }

                            // Particles
                            for p in game.particles {
                                let alpha = max(0, Double(p.life))
                                let r: CGFloat = 2 + (1 - p.life) * 2
                                let rect = CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r*2, height: r*2)
                                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                            }

                            // Shockwaves (expanding rings at hit location)
                            for w in game.shockwaves {
                                let center = CGPoint(x: CGFloat(w.pos.x), y: CGFloat(w.pos.y))
                                let r = CGFloat(w.age) * w.maxRadius
                                let alpha = Double(max(0, 1 - w.age))
                                let rect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
                                context.stroke(Path(ellipseIn: rect),
                                               with: .color(.white.opacity(alpha * 0.8)),
                                               lineWidth: max(1, 3 - r * 0.02))
                            }
                        }
                    }
                    .screenShake(game.shake)

                    // === Stable input layer (does NOT move/shake) ===
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { game.inputDrag($0) }
                                .onEnded   { _ in game.endDrag() }
                        )
                }
            }

            // === HUD & overlays ===
            overlayUI
        }
        // Music & score save on phase changes
        .onChange(of: game.phase) {
            switch game.phase {
            case .playing:
                MusicLoop.shared.setScene(.game)
            case .gameOver:
                scores.add(score: game.score)
                MusicLoop.shared.setScene(.gameOver)
            case .paused:
                MusicLoop.shared.setScene(.menu)
            case .menu:
                MusicLoop.shared.setScene(.menu)
            }
        }
        // App lifecycle without Combine: pause loop when inactive, resume when active
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                // resume loop if needed
                if loopTask == nil {
                    startLoop(size: size)
                }
            case .inactive, .background:
                stopLoop()
                if game.phase == .playing {
                    game.togglePause()
                }
            @unknown default:
                break
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Overlay
    @ViewBuilder
    private var overlayUI: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Score \(game.score)")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()

                if game.shieldCharges > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.fill")
                        Text("x\(game.shieldCharges)").monospacedDigit()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel(Text("Shields \(game.shieldCharges)"))
                }

                Spacer()

                Button(action: { game.togglePause() }) {
                    Image(systemName: game.phase == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(game.phase == .paused ? "Resume" : "Pause"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            switch game.phase {
            case .menu:
                BigButton(title: "Start") { game.reset(in: size) }
            case .paused:
                PauseCard(
                    resume: { game.togglePause() },
                    restart: { game.reset(in: size) }
                )
            case .gameOver:
                GameOverCard(
                    score: game.score,
                    highScore: game.highScore,
                    restart: { game.reset(in: size) },
                    goMenu: { router.backToRoot() }
                )
            case .playing:
                EmptyView()
            }
        }
        .padding(.bottom, 24)
        .padding(.horizontal, 16)
    }

    // MARK: - Loop control
    private func startLoop(size: CGSize) {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            for await ts in DisplayLinkAsync.ticks() {
                game.update(now: ts, size: size)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }
}
