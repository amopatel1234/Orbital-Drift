//
//  OrbiterGameView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//
import SwiftUI
import UIKit

struct OrbiterGameView: View {
    @StateObject private var game = GameState()
    @EnvironmentObject private var scores: ScoresStore
    @EnvironmentObject private var router: AppRouter
    @State private var size: CGSize = .zero
    
    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let proxySize = proxy.size
                
                // Setup/resize
                Color.clear
                    .onAppear {
                        size = proxySize
                        game.worldCenter = CGPoint(x: proxySize.width/2, y: proxySize.height/2)
                        game.reset(in: proxySize)
                    }
                    .onChange(of: proxy.size) { newValue in
                        size = newValue
                        game.worldCenter = CGPoint(x: newValue.width/2, y: newValue.height/2)
                    }
                
                // === Playfield ===
                ZStack {
                    // 1) Canvas can shake freely
                    TimelineView(.animation) { timeline in
                        Canvas(rendersAsynchronously: true) { context, _ in
                            // Orbit ring (with near-miss flash)
                            let ringPath = Path { p in
                                p.addEllipse(in: CGRect(x: game.worldCenter.x - game.player.radius,
                                                        y: game.worldCenter.y - game.player.radius,
                                                        width: game.player.radius*2,
                                                        height: game.player.radius*2))
                            }
                            let flash = game.nearMissFlash
                            let ringColor = Color.white.opacity(0.15 + 0.25 * flash)
                            context.stroke(ringPath, with: .color(ringColor), lineWidth: 2 + 1 * flash)
                            
                            // Player
                            let playerPos = game.playerPosition()
                            let playerRect = CGRect(x: playerPos.x - game.player.size,
                                                    y: playerPos.y - game.player.size,
                                                    width: game.player.size*2, height: game.player.size*2)
                            context.fill(Path(ellipseIn: playerRect), with: .color(.white))

                            // Shield halo (when you have at least 1 charge OR invulnerable)
                            if game.shieldCharges > 0 || game.invulnerability > 0 {
                                let pulse = game.invulnerabilityPulse
                                let haloSize = game.player.size + 6 + CGFloat(pulse * 6) // expand with pulse
                                let halo = CGRect(x: playerPos.x - haloSize,
                                                  y: playerPos.y - haloSize,
                                                  width: haloSize*2, height: haloSize*2)

                                let opacity = game.invulnerability > 0
                                    ? 0.8 - (pulse * 0.3)    // stronger pulsing halo
                                    : 0.6                    // static if just shielded
                                context.stroke(Path(ellipseIn: halo),
                                               with: .color(.white.opacity(opacity)),
                                               lineWidth: 2 + CGFloat(pulse))
                            }
                            
                            // Asteroids
                            for a in game.asteroids {
                                let rect = CGRect(x: a.pos.x - a.size, y: a.pos.y - a.size,
                                                  width: a.size*2, height: a.size*2)
                                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)))
                            }
                            
                            // Powerups
                            for p in game.powerups {
                                let rect = CGRect(x: p.pos.x - p.size, y: p.pos.y - p.size,
                                                  width: p.size*2, height: p.size*2)
                                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 2)
                            }
                            
                            // Particles
                            for p in game.particles {
                                let alpha = max(0, Double(p.life))
                                let r: CGFloat = 2 + (1 - p.life) * 2
                                let rect = CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r*2, height: r*2)
                                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                            }
                            
                            // Shockwaves (expanding rings)
                            for w in game.shockwaves {
                                let r = CGFloat(w.age) * w.maxRadius
                                let alpha = Double(max(0, 1 - w.age))
                                let rect = CGRect(x: game.playerPosition().x - r,
                                                  y: game.playerPosition().y - r,
                                                  width: r * 2, height: r * 2)
                                context.stroke(Path(ellipseIn: rect),
                                               with: .color(.white.opacity(alpha * 0.8)),
                                               lineWidth: max(1, 3 - r * 0.02))
                            }
                        }
                        .onChange(of: timeline.date) { newDate in
                            // Keep the sim ticking with a clamped dt
                            let now = newDate.timeIntervalSinceReferenceDate
                            game.update(now: now, size: proxySize)
                            // Safety: ensure we never get stuck off-playing on near-miss
                            if game.nearMissFlash > 0, game.phase != .playing {
                                game.phase = .playing
                            }
                        }
                    }
                    .screenShake(game.shake)
                    
                    // Stable input layer
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { game.inputDrag($0) }
                                .onEnded   { _ in game.endDrag() }   // <— add this
                        )
                }
            }
            
            // === HUD & overlays ===
            overlayUI
        }
        // Save score when round ends
        .onChange(of: game.phase) { phase in
            switch phase {
            case .playing:
                MusicLoop.shared.setScene(.game)

            case .gameOver:
                scores.add(score: game.score)
                MusicLoop.shared.setScene(.gameOver)

            case .paused:
                MusicLoop.shared.setScene(.menu)   // or keep ducked if you prefer

            case .menu:
                MusicLoop.shared.setScene(.menu)
            }
        }
        // Auto-pause on background
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if game.phase == .playing { game.togglePause() }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }
    
    @ViewBuilder
    private var overlayUI: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Score \(game.score)")
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                
                if game.shieldCharges > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.fill")
                        Text("x\(game.shieldCharges)")
                            .monospacedDigit()
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
}
