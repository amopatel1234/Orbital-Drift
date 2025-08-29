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
    
    @AppStorage("debugEnabled") private var debugEnabled = false
    @AppStorage("debugDrawHitboxes") private var debugDrawHitboxes = true
    
    var body: some View {
        ZStack {
            StarfieldBackground()
            GeometryReader { proxy in
                let proxySize = proxy.size
                
                ZStack {
                    // Split the big Canvas into smaller composable canvases
                    PlayfieldCanvas(game: game)
                    EnemiesCanvas(game: game)
                    BulletsCanvas(game: game)
                    FXCanvas(game: game)
                    DebugCanvas(game: game, drawHitboxes: debugDrawHitboxes)
                    // Controls (bottom corners)
                    ControlsOverlay(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 0) // adjust if it collides with your cards
                }
                .scaleEffect(game.cameraZoom, anchor: .center)
                .screenShake(game.shake)
                .contentShape(Rectangle()) // for gestures
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
            
            if debugEnabled {
                DevMeter(
                    fps: max(1, 1000.0 / game.debugFrameMs),               // derived
                    frameMs: game.debugFrameMs,
                    counts: (game.asteroids.count, game.bullets.count, game.particles.count),
                    scale: game.particleBudgetScale
                )
                .padding(.leading, 12)
                .padding(.bottom, game.phase == .playing ? 12 : 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
            let ringColor = Color.white.opacity(0.15 + 0.25)
            context.stroke(ringPath, with: .color(ringColor), lineWidth: 2 + 1)
            
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
                context.stroke(path, with: .color(b.tint), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .drawingGroup(opaque: false)
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
            for toast in game.toasts {
                let t = max(0, min(1, toast.age / toast.lifetime))        // 0→1
                let alpha = (1 - t) * (1 - 0.15 * t)                       // fade-out, gentle tail
                let rise  = easeOutCubic(t) * 42                           // px up
                let scale = 0.85 + 0.25 * easeOutBack(min(t * 1.4, 1))     // pop-in then settle

                let p = CGPoint(x: toast.pos.x, y: toast.pos.y - rise)

                // Build once, then resolve to GraphicsContext text
                let base = Text("+\(toast.value)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                let shadowText = context.resolve(
                    base.foregroundStyle(Color.black.opacity(Double(alpha) * 0.35))
                )
                let mainText = context.resolve(
                    base.foregroundStyle(toast.color.opacity(Double(alpha)))
                )

                // Draw both with the same transform (scale around p)
                context.drawLayer { layer in
                    // move the local origin to p
                    layer.translateBy(x: p.x, y: p.y)
                    // scale around the new origin
                    layer.scaleBy(x: scale, y: scale)

                    // Soft shadow (draw slightly offset from origin)
                    layer.draw(shadowText, at: CGPoint(x: 1.5, y: 1.5))

                    // Main colored label at the origin
                    layer.draw(mainText, at: .zero)
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    @inline(__always) private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let u = 1 - t
        return 1 - u*u*u
    }
    @inline(__always) private func easeOutBack(_ t: CGFloat, _ s: CGFloat = 1.70158) -> CGFloat {
        //  overshoot “pop”
        let u = t - 1
        return 1 + (u*u*((s + 1)*u + s))
    }
}

private struct DebugCanvas: View {
    let game: GameState
    let drawHitboxes: Bool
    
    var body: some View {
        Canvas { context, _ in
            guard drawHitboxes else { return }
            
            // Player
            let pp = game.playerPosition()
            let pr = game.player.size
            context.stroke(Path(ellipseIn: .init(x: pp.x - pr, y: pp.y - pr, width: pr*2, height: pr*2)),
                           with: .color(.green.opacity(0.8)), lineWidth: 1)
            
            // Enemies
            for a in game.asteroids where a.alive {
                let r = a.size
                context.stroke(Path(ellipseIn: .init(x: a.pos.x - r, y: a.pos.y - r, width: r*2, height: r*2)),
                               with: .color(.yellow.opacity(0.8)), lineWidth: 1)
            }
            
            // Bullets
            for b in game.bullets {
                let r = b.size
                context.stroke(Path(ellipseIn: .init(x: CGFloat(b.pos.x) - r, y: CGFloat(b.pos.y) - r, width: r*2, height: r*2)),
                               with: .color(.cyan.opacity(0.8)), lineWidth: 1)
            }
            
            // Power-ups
            for p in game.powerups {
                let r = p.size
                context.stroke(Path(ellipseIn: .init(x: p.pos.x - r, y: p.pos.y - r, width: r*2, height: r*2)),
                               with: .color(.orange.opacity(0.9)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .opacity(drawHitboxes ? 1 : 0)
    }
}

private struct DevMeter: View {
    let fps: Double
    let frameMs: Double
    let counts: (enemies: Int, bullets: Int, particles: Int)
    let scale: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "FPS %.0f  (%.1f ms)", fps, frameMs))
            Text("Enemies \(counts.enemies)  Bullets \(counts.bullets)")
            Text(String(format: "Particles %d  Budget x%.2f", counts.particles, scale))
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.top, 12)
    }
}

private struct PressHoldButton: View {
    let systemImage: String
    let label: String
    let onPressChanged: (Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Text(Image(systemName: systemImage))  // icon only; label unused for now
            .font(.title2.weight(.semibold))
            .frame(width: 54, height: 54)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.white.opacity(isPressed ? 0.8 : 0.25), lineWidth: 1))
            .shadow(radius: isPressed ? 0 : 4)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .contentShape(shape)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity,
                                pressing: { pressing in
                                    if pressing != isPressed {
                                        isPressed = pressing
                                        onPressChanged(pressing)
                                    }
                                },
                                perform: {})
            // Nice haptic when press begins
            .sensoryFeedback(.impact(weight: .light),
                             trigger: isPressed)
    }
}

private struct ControlsOverlay: View {
    @Bindable var game: GameState   // @Observable model

    var body: some View {
        HStack {
            // LEFT STACK: CCW on top, CW on bottom (thumb-friendly)
            VStack(spacing: 10) {
                PressHoldButton(systemImage: "arrow.counterclockwise", label: "CCW") {
                    game.holdRotateCCW = $0
                }
                PressHoldButton(systemImage: "arrow.clockwise", label: "CW") {
                    game.holdRotateCW = $0
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // RIGHT STACK: OUT on top, IN on bottom
            VStack(spacing: 10) {
                // RIGHT stack
                PressHoldButton(systemImage: "arrow.up.to.line.compact", label: "OUT") {
                    game.setOuterPress($0)
                }
                PressHoldButton(systemImage: "arrow.down.to.line.compact", label: "IN") {
                    game.setInnerPress($0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .allowsHitTesting(true)
    }
}
