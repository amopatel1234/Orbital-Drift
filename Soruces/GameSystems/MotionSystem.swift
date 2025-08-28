//  MotionSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import UIKit

/// Integrates the player's **angle** and **radius** using a momentum model for rotation
/// and a critically-damped spring for radial movement.
///
/// ### Responsibilities
/// - **Angular motion**: accelerates/decelerates toward a target turn speed derived from
///   input buttons (CCW/CW). Applies per-second damping to prevent lingering jitter.
/// - **Radial motion**: springs the ship toward `targetRadius` with critical damping and
///   clamps to `[minOrbit, maxOrbit]`. Emits a small haptic “bump” when hitting bounds.
/// - **No rendering / scoring / collisions** here — this system only updates `Player`.
///
/// ### Time model
/// Call `updateMotion` with **simulation dt** (`simDt = dt * timeScale`) so motion correctly
/// slows during hit-stop. Haptics fire on the main thread when bounds are reached.
///
/// ### Ownership & interaction
/// - `MotionSystem` owns only transient motion state (angular/radial velocities).
/// - `GameState` owns `Player` and passes it **inout** each frame.
/// - Orbit bounds are defined here so UI and other systems can treat them as shared constants.
///
/// ### Order
/// Call `updateMotion` **after** input has been latched (holdRotateCCW/holdRotateCW),
/// and **before** collisions and rendering, so the updated transform is visible and correct.
@MainActor
@Observable
final class MotionSystem {
    // MARK: - Motion State

    /// Current angular velocity in radians/sec.
    var angularVel: CGFloat = 0

    /// Current radial velocity in points/sec.
    var radialVel: CGFloat = 0
    
    // MARK: - Angular motion constants

    /// Maximum turn speed magnitude (radians/sec).
    let angularMaxSpeed: CGFloat = 2.4

    /// Acceleration toward target turn speed while input is held.
    let angularAccel: CGFloat = 7.0

    /// Braking magnitude applied when no turn input is held.
    let angularDecel: CGFloat = 6.0

    /// Per-second damping multiplier (0..1]. Applied as `pow(angularFriction, dt)` to
    /// bleed tiny oscillations without affecting large intentional changes.
    let angularFriction: CGFloat = 0.8
    
    // MARK: - Radial motion constants

    /// Reserved tunables if you switch away from the spring model in future.
    let radialMaxSpeed: CGFloat = 160
    let radialAccel: CGFloat = 280
    let radialDecel: CGFloat = 240
    let radialFriction: CGFloat = 0.85
    
    // MARK: - Orbit bounds

    /// Minimum radius allowed for the player's orbit (points).
    let minOrbit: CGFloat = 60

    /// Maximum radius allowed for the player's orbit (points).
    let maxOrbit: CGFloat = 160
    
    // MARK: - Private state

    /// Last time (system seconds) an orbit edge bump haptic was played.
    private var lastOrbitBumpTime: CFTimeInterval = 0

    /// Minimum time between orbit bump haptics (seconds).
    private let orbitBumpCooldown: CFTimeInterval = 0.25
    
    // MARK: - Public Interface
    
    /// Integrates the player's rotation and radius for one simulation step.
    ///
    /// - Parameters:
    ///   - player: The `Player` to mutate (angle/radius).
    ///   - targetRadius: Desired orbit radius the spring will approach.
    ///   - holdRotateCCW: Whether the CCW (counter-clockwise) input is held this frame.
    ///   - holdRotateCW: Whether the CW (clockwise) input is held this frame.
    ///   - dt: **Simulation delta time** (scaled by hit-stop).
    ///   - now: Wall-clock timestamp (used only for haptic cooldown).
    /// - Order: Call after input was sampled; before collisions/rendering.
    func updateMotion(
        player: inout Player,
        targetRadius: CGFloat,
        holdRotateCCW: Bool,
        holdRotateCW: Bool,
        dt: TimeInterval,
        now: TimeInterval
    ) {
        updateAngularMotion(
            player: &player,
            holdRotateCCW: holdRotateCCW,
            holdRotateCW: holdRotateCW,
            dt: dt
        )
        updateRadialMotion(
            player: &player,
            targetRadius: targetRadius,
            dt: dt,
            now: now
        )
    }
    
    /// Resets all transient motion state (velocities and haptic cooldown).
    func reset() {
        angularVel = 0
        radialVel = 0
        lastOrbitBumpTime = 0
    }
    
    // MARK: - Private Implementation
    
    /// Updates angular velocity from inputs and integrates `player.angle`.
    ///
    /// - Parameters:
    ///   - player: Player to mutate.
    ///   - holdRotateCCW: CCW input latch.
    ///   - holdRotateCW: CW input latch.
    ///   - dt: **Simulation dt**.
    private func updateAngularMotion(
        player: inout Player,
        holdRotateCCW: Bool,
        holdRotateCW: Bool,
        dt: TimeInterval
    ) {
        // Map inputs to a signed turn target in [-angularMaxSpeed, +angularMaxSpeed]
        let turnInput: CGFloat = (holdRotateCCW ? 1 : 0) - (holdRotateCW ? 1 : 0)
        let turnTargetSpeed = turnInput * angularMaxSpeed
        
        if turnInput != 0 {
            // Thrust toward target turn speed while held
            let delta = turnTargetSpeed - angularVel
            let maxDelta = angularAccel * CGFloat(dt)
            angularVel += max(-maxDelta, min(maxDelta, delta))
        } else {
            // Brake toward zero when released
            let sign: CGFloat = angularVel >= 0 ? 1 : -1
            let mag = abs(angularVel)
            let newMag = max(0, mag - angularDecel * CGFloat(dt))
            angularVel = sign * newMag
        }
        
        // Per-second damping (keeps tiny oscillations from lingering)
        angularVel *= pow(angularFriction, CGFloat(dt))
        player.angle += angularVel * CGFloat(dt)
    }
    
    /// Springs the player's radius toward `targetRadius` with critical damping,
    /// clamps to orbit bounds, and emits a small haptic on hard limits.
    ///
    /// - Parameters:
    ///   - player: Player to mutate.
    ///   - targetRadius: Desired radius.
    ///   - dt: **Simulation dt**.
    ///   - now: Wall-clock time for haptic cooldown.
    private func updateRadialMotion(
        player: inout Player,
        targetRadius: CGFloat,
        dt: TimeInterval,
        now: TimeInterval
    ) {
        // Critically-damped spring toward targetRadius
        let k: CGFloat = 22.0
        let c: CGFloat = 2 * sqrt(k)
        let x = player.radius
        let v = radialVel
        let a = -k * (x - targetRadius) - c * v
        
        radialVel += a * CGFloat(dt)
        player.radius += radialVel * CGFloat(dt)
        
        // Clamp and handle orbit bumps
        player.radius = min(max(player.radius, minOrbit), maxOrbit)
        
        let bumpedMin = player.radius <= minOrbit + 0.001
        let bumpedMax = player.radius >= maxOrbit - 0.001
        if (bumpedMin || bumpedMax), now - lastOrbitBumpTime > orbitBumpCooldown {
            orbitBumpHaptic()
            lastOrbitBumpTime = now
        }
    }
    
    /// Fires a small haptic to acknowledge hard orbit bounds.
    private func orbitBumpHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        gen.impactOccurred(intensity: 0.6)
    }
}
