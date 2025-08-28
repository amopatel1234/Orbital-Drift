//
//  EffectsSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import QuartzCore

@MainActor
@Observable
final class EffectsSystem {
    // MARK: - Effect Entities
    var particles: [Particle] = []
    var shockwaves: [Shockwave] = []
    var toasts: [KillToast] = []
    
    // MARK: - Visual State
    var shake: CGFloat = 0
    var cameraZoom: CGFloat = 1.0
    private var zoomVel: CGFloat = 0
    private var zoomTimer: TimeInterval = 0
    
    // MARK: - Performance Budget
    private var particleBudgetScale: CGFloat = 1.0
    let maxParticles: Int = 800
    
    // MARK: - Constants
    private let maxShake: CGFloat = 3.0
    private let shakeDecayPerSec: CGFloat = 3.2
    private let maxZoom: CGFloat = 1.035
    private let zoomKick: CGFloat = 0.02
    private let zoomSpringK: CGFloat = 18
    private let zoomSpringDamp: CGFloat = 2 * sqrt(18)
    
    // MARK: - Time Scale / Hit-Stop
    private(set) var timeScale: Double = 1.0   // 1.0 = normal
    private var hitStopTimer: Double = 0.0
    
    private let hitStopScaleBig: Double = 0.33
    private let hitStopDurBig:   Double = 0.12
    private let hitStopScaleMed: Double = 0.6
    private let hitStopDurMed:   Double = 0.08
    private let hitStopRecoverPerSec: Double = 2.5
    
    // MARK: - Public Interface
    
    func updateEffects(dt: TimeInterval, particleBudget: CGFloat) {
        self.particleBudgetScale = particleBudget
        
        updateParticles(dt: dt)
        updateShockwaves(dt: dt)
        updateToasts(dt: dt)
        decayShake(dt: dt)
        springCameraZoom(dt: dt)
        updateHitStop(dt: dt) // NEW
    }
    
    func addShake(_ amount: CGFloat) {
        shake = min(maxShake, shake + amount)
    }
    
    func addZoomKick() {
        cameraZoom = min(maxZoom, cameraZoom + zoomKick)
        zoomTimer = 0.05
    }
    
    func applyHitStopBig() {
        timeScale = hitStopScaleBig
        hitStopTimer = hitStopDurBig
    }
    
    func applyHitStopMed() {
        timeScale = hitStopScaleMed
        hitStopTimer = hitStopDurMed
    }
    
    func emitBurst(at p: CGPoint,
                   count: Int = 12,
                   speed: ClosedRange<CGFloat> = 90...180,
                   color: Color = .white) {
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
    
    func emitDirectionalBurst(at p: CGPoint,
                              dir: CGVector,
                              count: Int,
                              spread: CGFloat,
                              speed: ClosedRange<CGFloat>,
                              life: CGFloat = 1.0,
                              color: Color) {
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
    
    func emitShockwave(at p: CGPoint, maxRadius: CGFloat = 80) {
        shockwaves.append(Shockwave(pos: .init(x: p.x, y: p.y), age: 0, maxRadius: maxRadius))
    }
    
    func emitKillToast(at p: CGPoint, value: Int, color: Color) {
        toasts.append(KillToast(pos: .init(x: p.x, y: p.y), value: value, color: color))
    }
    
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
    
    // MARK: - Private Implementation
    
    private func updateParticles(dt: TimeInterval) {
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.x * dt
            particles[i].pos.y += particles[i].vel.y * dt
            particles[i].life -= CGFloat(dt * 1.8)
        }
        particles.removeAll { $0.life <= 0 }
    }
    
    private func updateShockwaves(dt: TimeInterval) {
        for i in shockwaves.indices {
            shockwaves[i].age += CGFloat(dt * 1.6)
        }
        shockwaves.removeAll { $0.age >= 1 }
    }
    
    private func updateToasts(dt: TimeInterval) {
        for i in toasts.indices {
            toasts[i].age += CGFloat(dt)
        }
        toasts.removeAll { $0.age >= $0.lifetime }
    }
    
    private func decayShake(dt: TimeInterval) {
        shake = max(0, shake - shakeDecayPerSec * CGFloat(dt))
    }
    
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
