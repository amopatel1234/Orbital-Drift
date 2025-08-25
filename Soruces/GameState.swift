//
//  GameState.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//
import SwiftUI
import Observation
import QuartzCore

@MainActor
@Observable
final class GameState {
    
    // MARK: - Published state
    var phase: GamePhase = .menu
    var score: Int = 0
    var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    
    var toasts: [KillToast] = []
    
    var player = Player()
    var asteroids: [Asteroid] = []
    var particles: [Particle] = []
    var powerups: [Powerup] = []
    var shockwaves: [Shockwave] = []  // expanding ring FX
    // Bullets
    var bullets: [Bullet] = []
    
    // Score multiplier (from near-misses)
    var scoreMultiplier: Double = 1.0
    private let maxMultiplier: Double = 3.0
    private let nearMissBoost: Double = 0.25
    private let multiplierDecayPerSec: Double = 0.25
    
    // Firing cadence
    private var fireAccumulator: TimeInterval = 0
    var fireRate: Double = 6.0  // shots per second (tune 5–10)
    
    // Shields / i-frames
    var shieldCharges: Int = 0
    let maxShields: Int = 5
    var invulnerability: TimeInterval = 0 // seconds of i-frames
    
    // World / control
    var worldCenter: CGPoint = .zero
    var orbitRadiusRange: ClosedRange<CGFloat> = 90...150
    
    // Juice
    var shake: CGFloat = 0
    var nearMissFlash: Double = 0
    
    /// For pulsing shield halo in the renderer
    var invulnerabilityPulse: Double {
        guard invulnerability > 0 else { return 0 }
        let t = CACurrentMediaTime()
        return (sin(t * 10) * 0.5 + 0.5)
    }
    
    // MARK: - Input smoothing (prevents tap-to-teleport)
    var targetAngle: CGFloat = .pi / 2
    var targetRadius: CGFloat = 120
    private var isGrabbing = false
    
    // Tuning
    private let grabTolerance: CGFloat = 60     // px from ship to "pick up" control
    private let maxTurnRate: CGFloat = 4.2      // radians/sec (angular speed toward target)
    private let maxRadialSpeed: CGFloat = 180   // px/sec (radius change speed)
    
    // MARK: - Timing
    private var lastUpdate: TimeInterval = 0
    private var spawnAccumulator: TimeInterval = 0
    private var powerupTimer: TimeInterval = 0
    private var scoreAccumulator: TimeInterval = 0
    
    // MARK: - Difficulty
    private var spawnInterval: TimeInterval = 0.9
    private var minSpawnInterval: TimeInterval = 0.25
    
    // Near-miss
    private let nearMissThreshold: CGFloat = 14
    private var lastNearMissAt: TimeInterval = 0
    
    // MARK: - Lifecycle
    func reset(in size: CGSize) {
        worldCenter = CGPoint(x: size.width/2, y: size.height/2)
        
        player = Player(angle: .pi/2, radius: 120)
        targetAngle = player.angle
        targetRadius = player.radius
        isGrabbing = false
        
        bullets.removeAll()
        fireAccumulator = 0
        
        asteroids.removeAll()
        particles.removeAll()
        powerups.removeAll()
        shockwaves.removeAll()
        
        shieldCharges = 0
        invulnerability = 0
        score = 0
        
        spawnInterval = 0.9
        spawnAccumulator = 0
        powerupTimer = 0
        scoreAccumulator = 0
        scoreMultiplier = 1.0
        lastUpdate = 0
        
        phase = .playing
    }
    
    // MARK: - Main loop
    func update(now: TimeInterval, size: CGSize) {
        guard phase == .playing else {
            lastUpdate = now
            return
        }
        if lastUpdate == 0 { lastUpdate = now }
        var dt = now - lastUpdate
        lastUpdate = now
        dt = min(max(dt, 0), 1.0/30.0) // clamp big spikes
        
        // Decay multiplier gently back toward 1
        if scoreMultiplier > 1.0 {
            scoreMultiplier = max(1.0, scoreMultiplier - multiplierDecayPerSec * dt)
        }
        
        // --- Auto-fire toward world center ---
        fireAccumulator += dt
        let fireInterval = 1.0 / fireRate
        while fireAccumulator >= fireInterval {
            fireAccumulator -= fireInterval
            
            let p = playerPosition()
            let dir = Vector2(x: worldCenter.x - p.x,
                              y: worldCenter.y - p.y).normalized()
            let speed: CGFloat = 420
            let vel = dir * speed
            
            bullets.append(Bullet(
                pos: .init(x: p.x, y: p.y),
                vel: vel,
                life: 1.2,
                size: 3.5
            ))
            emitBurst(at: p, count: 4, speed: 120...220)   // tiny white spark when shooting
        }
        
        // Tick invulnerability
        if invulnerability > 0 { invulnerability = max(0, invulnerability - dt) }
        
        // Smoothly steer toward targets (prevents teleporting)
        let dAngle = shortestAngleDiff(from: player.angle, to: targetAngle)
        let maxStep = maxTurnRate * dt
        let step = max(min(dAngle, maxStep), -maxStep)
        player.angle = normalizeAngle(player.angle + step)
        
        let dRad = targetRadius - player.radius
        let maxRadStep = maxRadialSpeed * dt
        let rStep = max(min(dRad, maxRadStep), -maxRadStep)
        player.radius += rStep
        
        // Move asteroids
        for i in asteroids.indices {
            asteroids[i].pos.x += asteroids[i].vel.x * dt
            asteroids[i].pos.y += asteroids[i].vel.y * dt
        }
        
        // --- Bullets step ---
        for i in bullets.indices {
            bullets[i].pos = bullets[i].pos + bullets[i].vel * dt
            bullets[i].life -= CGFloat(dt)
        }
        bullets.removeAll { $0.life <= 0 }
        
        // Cull off-screen or dead
        let pad: CGFloat = 60
        asteroids.removeAll { a in
            a.pos.x < -pad || a.pos.x > size.width + pad ||
            a.pos.y < -pad || a.pos.y > size.height + pad ||
            !a.alive
        }
        
        // Spawn logic
        spawnAccumulator += dt
        if spawnAccumulator >= spawnInterval {
            spawnAccumulator = 0
            spawnAsteroid(size: size)
            spawnInterval = max(minSpawnInterval, spawnInterval - dt * 0.02)
        }
        
        // Powerup spawns (simple timer/coin-flip)
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
        
        // Particles update
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.x * dt
            particles[i].pos.y += particles[i].vel.y * dt
            particles[i].life -= CGFloat(dt * 1.8)
        }
        particles.removeAll { $0.life <= 0 }
        
        // Shockwaves update
        for i in shockwaves.indices {
            shockwaves[i].age += CGFloat(dt * 1.6)
        }
        shockwaves.removeAll { $0.age >= 1 }
        
        // --- Kill toast update ---
        for i in toasts.indices { toasts[i].age += CGFloat(dt) }
        toasts.removeAll { $0.age >= $0.lifetime }
        
        // Collisions + near-miss
        let playerPos = playerPosition()
        var collided = false
        
        for i in asteroids.indices {
            let d = (asteroids[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            let hitDist = (player.size + asteroids[i].size)
            
            if d < hitDist {
                // Already invulnerable: delete asteroid and pass through
                if invulnerability > 0 {
                    asteroids[i].alive = false
                    continue
                }
                
                if shieldCharges > 0 {
                    // SHIELD SAVE
                    shieldCharges -= 1
                    invulnerability = 0.7
                    asteroids[i].alive = false
                    
                    emitBurst(at: playerPos, count: 24, speed: 160...260)
                    emitShockwave(at: playerPos, maxRadius: 90)
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.shieldSave()
                    
                    // Knockback and keep targets aligned so smoothing doesn't pull back
                    player.radius = min(player.radius + 10, orbitRadiusRange.upperBound)
                    targetRadius = player.radius
                    
                    score += 10
                    continue
                } else {
                    collided = true
                    break
                }
            } else if d < hitDist + nearMissThreshold, now - lastNearMissAt > 0.35 {
                lastNearMissAt = now
                // Increase multiplier instead of flat points
                scoreMultiplier = min(maxMultiplier, scoreMultiplier + nearMissBoost)
                nearMissFlash = 1
                withAnimation(.easeOut(duration: 0.25)) { shake = 6 }
                Haptics.shared.nearMiss()
                SoundSynth.shared.nearMiss()
                emitBurst(at: playerPos, count: 6, speed: 50...120)
                
                // belt-and-suspenders: stay in playing
                if phase != .playing { phase = .playing }
            }
        }
        
        let ship = Vector2(x: playerPosition().x, y: playerPosition().y)
        for i in asteroids.indices where asteroids[i].type == .evader {
            let away = (asteroids[i].pos - ship).normalized()
            let evade: CGFloat = 40   // tweak feel (30–60 works well)
            asteroids[i].pos.x += away.x * evade * dt
            asteroids[i].pos.y += away.y * evade * dt
        }
        
        // --- Bullet hits ---
        if !bullets.isEmpty && !asteroids.isEmpty {
            for bi in bullets.indices where bullets[bi].life > 0 {
                for ai in asteroids.indices where asteroids[ai].alive {
                    if asteroids[ai].pos.distance(to: bullets[bi].pos) <
                        (asteroids[ai].size + bullets[bi].size) {
                        
                        bullets[bi].life = 0
                        asteroids[ai].hp -= 1
                        
                        emitBurst(at: CGPoint(x: CGFloat(asteroids[ai].pos.x),
                                              y: CGFloat(asteroids[ai].pos.y)),
                                  count: 8,
                                  speed: 80...160,
                                  color: asteroids[ai].type.color)
                        if asteroids[ai].hp <= 0 {
                            asteroids[ai].alive = false
                            // (Your scoring code stays as-is; it will award on death.)
                            let base = asteroids[ai].type.scoreValue 
                            let gained = Int(Double(base) * scoreMultiplier)
                            score += gained

                            let hitPoint = CGPoint(x: CGFloat(asteroids[ai].pos.x), y: CGFloat(asteroids[ai].pos.y))
                            emitKillToast(at: hitPoint, value: gained, color: asteroids[ai].type.color)

                            SoundSynth.shared.pickup()
                        } else {
                            // Optional: a lighter “hit” sound for non-lethal hits
                            SoundSynth.shared.nearMiss()
                        }
                        break
                    }
                }
            }
        }
        
        // Powerup collect (stack to 5)
        for i in powerups.indices {
            let d = (powerups[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            if d < (player.size + powerups[i].size) {
                powerups[i].alive = false
                if shieldCharges < maxShields {
                    shieldCharges += 1
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.pickup()
                    emitBurst(at: playerPos, count: 10, speed: 80...140)
                } else {
                    emitBurst(at: playerPos, count: 6, speed: 60...120)
                }
            }
        }
        powerups.removeAll { !$0.alive }
        
        if collided {
            player.isAlive = false
            phase = .gameOver
            highScore = max(highScore, score)
            UserDefaults.standard.set(highScore, forKey: "highScore")
            Haptics.shared.crash()
            SoundSynth.shared.crash()
        }
        
        // Fade juice
        nearMissFlash = max(0, nearMissFlash - dt*3.0)
        shake = max(0, shake - CGFloat(dt*16))
    }
    
    // MARK: - Input
    func inputDrag(_ value: DragGesture.Value) {
        guard phase == .playing else { return }
        
        if !isGrabbing {
            // Require the gesture to start near the current ship position
            let start = value.startLocation
            let ship = playerPosition()
            let startDist = hypot(start.x - ship.x, start.y - ship.y)
            if startDist > grabTolerance { return } // ignore stray taps
            isGrabbing = true
        }
        
        // Update targets based on finger location
        let v = Vector2(x: value.location.x - worldCenter.x, y: value.location.y - worldCenter.y)
        targetAngle = atan2(v.y, v.x)
        
        let dist = v.length()
        let clamped = min(max(dist, orbitRadiusRange.lowerBound), orbitRadiusRange.upperBound)
        targetRadius = clamped
    }
    
    func endDrag() {
        isGrabbing = false
    }
    
    // MARK: - Spawns & FX
    func spawnAsteroid(size: CGSize) {
        // Spawn from a random edge
        let edge = Int.random(in: 0..<4)
        var pos = CGPoint.zero
        switch edge {
        case 0: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
        case 1: pos = CGPoint(x: size.width + 20, y: CGFloat.random(in: 0...size.height))
        case 2: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 20)
        default: pos = CGPoint(x: -20, y: CGFloat.random(in: 0...size.height))
        }
        
        // Weighted type selection
        let r = Double.random(in: 0...1)
        let type: EnemyType = (r < 0.65) ? .small : (r < 0.90) ? .big : .evader
        
        // Aim roughly at the center (with a little randomness)
        let jitter: CGFloat = 40
        let target = CGPoint(
            x: worldCenter.x + CGFloat.random(in: -jitter...jitter),
            y: worldCenter.y + CGFloat.random(in: -jitter...jitter)
        )
        let dir = CGVector(dx: target.x - pos.x, dy: target.y - pos.y)
        let len = max(1, sqrt(dir.dx*dir.dx + dir.dy*dir.dy))
        
        // Type-specific stats
        let speed: CGFloat
        let hp: Int
        let radius: CGFloat
        switch type {
        case .small:
            speed = CGFloat.random(in: 100...170)
            hp = 1
            radius = 10
        case .big:
            speed = CGFloat.random(in: 60...110)
            hp = 3
            radius = 18
        case .evader:
            speed = CGFloat.random(in: 100...160)
            hp = 2
            radius = 12
        }
        
        let vel = Vector2(x: (dir.dx/len) * speed, y: (dir.dy/len) * speed)
        
        asteroids.append(Asteroid(
            pos: .init(x: pos.x, y: pos.y),
            vel: vel,
            size: radius,
            alive: true,
            type: type,
            hp: hp
        ))
    }
    
    func emitBurst(at p: CGPoint,
                   count: Int = 12,
                   speed: ClosedRange<CGFloat> = 90...180,
                   color: Color = .white) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2*CGFloat.pi))
            let s = CGFloat.random(in: speed)
            particles.append(Particle(
                pos: .init(x: p.x, y: p.y),
                vel: .init(x: cos(a)*s, y: sin(a)*s),
                life: 1,
                color: color
            ))
        }
    }
    
    func emitShockwave(at p: CGPoint, maxRadius: CGFloat = 80) {
        shockwaves.append(Shockwave(pos: .init(x: p.x, y: p.y), age: 0, maxRadius: maxRadius))
    }
    
    func emitKillToast(at p: CGPoint, value: Int, color: Color) {
        toasts.append(KillToast(pos: .init(x: p.x, y: p.y), value: value, color: color))
    }
    
    // MARK: - Geometry
    func playerPosition() -> CGPoint {
        let x = worldCenter.x + cos(player.angle) * player.radius
        let y = worldCenter.y + sin(player.angle) * player.radius
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Pause
    func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default: break
        }
    }
    
    // MARK: - Helpers (angles)
    private func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var x = a
        while x <= -.pi { x += 2 * .pi }
        while x >   .pi { x -= 2 * .pi }
        return x
    }
    
    private func shortestAngleDiff(from a: CGFloat, to b: CGFloat) -> CGFloat {
        normalizeAngle(b - a)
    }
}
