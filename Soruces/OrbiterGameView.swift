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
    @State private var size: CGSize = .zero
    
    // In OrbiterGameView
    @EnvironmentObject private var scores: ScoresStore
    @EnvironmentObject private var router: AppRouter
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.95), location: 0),
                .init(color: Color.purple.opacity(0.2), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            GeometryReader { proxy in
                let proxySize = proxy.size
                Color.clear
                    .onAppear {
                        size = proxySize
                        game.worldCenter = CGPoint(x: proxySize.width/2, y: proxySize.height/2)
                        game.reset(in: proxySize)
                    }
                    .onChange(of: proxySize) { newValue in
                        size = newValue
                        game.worldCenter = CGPoint(x: newValue.width/2, y: newValue.height/2)
                    }
                
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
                        let baseOpacity = game.theme.ringOpacity
                        let ringColor = Color.white.opacity(baseOpacity + 0.25 * flash)
                        context.stroke(ringPath, with: .color(ringColor), lineWidth: 2 + 1 * flash)
                        
                        // Player
                        let playerPos = game.playerPosition()
                        let playerRect = CGRect(x: playerPos.x - game.player.size,
                                                y: playerPos.y - game.player.size,
                                                width: game.player.size*2, height: game.player.size*2)
                        context.fill(Path(ellipseIn: playerRect), with: .color(.white))
                        
                        // Shield halo
                        if game.shieldCharges > 0 {
                            let halo = CGRect(x: playerPos.x - (game.player.size + 6),
                                              y: playerPos.y - (game.player.size + 6),
                                              width: (game.player.size + 6) * 2, height: (game.player.size + 6) * 2)
                            context.stroke(Path(ellipseIn: halo), with: .color(.white.opacity(0.6)), lineWidth: 2)
                        }
                        
                        // Asteroids
                        for a in game.asteroids {
                            let rect = CGRect(x: a.pos.x - a.size, y: a.pos.y - a.size,
                                              width: a.size*2, height: a.size*2)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(game.theme.asteroidAlpha)))
                        }
                        
                        // Powerups
                        for p in game.powerups {
                            let rect = CGRect(x: p.pos.x - p.size, y: p.pos.y - p.size, width: p.size*2, height: p.size*2)
                            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)), lineWidth: 2)
                        }
                        
                        // Particles
                        for p in game.particles {
                            let alpha = max(0, Double(p.life))
                            let r: CGFloat = 2 + (1 - p.life) * 2
                            let rect = CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r*2, height: r*2)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { game.inputDrag($0) })
                    .screenShake(game.shake)
                    .overlay(overlayUI, alignment: .top)
                    .onChange(of: timeline.date) { newDate in
                        game.update(now: newDate.timeIntervalSinceReferenceDate, size: proxySize)
                    }
                    .onChange(of: game.phase) { newPhase in
                        if newPhase == .gameOver {
                            scores.add(score: game.score)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if game.phase == .playing { game.togglePause() }
        }
        .accessibilityElement(children: .contain)
    }
    
    @ViewBuilder
    private var overlayUI: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Score \(game.score)")
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .accessibilityLabel(Text("Score \(game.score)"))
                
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
                PauseCard(resume: { game.togglePause() }, restart: { game.reset(in: size) })
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
