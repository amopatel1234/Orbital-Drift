//
//  CombatSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI
import QuartzCore

@MainActor
@Observable
final class CombatSystem {
    // MARK: - Combat Entities
    var bullets: [Bullet] = []
    var powerups: [Powerup] = []
    
    // MARK: - Combat State
    var shieldCharges: Int = 0
    var invulnerability: TimeInterval = 0
    let maxShields: Int = 5
    
    // MARK: - Shooting State
    private var fireAccumulator: TimeInterval = 0
    var fireRate: Double = 6.0
    
    // MARK: - Powerup State
    private var powerupTimer: TimeInterval = 0
    
    // MARK: - Public Interface
    
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
    
    func updateBullets(dt: TimeInterval) {
        for i in bullets.indices {
            bullets[i].pos = bullets[i].pos + bullets[i].vel * dt
            bullets[i].life -= CGFloat(dt)
        }
        bullets.removeAll { $0.life <= 0 }
    }
    
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
            if d < (playerSize + powerups[i].size) { // player.size hardcoded
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
    
    func updateInvulnerability(dt: TimeInterval) {
        if invulnerability > 0 {
            invulnerability = max(0, invulnerability - dt)
        }
    }
    
    func consumeShield() -> Bool {
        if shieldCharges > 0 {
            shieldCharges -= 1
            invulnerability = 0.7
            return true
        }
        return false
    }
    
    func reset() {
        bullets.removeAll()
        powerups.removeAll()
        shieldCharges = 0
        invulnerability = 0
        fireAccumulator = 0
        powerupTimer = 0
    }
    
    // MARK: - Computed Properties
    
    var invulnerabilityPulse: Double {
        guard invulnerability > 0 else { return 0 }
        let t = CACurrentMediaTime()
        return (sin(t * 10) * 0.5 + 0.5)
    }
}
