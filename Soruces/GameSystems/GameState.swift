//
//  GameState.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI
import Observation
import QuartzCore

/// The central simulation object for Orbital Drift.
///
/// `GameState` coordinates the component systems and maintains shared state
/// needed by the UI. All gameplay logic is delegated to specialized systems.
@MainActor
@Observable
final class GameState {

    // MARK: - Systems
    private let motionSystem = MotionSystem()
    private let combatSystem = CombatSystem()
    private let effectsSystem = EffectsSystem()
    private let spawningSystem = SpawningSystem()
    private let scoringSystem = ScoringSystem()

    // MARK: 🧭 Phase & Timing (public UI-facing)
    var phase: GamePhase = .menu
    private var lastUpdate: TimeInterval = 0

    // MARK: 🌍 World & Entities
    var worldCenter: CGPoint = .zero
    var player = Player()
    
    // Motion state
    private var targetRadius: CGFloat = 160

    // MARK: 🎮 Input Flags (exposed for UI)
    var holdRotateCW: Bool = false
    var holdRotateCCW: Bool = false
    var holdInnerRadius: Bool = false
    var holdOuterRadius: Bool = false

    // Performance tracking
    private var _debugFrameMs: Double = 16.0
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Computed Properties (delegated to systems)
    
    var score: Int { scoringSystem.score }
    var highScore: Int { scoringSystem.highScore }
    var scoreMultiplier: Double { scoringSystem.scoreMultiplier }
    var shieldCharges: Int { combatSystem.shieldCharges }
    var invulnerability: TimeInterval { combatSystem.invulnerability }
    var invulnerabilityPulse: Double { combatSystem.invulnerabilityPulse }
    var shake: CGFloat { effectsSystem.shake }
    var cameraZoom: CGFloat { effectsSystem.cameraZoom }
    
    // Entity accessors
    var asteroids: [Asteroid] = []
    var bullets: [Bullet] { combatSystem.bullets }
    var powerups: [Powerup] { combatSystem.powerups }
    var particles: [Particle] { effectsSystem.particles }
    var shockwaves: [Shockwave] { effectsSystem.shockwaves }
    var toasts: [KillToast] { effectsSystem.toasts }
    
    // Performance metrics
    var debugFrameMs: Double { _debugFrameMs }
    var particleBudgetScale: CGFloat { 1.0 } // Simplified for now

    // MARK: - Lifecycle

    func reset(in size: CGSize) {
        worldCenter = CGPoint(x: size.width/2, y: size.height/2)

        // Reset player
        player = Player(angle: .pi/2, radius: 160)
        targetRadius = 160

        asteroids = []
        
        // Reset systems
        motionSystem.reset()
        combatSystem.reset()
        effectsSystem.reset()
        spawningSystem.reset()
        scoringSystem.reset()

        lastUpdate = 0
        phase = .playing
    }

    // MARK: - Main loop

    func update(now: TimeInterval, size: CGSize) {
        guard phase == .playing else { lastUpdate = now; return }

        // Calculate frame time
        if lastUpdate == 0 { lastUpdate = now }
        let rawDt = now - lastUpdate
        lastUpdate = now
        let dt = min(max(rawDt, 0), 1.0/30.0)

        // Update performance tracking
        updatePerformanceMetrics(rawDt: rawDt)

        // Update real-time effects
        effectsSystem.updateEffects(dt: dt, particleBudget: 1.0)
        scoringSystem.updateMultiplier(dt: dt)

        // Update systems in order
        spawningSystem.updateSpawning(dt: dt, size: size, asteroids: &asteroids, worldCenter: worldCenter)
        
        updateShooting(dt: dt)
        
        motionSystem.updateMotion(player: &player,
                                 targetAngle: player.angle,
                                 targetRadius: targetRadius,
                                 holdRotateCCW: holdRotateCCW,
                                 holdRotateCW: holdRotateCW,
                                 dt: dt,
                                 now: now)
        
        updateEnemies(dt: dt, size: size)
        combatSystem.updateBullets(dt: dt)
        
        let collided = updateCollisions(dt: dt, size: size, now: now)
        combatSystem.updatePowerups(dt: dt, size: size, playerPos: playerPosition(), worldCenter: worldCenter, effects: effectsSystem)
        
        combatSystem.updateInvulnerability(dt: dt)

        finalizeIfGameOver(collided)
    }

    // MARK: - System Coordination

    private func updateShooting(dt: TimeInterval) {
        let p = playerPosition()
        combatSystem.updateShooting(playerPos: p, worldCenter: worldCenter, dt: dt)
    }

    private func updateEnemies(dt: TimeInterval, size: CGSize) {
        // Move enemies
        for i in asteroids.indices {
            asteroids[i].pos.x += asteroids[i].vel.x * dt
            asteroids[i].pos.y += asteroids[i].vel.y * dt
        }
        
        // Apply evader behavior
        let ship = Vector2(x: playerPosition().x, y: playerPosition().y)
        for i in asteroids.indices where asteroids[i].type == .evader {
            let away = (asteroids[i].pos - ship).normalized()
            let evade: CGFloat = 40
            asteroids[i].pos.x += away.x * evade * dt
            asteroids[i].pos.y += away.y * evade * dt
        }
        
        // Cull off-screen enemies
        let pad: CGFloat = 60
        asteroids.removeAll { a in
            a.pos.x < -pad || a.pos.x > size.width + pad ||
            a.pos.y < -pad || a.pos.y > size.height + pad ||
            !a.alive
        }
    }

    private func updateCollisions(dt: TimeInterval, size: CGSize, now: TimeInterval) -> Bool {
        let playerPos = playerPosition()
        var collided = false

        // Player vs asteroids
        for i in asteroids.indices {
            let d = (asteroids[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            let hitDist = (player.size + asteroids[i].size)
            if d < hitDist {
                if combatSystem.invulnerability > 0 {
                    asteroids[i].alive = false
                    continue
                }
                if combatSystem.consumeShield() {
                    asteroids[i].alive = false
                    effectsSystem.emitBurst(at: playerPos, count: 24, speed: 160...260)
                    effectsSystem.emitShockwave(at: playerPos, maxRadius: 90)
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.shieldSave()
                    
                    // Push player out slightly
                    player.radius = min(player.radius + 10, 160)
                    targetRadius = player.radius
                    scoringSystem.addScore(10)
                    continue
                } else {
                    collided = true
                    break
                }
            }
        }

        // Bullets vs asteroids
        if !combatSystem.bullets.isEmpty && !asteroids.isEmpty {
            for bi in combatSystem.bullets.indices where combatSystem.bullets[bi].life > 0 {
                for ai in asteroids.indices where asteroids[ai].alive {
                    if asteroids[ai].pos.distance(to: combatSystem.bullets[bi].pos) < (asteroids[ai].size + combatSystem.bullets[bi].size) {
                        
                        combatSystem.bullets[bi].life = 0
                        asteroids[ai].hp -= 1

                        let hitPoint = CGPoint(x: CGFloat(asteroids[ai].pos.x), y: CGFloat(asteroids[ai].pos.y))
                        effectsSystem.emitBurst(at: hitPoint,
                                              count: 8,
                                              speed: 80...160,
                                              color: asteroids[ai].type.color)

                        if asteroids[ai].hp > 0 {
                            // Bullet impact sparks
                            let bp = combatSystem.bullets[bi].pos
                            let dir = CGVector(dx: CGFloat(combatSystem.bullets[bi].vel.x), dy: CGFloat(combatSystem.bullets[bi].vel.y))
                            effectsSystem.emitDirectionalBurst(at: .init(x: CGFloat(bp.x), y: CGFloat(bp.y)),
                                                             dir: dir,
                                                             count: 5,
                                                             spread: 0.25,
                                                             speed: 80...140,
                                                             life: 0.5,
                                                             color: .white.opacity(0.9))
                        }

                        if asteroids[ai].hp <= 0 {
                            asteroids[ai].alive = false

                            // Apply hit-stop and effects
                            let enemy = asteroids[ai]
                            applyHitStopForEnemy(enemy.type)

                            // Handle scoring and effects
                            let baseScore = enemy.type.scoreValue
                            let gainedScore = scoringSystem.addKillScore(baseScore, for: enemy.type)
                            
                            addShakeForEnemy(enemy.type)
                            emitKillEffects(at: hitPoint, for: enemy.type, score: gainedScore)
                            SoundSynth.shared.pickup()
                        } else {
                            SoundSynth.shared.nearMiss()
                        }
                        break
                    }
                }
            }
        }

        return collided
    }

    private func finalizeIfGameOver(_ collided: Bool) {
        if collided {
            player.isAlive = false
            phase = .gameOver
            scoringSystem.finalizeScore()
            Haptics.shared.crash()
            SoundSynth.shared.crash()
        }
    }

    // MARK: - Helper Methods
    
    private func updatePerformanceMetrics(rawDt: TimeInterval) {
        _debugFrameMs = rawDt * 1000.0
    }
    
    private func applyHitStopForEnemy(_ type: EnemyType) {
        switch type {
        case .big:
            effectsSystem.addZoomKick()
        case .evader:
            effectsSystem.addZoomKick()
        case .small:
            break
        }
    }
    
    private func addShakeForEnemy(_ type: EnemyType) {
        switch type {
        case .small: effectsSystem.addShake(0.8)
        case .evader: effectsSystem.addShake(1.2)
        case .big: effectsSystem.addShake(2.0)
        }
    }
    
    private func emitKillEffects(at point: CGPoint, for type: EnemyType, score: Int) {
        // Burst effect
        let burstCount = type == .big ? 20 : (type == .evader ? 16 : 12)
        effectsSystem.emitBurst(at: point, count: burstCount, speed: 120...220, color: type.color)
        
        // Score toast
        effectsSystem.emitKillToast(at: point, value: score, color: type.color)
    }

    // MARK: - Public Interface

    func playerPosition() -> CGPoint {
        let x = worldCenter.x + cos(player.angle) * player.radius
        let y = worldCenter.y + sin(player.angle) * player.radius
        return CGPoint(x: x, y: y)
    }

    func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default: break
        }
    }

    func setInnerPress(_ pressing: Bool) {
        holdInnerRadius = pressing
        targetRadius = pressing ? motionSystem.minOrbit : player.radius
    }

    func setOuterPress(_ pressing: Bool) {
        holdOuterRadius = pressing
        targetRadius = pressing ? motionSystem.maxOrbit : player.radius
    }
}
