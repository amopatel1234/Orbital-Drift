//
//  OrbiterGameView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//
import SwiftUI
import UIKit

// MARK: - Main Game View

struct OrbiterGameView: View {
    @State private var game = GameState()
    @EnvironmentObject private var scores: ScoresStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var size: CGSize = .zero
    @State private var loopTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let proxySize = proxy.size

                ZStack {
                    // Split the big Canvas into smaller composable canvases
                    PlayfieldCanvas(game: game)
                    EnemiesCanvas(game: game)
                    BulletsCanvas(game: game)
                    FXCanvas(game: game)
                }
                .screenShake(game.shake)
                .contentShape(Rectangle()) // for gestures
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { game.inputDrag($0) }
                        .onEnded { _ in game.endDrag() }
                )
                .onAppear {
                    size = proxySize
                    game.worldCenter = CGPoint(x: proxySize.width / 2, y: proxySize.height / 2)
                    game.reset(in: proxySize)
                    startLoop(size: proxySize)
                }
                .onChange(of: proxy.size) {
                    size = proxy.size
                    game.worldCenter = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .onDisappear {
                    stopLoop()
                }
            }

            overlayUI
        }
        .onChange(of: game.phase) {
            switch game.phase {
            case .playing:  MusicLoop.shared.setScene(.game)
            case .gameOver: scores.add(score: game.score); MusicLoop.shared.setScene(.gameOver)
            case .paused:   MusicLoop.shared.setScene(.menu)
            case .menu:     MusicLoop.shared.setScene(.menu)
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                if loopTask == nil { startLoop(size: size) }
            case .inactive, .background:
                stopLoop()
                if game.phase == .playing { game.togglePause() }
            @unknown default: break
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Overlay (your existing code)

    @ViewBuilder
    private var overlayUI: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Score \(game.score)")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()

                if game.scoreMultiplier > 1.0 {
                    Text(String(format: "x%.2f", game.scoreMultiplier))
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel(Text("Multiplier \(String(format: "%.2f", game.scoreMultiplier))"))
                }

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
                    restart: { game.reset(in: size) },
                    mainMenu: { router.backToRoot()}
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

// MARK: - Small Canvas Views (split to keep the compiler happy)

private struct PlayfieldCanvas: View {
    let game: GameState
    var body: some View {
        Canvas { context, _ in
            // Orbit ring
            let ringRect = CGRect(
                x: game.worldCenter.x - game.player.radius,
                y: game.worldCenter.y - game.player.radius,
                width: game.player.radius * 2,
                height: game.player.radius * 2
            )
            let ringPath = Path(ellipseIn: ringRect)
            let flash = game.nearMissFlash
            let ringColor = Color.white.opacity(0.15 + 0.25 * flash)
            context.stroke(ringPath, with: .color(ringColor), lineWidth: 2 + 1 * flash)

            // Player
            let playerPos = game.playerPosition()
            let pr = game.player.size
            let playerRect = CGRect(x: playerPos.x - pr, y: playerPos.y - pr, width: pr * 2, height: pr * 2)
            context.fill(Path(ellipseIn: playerRect), with: .color(.white))

            // Shield halo
            if game.shieldCharges > 0 || game.invulnerability > 0 {
                let pulse = game.invulnerabilityPulse
                let haloSize = pr + 6 + CGFloat(pulse * 6)
                let haloRect = CGRect(x: playerPos.x - haloSize, y: playerPos.y - haloSize, width: haloSize * 2, height: haloSize * 2)
                let opacity = game.invulnerability > 0 ? (0.8 - pulse * 0.3) : 0.6
                context.stroke(Path(ellipseIn: haloRect),
                               with: .color(.white.opacity(opacity)),
                               lineWidth: 2 + CGFloat(pulse))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EnemiesCanvas: View {
    let game: GameState
    var body: some View {
        Canvas { context, _ in
            // Asteroids / Enemies
            for a in game.asteroids where a.alive {
                let rect = CGRect(x: a.pos.x - a.size, y: a.pos.y - a.size, width: a.size * 2, height: a.size * 2)
                context.fill(Path(ellipseIn: rect), with: .color(a.type.color))
            }
            // Powerups
            for p in game.powerups {
                let rect = CGRect(x: p.pos.x - p.size, y: p.pos.y - p.size, width: p.size * 2, height: p.size * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct BulletsCanvas: View {
    let game: GameState
    var body: some View {
        Canvas { context, _ in
            for b in game.bullets {
                // velocity-aligned streak
                let v = b.vel.normalized()
                let lead: CGFloat = 6
                let trail: CGFloat = 10
                let center = CGPoint(x: CGFloat(b.pos.x), y: CGFloat(b.pos.y))
                let p1 = CGPoint(x: center.x - v.x * trail, y: center.y - v.y * trail)
                let p2 = CGPoint(x: center.x + v.x * lead,  y: center.y + v.y * lead)
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FXCanvas: View {
    let game: GameState
    var body: some View {
        Canvas { context, _ in
            // Particles
            for p in game.particles {
                let alpha = max(0, Double(p.life))
                let r: CGFloat = 2 + (1 - p.life) * 2
                let rect = CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(alpha)))
            }

            // Shockwaves
            for w in game.shockwaves {
                let center = CGPoint(x: CGFloat(w.pos.x), y: CGFloat(w.pos.y))
                let r = CGFloat(w.age) * w.maxRadius
                let alpha = Double(max(0, 1 - w.age))
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect),
                               with: .color(.white.opacity(alpha * 0.8)),
                               lineWidth: max(1, 3 - r * 0.02))
            }

            // +points toasts
            for t in game.toasts {
                let prog = max(0, min(1, t.age / t.lifetime))
                let rise: CGFloat = 28
                let pos = CGPoint(x: CGFloat(t.pos.x), y: CGFloat(t.pos.y) - rise * prog)

                // scale pop (ease-out-back-ish)
                let popPhase = min(prog / 0.25, 1)
                let scale = 0.9 + (1 - pow(1 - popPhase, 3)) * 0.25
                let opacity = 1 - Double(prog)

                let label = Text("+\(t.value)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(t.color)

                context.opacity = opacity

                // Scale around `pos`
                context.translateBy(x: pos.x, y: pos.y)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -pos.x, y: -pos.y)

                context.draw(label, at: pos, anchor: .center)

                // Reset transform
                context.translateBy(x: pos.x, y: pos.y)
                context.scaleBy(x: 1/scale, y: 1/scale)
                context.translateBy(x: -pos.x, y: -pos.y)

                context.opacity = 1
            }
        }
        .allowsHitTesting(false)
    }
}
