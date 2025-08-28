//  MotionSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class MotionSystem {
    // MARK: - Motion State
    var angularVel: CGFloat = 0
    var radialVel: CGFloat = 0
    
    // MARK: - Angular motion constants
    let angularMaxSpeed: CGFloat = 2.4
    let angularAccel: CGFloat = 7.0
    let angularDecel: CGFloat = 6.0
    /// Per-second damping multiplier (0..1]. Applied as pow(angularFriction, dt).
    let angularFriction: CGFloat = 0.8
    
    // MARK: - Radial motion constants
    // Reserved tunables if you switch away from the spring model in future.
    let radialMaxSpeed: CGFloat = 160
    let radialAccel: CGFloat = 280
    let radialDecel: CGFloat = 240
    let radialFriction: CGFloat = 0.85
    
    // MARK: - Orbit bounds
    let minOrbit: CGFloat = 60
    let maxOrbit: CGFloat = 160
    
    // MARK: - Private state
    private var lastOrbitBumpTime: CFTimeInterval = 0
    private let orbitBumpCooldown: CFTimeInterval = 0.25
    
    // MARK: - Public Interface
    
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
    
    func reset() {
        angularVel = 0
        radialVel = 0
        lastOrbitBumpTime = 0
    }
    
    // MARK: - Private Implementation
    
    private func updateAngularMotion(
        player: inout Player,
        holdRotateCCW: Bool,
        holdRotateCW: Bool,
        dt: TimeInterval
    ) {
        let turnInput: CGFloat = (holdRotateCCW ? 1 : 0) - (holdRotateCW ? 1 : 0)
        let turnTargetSpeed = turnInput * angularMaxSpeed
        
        if turnInput != 0 {
            let delta = turnTargetSpeed - angularVel
            let maxDelta = angularAccel * CGFloat(dt)
            angularVel += max(-maxDelta, min(maxDelta, delta))
        } else {
            let sign: CGFloat = angularVel >= 0 ? 1 : -1
            let mag = abs(angularVel)
            let newMag = max(0, mag - angularDecel * CGFloat(dt))
            angularVel = sign * newMag
        }
        
        // Per-second damping (keeps tiny oscillations from lingering)
        angularVel *= pow(angularFriction, CGFloat(dt))
        player.angle += angularVel * CGFloat(dt)
    }
    
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
    
    private func orbitBumpHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        gen.impactOccurred(intensity: 0.6)
    }
}
