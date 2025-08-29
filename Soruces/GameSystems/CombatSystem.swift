//
//  CombatSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import QuartzCore

/// Owns player combat mechanics that run on the **gameplay clock**:
/// - **Autofire** toward the world center (bullet spawning & lifetime).
/// - **Powerups**: spawning & pickup (shield charges).
/// - **Invulnerability**: brief i-frames after shield consumption.
///
/// ### Time model
/// Call all per-frame updates with **simulation dt** (`simDt = dt * timeScale`) so combat
/// slows correctly during hit-stop. Visual effects invoked from here (bursts) animate on
/// **real dt** inside `EffectsSystem`.
///
/// ### Ownership & interaction
/// - `CombatSystem` owns **bullets** and **powerups** arrays.
/// - `GameState` passes the **player position/size** and **worldCenter** each frame.
/// - `EffectsSystem` is passed in only when we need to emit FX on powerup pickup.
/// - Shield consumption is coordinated via `consumeShield()`; game over handling stays in `GameState`.
@MainActor
@Observable
final class CombatSystem {
    // MARK: - Combat Entities

    /// Live bullets fired by the player. Updated with **simDt**, culled by lifetime.
    var bullets: [Bullet] = []

    /// Shield powerups floating in the playfield. Updated & collected with **simDt**.
    var powerups: [Powerup] = []
    
    // MARK: - Combat State

    /// Current number of shield charges the player has collected (0...`maxShields`).
    var shieldCharges: Int = 0

    /// Remaining invulnerability time (seconds). Ticked down with **simDt**.
    var invulnerability: TimeInterval = 0

    /// Upper bound for `shieldCharges`.
    let maxShields: Int = 5
    
    // MARK: - Shooting State

    /// Accumulator used to fire at a steady rate independent of frame rate.
    private var fireAccumulator: TimeInterval = 0

    /// Shots per second. Higher values increase bullet frequency.
    var fireRate: Double = 6.0
    
    // MARK: - Powerup State

    /// Internal timer for periodic shield powerup spawns.
    private var powerupTimer: TimeInterval = 0
    
    // MARK: - Public Interface

    /// Updates autofire toward the **world center** and spawns bullets at a steady cadence.
    ///
    /// - Parameters:
    ///   - playerPos: The player’s current world-space position.
    ///   - worldCenter: The orbital center the ship fires toward.
    ///   - dt: **Simulation delta time** (scaled by hit-stop).
    /// - Order: Call **before** collision checks so newly spawned bullets can interact this frame.
    func updateShooting(playerPos: CGPoint, worldCenter: CGPoint, dt: TimeInterval) {
        fireAccumulator += dt
        let fireInterval = 1.0 / fireRate
        
        while fireAccumulator >= fireInterval {
            fireAccumulator -= fireInterval
            
            let dir = Vector2(x: worldCenter.x - playerPos.x, y: worldCenter.y - playerPos.y).normalized()
            let speed: CGFloat = 420
            let vel = dir * speed
            
            bullets.append(Bullet(
                pos: .init(x: playerPos.x, y: playerPos.y),
                vel: vel,
                life: 1.2,
                size: 3.5
            ))
        }
    }
    
    /// Integrates bullet positions and lifetimes, then culls expired bullets.
    ///
    /// - Parameter dt: **Simulation delta time** (scaled by hit-stop).
    /// - Order: Call **before** collisions to ensure positions are up-to-date.
    func updateBullets(dt: TimeInterval) {
        for i in bullets.indices {
            bullets[i].pos = bullets[i].pos + bullets[i].vel * dt
            bullets[i].life -= CGFloat(dt)
        }
        bullets.removeAll { $0.life <= 0 }
    }
    
    /// Spawns and collects shield powerups.
    ///
    /// - Parameters:
    ///   - dt: **Simulation delta time** (scaled by hit-stop).
    ///   - size: World bounds used for spawn layout.
    ///   - playerPos: Player position for pickup checks.
    ///   - playerSize: Player collision radius (for pickup distance).
    ///   - worldCenter: Center used to place powerups on a ring.
    ///   - effects: Effects system to emit small pickup bursts (runs on real dt internally).
    /// - Behavior:
    ///   - Spawns a shield powerup periodically (capped to 2 active) on a ring about the center.
    ///   - On pickup: increments `shieldCharges` (up to `maxShields`), plays haptic/SFX, and emits a burst.
    /// - Order: Call **after** player movement but before end-of-frame entity cleanup.
    func updatePowerups(dt: TimeInterval,
                        size: CGSize,
                        playerPos: CGPoint,
                        playerSize: CGFloat,
                        worldCenter: CGPoint,
                        effects: EffectsSystem) {
        // Spawn powerups
        powerupTimer += dt
        if powerupTimer > 6.5 {
            powerupTimer = 0
            if Bool.random(), powerups.count < 2 {
                let angle = CGFloat.random(in: 0...(2*CGFloat.pi))
                let r: CGFloat = CGFloat.random(in: 70...170)
                let p = CGPoint(x: worldCenter.x + cos(angle)*r, y: worldCenter.y + sin(angle)*r)
                powerups.append(Powerup(pos: .init(x: p.x, y: p.y)))
            }
        }
        
        // Collect powerups
        for i in powerups.indices {
            let d = (powerups[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            if d < (playerSize + powerups[i].size) {
                powerups[i].alive = false
                if shieldCharges < maxShields {
                    shieldCharges += 1
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.pickup()
                    effects.emitBurst(at: playerPos, count: 10, speed: 80...140)
                } else {
                    effects.emitBurst(at: playerPos, count: 6, speed: 60...120)
                }
            }
        }
        powerups.removeAll { !$0.alive }
    }
    
    /// Ticks down remaining invulnerability time (i-frames).
    ///
    /// - Parameter dt: **Simulation delta time** (scaled by hit-stop).
    /// - Call this once per frame from `GameState.update(...)`.
    func updateInvulnerability(dt: TimeInterval) {
        if invulnerability > 0 {
            invulnerability = max(0, invulnerability - dt)
        }
    }
    
    /// Consumes one shield charge (if available) and grants brief invulnerability.
    ///
    /// - Returns: `true` if a shield was consumed and i-frames granted; otherwise `false`.
    /// - Order: Call from collision handling when the player would otherwise take a hit.
    func consumeShield() -> Bool {
        if shieldCharges > 0 {
            shieldCharges -= 1
            invulnerability = 0.7
            return true
        }
        return false
    }
    
    /// Applies a kills-based firepower tier by setting the current fire rate.
    /// Tier 0 is baseline; higher tiers increase shots/sec. Patterns stay the same in Phase 1.
    func setFirepowerTier(_ tier: Int) {
        // Keep tiers clamped so future changes don't crash older builds.
        let t = max(0, min(tier, 4))
        switch t {
        case 0: fireRate = 6.0     // baseline
        case 1: fireRate = 7.2     // +20%
        case 2: fireRate = 7.2     // will add 2-shot fan in Phase 2 (same rate)
        case 3: fireRate = 8.2     // +~15% over tier 2
        default: fireRate = 8.2    // tier 4 cap (Phase 2/3 can add pattern variety)
        }
    }
    
    /// Resets per-run combat state (bullets, powerups, shields, timers).
    /// Does **not** affect systems outside combat.
    func reset() {
        bullets.removeAll()
        powerups.removeAll()
        shieldCharges = 0
        invulnerability = 0
        fireAccumulator = 0
        powerupTimer = 0
    }
    
    // MARK: - Computed Properties
    
    /// A 0–1 pulse useful for rendering a shield halo while invulnerable.
    /// Uses **real time** (`CACurrentMediaTime`) so the pulse feels stable during hit-stop.
    var invulnerabilityPulse: Double {
        guard invulnerability > 0 else { return 0 }
        let t = CACurrentMediaTime()
        return (sin(t * 10) * 0.5 + 0.5)
    }
}
