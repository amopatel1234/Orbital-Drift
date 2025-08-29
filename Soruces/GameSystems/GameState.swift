//
//  GameState.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI
import Observation
import QuartzCore

/// The central simulation object for **Orbital Drift**.
///
/// `GameState` coordinates all subsystem updates, owns shared world state that the UI
/// binds to, and defines the frame loop (`update`). Gameplay logic is delegated to
/// specialized systems:
///
/// - `MotionSystem` – integrates the player's angle/radius with momentum + spring.
/// - `CombatSystem` – bullets, powerups, shields, i-frames.
/// - `EffectsSystem` – particles, shockwaves, kill toasts, shake/zoom, hit-stop timeScale.
/// - `SpawningSystem` – time-ramped enemy spawning with population caps.
/// - `ScoringSystem` – score + multiplier, high-score persistence.
///
/// ### Time model
/// Each frame computes:
/// - `dt` = clamped real delta (unscaled) used for **visual decays** and **UI-facing timing**.
/// - `simDt = dt * effectsSystem.timeScale` used for **gameplay simulation** (movement,
///   spawn, bullets, collisions) so hit-stop slows the game but not visual decays.
///
/// ### Ownership
/// - `GameState` owns the **authoritative** arrays for enemies (`asteroids`) and the
///   player model, plus UI-exposed derived values from subsystems (score, cameraZoom, etc).
/// - Subsystems own their internal state (e.g., `CombatSystem.bullets`, `EffectsSystem.particles`).
///
/// ### Order of operations (per frame)
/// 1. Compute `dt` and `simDt`, update performance/visual decays (`EffectsSystem`, `ScoringSystem`).
/// 2. Spawning (simDt), Shooting (simDt), Motion (simDt).
/// 3. Enemy movement / culling (simDt).
/// 4. Collisions (simDt), Powerups (simDt), Invulnerability tick (simDt).
/// 5. Finalize game-over and publish UI-observable fields.
///
/// This class is `@MainActor` & `@Observable` so SwiftUI can bind directly to its
/// published properties without threading hazards.
@MainActor
@Observable
final class GameState {

    // MARK: - Systems

    /// Integrates player motion (angle & radius) with momentum and a critically-damped spring.
    private let motionSystem = MotionSystem()

    /// Owns bullets/powerups, shield charges, and invulnerability.
    private let combatSystem = CombatSystem()

    /// Visual FX and global timeScale (hit-stop). Also handles shake/zoom/particles/toasts.
    private let effectsSystem = EffectsSystem()

    /// Time-ramped enemy spawning with population caps and edge placement.
    private let spawningSystem = SpawningSystem()

    /// Score/multiplier bookkeeping and high-score persistence.
    private let scoringSystem = ScoringSystem()

    // MARK: 🧭 Phase & Timing (public UI-facing)

    /// High-level gameplay phase bound to UI (menu/playing/paused/gameOver).
    var phase: GamePhase = .menu

    /// Last frame timestamp (seconds). Used to compute `dt` in `update`.
    private var lastUpdate: TimeInterval = 0

    // MARK: 🌍 World & Entities

    /// World origin for orbits & enemy targeting (usually the screen center).
    var worldCenter: CGPoint = .zero

    /// The player entity (angle, radius, size, alive state).
    var player = Player()
    
    // Motion state

    /// The target orbit radius the spring drives toward (updated by input handlers).
    private var targetRadius: CGFloat = 160

    // MARK: 🎮 Input Flags (exposed for UI)

    /// Hold to rotate clockwise.
    var holdRotateCW: Bool = false

    /// Hold to rotate counter-clockwise.
    var holdRotateCCW: Bool = false

    /// Hold to move toward inner orbit bound.
    var holdInnerRadius: Bool = false

    /// Hold to move toward outer orbit bound.
    var holdOuterRadius: Bool = false

    // Performance tracking

    /// Exponentially smoothed frame time in milliseconds for debug UI.
    private var _debugFrameMs: Double = 16.0

    /// Reserved; not currently used in the loop (kept for future profiling).
    private var lastFrameTime: CFTimeInterval = 0

    // MARK: - Computed Properties (delegated to systems)
    // UI reads these; they forward to the owning system to avoid duplicated state.

    /// Current score.
    var score: Int { scoringSystem.score }

    /// Highest score persisted in `UserDefaults`.
    var highScore: Int { scoringSystem.highScore }

    /// Current score multiplier (decays over **real** time).
    var scoreMultiplier: Double { scoringSystem.scoreMultiplier }

    /// Player shields remaining.
    var shieldCharges: Int { combatSystem.shieldCharges }

    /// Remaining invulnerability (i-frames) in seconds.
    var invulnerability: TimeInterval { combatSystem.invulnerability }

    /// 0–1 pulse used by the renderer to draw shield halo while invulnerable.
    var invulnerabilityPulse: Double { combatSystem.invulnerabilityPulse }

    /// Screen shake amount for the frame.
    var shake: CGFloat { effectsSystem.shake }

    /// Camera zoom scalar (1 = neutral).
    var cameraZoom: CGFloat { effectsSystem.cameraZoom }
    
    // Entity accessors

    /// Authoritative enemy array (alive/dead, HP, type, position).
    var asteroids: [Asteroid] = []

    /// Live bullets owned by `CombatSystem`.
    var bullets: [Bullet] { combatSystem.bullets }

    /// Active powerups owned by `CombatSystem`.
    var powerups: [Powerup] { combatSystem.powerups }

    /// Live particles owned by `EffectsSystem`.
    var particles: [Particle] { effectsSystem.particles }

    /// Expanding rings for impacts.
    var shockwaves: [Shockwave] { effectsSystem.shockwaves }

    /// Floating score popups on kill.
    var toasts: [KillToast] { effectsSystem.toasts }
    
    // Performance metrics

    /// Smoothed frame time (ms) for the dev meter.
    var debugFrameMs: Double { _debugFrameMs }

    /// Auto particle budget (0.3–1.0). Kept simple here; can be hooked to perf later.
    var particleBudgetScale: CGFloat { 1.0 } // Simplified for now

    // MARK: - Lifecycle

    /// Clears transient state and starts a new run in `.playing` phase.
    ///
    /// - Parameter size: Current viewport size; used to set `worldCenter` and initial radius.
    func reset(in size: CGSize) {
        worldCenter = CGPoint(x: size.width/2, y: size.height/2)

        // Reset player
        player = Player(angle: .pi/2, radius: 160)
        targetRadius = 160

        asteroids = []
        
        // Reset subsystems
        motionSystem.reset()
        combatSystem.reset()
        effectsSystem.reset()
        spawningSystem.reset()
        scoringSystem.reset()
        combatSystem.setFirepowerTier(0) // ensure baseline on new run

        lastUpdate = 0
        phase = .playing
    }

    // MARK: - Main loop

    /// Steps one frame of simulation and effects.
    ///
    /// - Parameters:
    ///   - now: Current timestamp in seconds (monotonic).
    ///   - size: Current viewport size for spawn & culling logic.
    ///
    /// Uses **real dt** for effects/decays and **simDt** (scaled by hit-stop) for gameplay.
    func update(now: TimeInterval, size: CGSize) {
        guard phase == .playing else { lastUpdate = now; return }

        // Calculate frame time
        if lastUpdate == 0 { lastUpdate = now }
        let rawDt = now - lastUpdate
        lastUpdate = now

        /// Clamped real time step to stabilize large hitches.
        let dt = min(max(rawDt, 0), 1.0/30.0)

        // --- NEW: apply timeScale from effectsSystem ---
        /// Gameplay delta time slowed by hit-stop; passed to systems that simulate.
        let simDt = dt * effectsSystem.timeScale

        // Update performance tracking (use raw dt, unaffected by hit-stop)
        updatePerformanceMetrics(rawDt: rawDt)

        // Update real-time effects (use raw dt so shake/zoom/toasts don’t freeze during stop)
        effectsSystem.updateEffects(dt: dt, particleBudget: 1.0)

        // Update scoring decay (real time, not sim time)
        scoringSystem.updateMultiplier(dt: dt)

        // Update systems in order (use simDt so gameplay slows during hit-stop)
        spawningSystem.updateSpawning(dt: simDt, size: size, asteroids: &asteroids, worldCenter: worldCenter)
        
        updateShooting(dt: simDt)
        
        motionSystem.updateMotion(player: &player,
                                 targetRadius: targetRadius,
                                 holdRotateCCW: holdRotateCCW,
                                 holdRotateCW: holdRotateCW,
                                 dt: simDt,
                                 now: now)
        
        updateEnemies(dt: simDt, size: size)
        combatSystem.updateBullets(dt: simDt)
        
        let collided = updateCollisions(dt: simDt, size: size, now: now)
        combatSystem.updatePowerups(dt: simDt,
                                    size: size,
                                    playerPos: playerPosition(),
                                    playerSize: player.size,
                                    worldCenter: worldCenter,
                                    effects: effectsSystem)
        
        combatSystem.updateInvulnerability(dt: simDt)

        finalizeIfGameOver(collided)
    }

    // MARK: - System Coordination

    /// Drives the auto-fire cadence and appends bullets into `CombatSystem`.
    /// - Parameter dt: **Simulation dt** so firing rate slows during hit-stop.
    private func updateShooting(dt: TimeInterval) {
        let p = playerPosition()
        combatSystem.updateShooting(playerPos: p, worldCenter: worldCenter, dt: dt)
    }

    /// Integrates enemies and applies simple AI (evader drift) and off-screen culling.
    /// - Parameters:
    ///   - dt: **Simulation dt**.
    ///   - size: Viewport bounds for culling.
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

    /// Resolves player/enemy and bullet/enemy collisions, applies scoring, FX, and hit-stop.
    /// - Returns: `true` if the player collided without a shield (i.e., game over).
    /// - Parameters:
    ///   - dt: **Simulation dt**.
    ///   - size: Viewport (unused here; kept for symmetry).
    ///   - now: Timestamp for misc. cooldowns/haptics if needed.
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
                        asteroids[ai].hp -= combatSystem.bullets[bi].damage

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

                            // Check if a firepower tier threshold was crossed by this kill
                            if let newTier = scoringSystem.registerKillAndMaybeTierUp(for: enemy.type) {
                                combatSystem.setFirepowerTier(newTier)
                                // Optional tiny cue (kept subtle for Phase 1)
                                effectsSystem.emitShockwave(at: hitPoint, maxRadius: 70)
                                effectsSystem.emitBurst(at: playerPos, color:bullets[bi].tint)
                                effectsSystem.addZoomKick()
                                Haptics.shared.nearMiss()
                            }
                            
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

    /// Transitions to `.gameOver`, persists high score, and triggers crash FX/SFX.
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
    
    /// Updates the smoothed frame time (ms) used by the dev meter.
    /// - Parameter rawDt: Unclamped real delta.
    private func updatePerformanceMetrics(rawDt: TimeInterval) {
        _debugFrameMs = rawDt * 1000.0
    }
    
    /// Chooses and applies hit-stop intensity + a small zoom kick by enemy type.
    private func applyHitStopForEnemy(_ type: EnemyType) {
        switch type {
        case .big:
            effectsSystem.applyHitStopBig()
            effectsSystem.addZoomKick()
        case .evader:
            effectsSystem.applyHitStopMed()
            effectsSystem.addZoomKick()
        case .small:
            break
        }
    }
    
    /// Adds a type-scaled screen shake amount on kill.
    private func addShakeForEnemy(_ type: EnemyType) {
        switch type {
        case .small: effectsSystem.addShake(0.8)
        case .evader: effectsSystem.addShake(1.2)
        case .big: effectsSystem.addShake(2.0)
        }
    }
    
    /// Emits kill burst particles and a floating score toast.
    private func emitKillEffects(at point: CGPoint, for type: EnemyType, score: Int) {
        // Burst effect
        let burstCount = type == .big ? 20 : (type == .evader ? 16 : 12)
        effectsSystem.emitBurst(at: point, count: burstCount, speed: 120...220, color: type.color)
        
        // Score toast
        effectsSystem.emitKillToast(at: point, value: score, color: type.color)
    }

    // MARK: - Public Interface

    /// Converts the player's polar state (angle, radius) into world-space position.
    func playerPosition() -> CGPoint {
        let x = worldCenter.x + cos(player.angle) * player.radius
        let y = worldCenter.y + sin(player.angle) * player.radius
        return CGPoint(x: x, y: y)
    }

    /// Toggles between `.playing` and `.paused`. No effect in other phases.
    func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default: break
        }
    }

    /// Latches/clears the “inner radius” control. When released, the current radius becomes sticky.
    func setInnerPress(_ pressing: Bool) {
        holdInnerRadius = pressing
        targetRadius = pressing ? motionSystem.minOrbit : player.radius
    }

    /// Latches/clears the “outer radius” control. When released, the current radius becomes sticky.
    func setOuterPress(_ pressing: Bool) {
        holdOuterRadius = pressing
        targetRadius = pressing ? motionSystem.maxOrbit : player.radius
    }
}
