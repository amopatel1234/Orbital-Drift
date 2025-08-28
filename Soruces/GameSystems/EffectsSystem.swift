//
//  EffectsSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import QuartzCore

/// Owns all *visual* and *feel* effects that should continue to animate on real time,
/// independent of gameplay slow-downs (hit-stop).
///
/// `EffectsSystem` is responsible for:
/// - **Particles / Shockwaves / Toasts**: transient FX entities that age on **real dt**.
/// - **Screen Shake**: a scalar used by the UI to offset the camera; decays on **real dt**.
/// - **Camera Zoom Kick**: small pulses that spring back to 1.0 on **real dt**.
/// - **Hit-Stop / timeScale**: exposes a time scaling factor used by gameplay code
///   (`simDt = dt * timeScale`). Hit-stop timers and recovery are advanced on **real dt** so
///   that UI/FX remain responsive during slow-motion.
///
/// Ownership & interaction notes:
/// - `EffectsSystem` **does not** move gameplay entities. It only updates FX state.
/// - `GameState` should:
///   - Pass **raw clamped `dt`** to `updateEffects(dt:particleBudget:)`.
///   - Compute **`simDt = dt * timeScale`** and pass *that* to gameplay systems (motion,
///     spawning, bullets, collisions, etc.).
/// - Particle budget scaling is provided by the caller (e.g., a perf controller/EMA).
@MainActor
@Observable
final class EffectsSystem {
    // MARK: - Effect Entities

    /// Additive, short-lived visual particles (spark/smoke fragments).
    /// Aged on **real dt**; hard-capped by `maxParticles`.
    var particles: [Particle] = []

    /// Expanding rings for impactful events (e.g., shield saves).
    /// Aged on **real dt** until `age >= 1`.
    var shockwaves: [Shockwave] = []

    /// Floating numeric toasts (e.g., kill score popups).
    /// Aged on **real dt** until `age >= lifetime`.
    var toasts: [KillToast] = []
    
    // MARK: - Visual State

    /// Screen shake intensity scalar. The view layer should read this and offset accordingly.
    /// Decays on **real dt** via `decayShake(dt:)`.
    var shake: CGFloat = 0

    /// Camera zoom factor; 1.0 = neutral. Small “kicks” are added on impacts and
    /// spring back toward 1.0 using **real dt**.
    var cameraZoom: CGFloat = 1.0

    /// Internal spring state (velocity) for camera zoom.
    private var zoomVel: CGFloat = 0

    /// Brief hold after a zoom kick before springing resumes (seconds).
    private var zoomTimer: TimeInterval = 0
    
    // MARK: - Performance Budget

    /// Scalar (0.3–1.0 typically) applied to requested particle counts to reduce load
    /// when the game approaches frame budget. Provided by `GameState`.
    private var particleBudgetScale: CGFloat = 1.0

    /// Hard upper bound on particles for safety.
    let maxParticles: Int = 800
    
    // MARK: - Constants

    private let maxShake: CGFloat = 3.0
    private let shakeDecayPerSec: CGFloat = 3.2

    /// Upper clamp for camera zoom pulses (e.g., ~3.5% zoom).
    private let maxZoom: CGFloat = 1.035

    /// Single kick increment applied by `addZoomKick()` before clamping.
    private let zoomKick: CGFloat = 0.02

    /// Camera zoom spring constants (critically-damped).
    private let zoomSpringK: CGFloat = 18
    private let zoomSpringDamp: CGFloat = 2 * sqrt(18)
    
    // MARK: - Time Scale / Hit-Stop

    /// Gameplay time scale (1.0 = normal). `GameState` should compute `simDt = dt * timeScale`
    /// and feed that into gameplay systems so that hit-stop slows motion/spawns/combat.
    private(set) var timeScale: Double = 1.0

    /// Remaining hit-stop time (seconds). Advanced on **real dt**.
    private var hitStopTimer: Double = 0.0

    /// Hit-stop presets for different impact magnitudes.
    private let hitStopScaleBig: Double = 0.33
    private let hitStopDurBig:   Double = 0.12
    private let hitStopScaleMed: Double = 0.6
    private let hitStopDurMed:   Double = 0.08

    /// Rate at which `timeScale` eases back to 1.0 once `hitStopTimer` elapses.
    private let hitStopRecoverPerSec: Double = 2.5
    
    // MARK: - Public Interface

    /// Updates all FX on **real dt** so they keep animating during hit-stop.
    ///
    /// - Parameters:
    ///   - dt: Real, clamped frame delta (not scaled by `timeScale`).
    ///   - particleBudget: Budget scale (0..1] to throttle particle counts.
    /// - Order: Call exactly once per frame before drawing; gameplay systems should
    ///   use `simDt` derived from `timeScale`.
    func updateEffects(dt: TimeInterval, particleBudget: CGFloat) {
        self.particleBudgetScale = particleBudget
        
        updateParticles(dt: dt)
        updateShockwaves(dt: dt)
        updateToasts(dt: dt)
        decayShake(dt: dt)
        springCameraZoom(dt: dt)
        updateHitStop(dt: dt)
    }
    
    /// Adds to the current screen shake intensity and clamps to `maxShake`.
    func addShake(_ amount: CGFloat) {
        shake = min(maxShake, shake + amount)
    }
    
    /// Applies a small, clamped “zoom kick” and holds briefly before springing resumes.
    func addZoomKick() {
        cameraZoom = min(maxZoom, cameraZoom + zoomKick)
        zoomTimer = 0.05
    }
    
    /// Triggers a stronger hit-stop preset (e.g., big enemy death).
    /// - Note: Called *before* scoring/FX so that subsequent visuals occur during slow-mo.
    func applyHitStopBig() {
        timeScale = hitStopScaleBig
        hitStopTimer = hitStopDurBig
    }
    
    /// Triggers a medium hit-stop preset (e.g., evader death).
    func applyHitStopMed() {
        timeScale = hitStopScaleMed
        hitStopTimer = hitStopDurMed
    }
    
    /// Emits an omnidirectional particle burst, budget-scaled and capped.
    func emitBurst(
        at p: CGPoint,
        count: Int = 12,
        speed: ClosedRange<CGFloat> = 90...180,
        color: Color = .white
    ) {
        let scaled = max(1, Int(ceil(CGFloat(count) * particleBudgetScale)))
        
        for _ in 0..<scaled {
            let a = CGFloat.random(in: 0...(2*CGFloat.pi))
            let s = CGFloat.random(in: speed)
            particles.append(Particle(
                pos: .init(x: p.x, y: p.y),
                vel: .init(x: cos(a)*s, y: sin(a)*s),
                life: 1,
                color: color
            ))
        }
        
        if particles.count > maxParticles {
            let overflow = particles.count - maxParticles
            particles.removeFirst(overflow)
        }
    }
    
    /// Emits a particle burst biased around a direction vector (streaky looks).
    func emitDirectionalBurst(
        at p: CGPoint,
        dir: CGVector,
        count: Int,
        spread: CGFloat,
        speed: ClosedRange<CGFloat>,
        life: CGFloat = 1.0,
        color: Color
    ) {
        let len = max(0.0001, sqrt(dir.dx*dir.dx + dir.dy*dir.dy))
        let ux = dir.dx / len
        let uy = dir.dy / len
        let baseAngle = atan2(uy, ux)
        
        let scaledCount = max(1, Int(ceil(CGFloat(count) * particleBudgetScale)))
        for _ in 0..<scaledCount {
            let a = baseAngle + CGFloat.random(in: -spread...spread)
            let s = CGFloat.random(in: speed)
            particles.append(Particle(
                pos: .init(x: p.x, y: p.y),
                vel: .init(x: cos(a)*s, y: sin(a)*s),
                life: life,
                color: color
            ))
        }
        
        if particles.count > maxParticles {
            particles.removeFirst(particles.count - maxParticles)
        }
    }
    
    /// Adds a new shockwave ring at a point; ages on **real dt**.
    func emitShockwave(at p: CGPoint, maxRadius: CGFloat = 80) {
        shockwaves.append(Shockwave(pos: .init(x: p.x, y: p.y), age: 0, maxRadius: maxRadius))
    }
    
    /// Adds a score toast at a point; ages on **real dt** until it expires.
    func emitKillToast(at p: CGPoint, value: Int, color: Color) {
        toasts.append(KillToast(pos: .init(x: p.x, y: p.y), value: value, color: color))
    }
    
    /// Clears all FX state back to defaults. Does not affect gameplay.
    func reset() {
        particles.removeAll()
        shockwaves.removeAll()
        toasts.removeAll()
        shake = 0
        cameraZoom = 1.0
        zoomVel = 0
        zoomTimer = 0
        timeScale = 1.0
        hitStopTimer = 0
    }
    
    // MARK: - Private Implementation (real-time updates)

    /// Advances particles on **real dt** and culls expired ones.
    private func updateParticles(dt: TimeInterval) {
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.x * dt
            particles[i].pos.y += particles[i].vel.y * dt
            particles[i].life -= CGFloat(dt * 1.8)
        }
        particles.removeAll { $0.life <= 0 }
    }
    
    /// Advances shockwaves on **real dt** and culls when `age >= 1`.
    private func updateShockwaves(dt: TimeInterval) {
        for i in shockwaves.indices {
            shockwaves[i].age += CGFloat(dt * 1.6)
        }
        shockwaves.removeAll { $0.age >= 1 }
    }
    
    /// Advances toasts on **real dt** and culls expired ones.
    private func updateToasts(dt: TimeInterval) {
        for i in toasts.indices {
            toasts[i].age += CGFloat(dt)
        }
        toasts.removeAll { $0.age >= $0.lifetime }
    }
    
    /// Decays screen shake on **real dt**.
    private func decayShake(dt: TimeInterval) {
        shake = max(0, shake - shakeDecayPerSec * CGFloat(dt))
    }
    
    /// Springs camera zoom back to 1.0 on **real dt**, with a brief post-kick hold.
    private func springCameraZoom(dt: TimeInterval) {
        if zoomTimer > 0 {
            zoomTimer -= dt
            return
        }
        
        let x = cameraZoom - 1.0
        let a = -zoomSpringK * x - zoomSpringDamp * zoomVel
        zoomVel += a * CGFloat(dt)
        cameraZoom += zoomVel * CGFloat(dt)
        
        if abs(cameraZoom - 1.0) < 0.0005, abs(zoomVel) < 0.0005 {
            cameraZoom = 1.0
            zoomVel = 0
        }
    }
    
    /// Advances hit-stop timers on **real dt** and eases `timeScale` back to 1.0.
    private func updateHitStop(dt: TimeInterval) {
        if hitStopTimer > 0 {
            hitStopTimer -= dt
            if hitStopTimer <= 0 {
                hitStopTimer = 0
            }
        } else if timeScale < 1.0 {
            timeScale = min(1.0, timeScale + hitStopRecoverPerSec * dt)
        }
    }
}
