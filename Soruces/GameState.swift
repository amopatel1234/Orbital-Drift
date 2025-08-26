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
    private let maxMultiplier: Double = 10.0
    private let multiplierDecayPerSec: Double = 0.08
    
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
    
    /// For pulsing shield halo in the renderer
    var invulnerabilityPulse: Double {
        guard invulnerability > 0 else { return 0 }
        let t = CACurrentMediaTime()
        return (sin(t * 10) * 0.5 + 0.5)
    }
    
    // MARK: - Input smoothing (prevents tap-to-teleport)
    var targetAngle: CGFloat = .pi / 2
    var targetRadius: CGFloat = 120
    
    // Tuning
    private let grabTolerance: CGFloat = 60     // px from ship to "pick up" control
    private let maxTurnRate: CGFloat = 4.2      // radians/sec (angular speed toward target)
    private let maxRadialSpeed: CGFloat = 180   // px/sec (radius change speed)
    
    // MARK: - Controls (now supports both directions; you already use CW + Inner)
    var holdRotateCW: Bool = false
    var holdRotateCCW: Bool = false        // future button
    var holdInnerRadius: Bool = false
    var holdOuterRadius: Bool = false      // future button (not used yet)

    // MARK: - Angular motion (radians)
    var angularVel: CGFloat = 0
    var angularMaxSpeed: CGFloat = 2.4     // cap for rotation speed
    var angularAccel: CGFloat = 7.0        // thrust while held
    var angularDecel: CGFloat = 6.0        // braking when no input
    var angularFriction: CGFloat = 0.8     // small continuous drag (per second)

    // MARK: - Radial motion (points)
    var radialVel: CGFloat = 0
    var radialMaxSpeed: CGFloat = 160      // px/s maximum radial speed
    var radialAccel: CGFloat = 280         // thrust while moving toward target
    var radialDecel: CGFloat = 240         // braking when overshooting/letting go
    var radialFriction: CGFloat = 0.85     // small continuous drag (per second)
    

    // MARK: - Orbit bounds
    let minOrbit: CGFloat = 60
    let maxOrbit: CGFloat = 160
    
    private var lastOrbitBumpTime: CFTimeInterval = 0
    private let orbitBumpCooldown: CFTimeInterval = 0.25
    
    // MARK: - Timing
    private var lastUpdate: TimeInterval = 0
    private var powerupTimer: TimeInterval = 0
    private var scoreAccumulator: TimeInterval = 0
    
    // MARK: - Spawn pacing
    private var elapsed: TimeInterval = 0
    private var spawnAcc: TimeInterval = 0

    /// Base spawns-per-second at t=0
    var baseSpawnRate: Double = 0.6
    /// Extra spawns/sec added over the first `rampDuration` seconds
    var rampSpawnBonus: Double = 1.2
    /// Seconds to reach full ramp
    var rampDuration: Double = 60
    /// Grace period with lighter cap
    var gracePeriod: Double = 8

    // Frame-time smoothing (EMA)
    private var emaFrameMs: Double = 16.7   // start near 60fps
    var debugFrameMs: Double {
        emaFrameMs
    }
    private let emaAlpha: Double = 0.12
    private let targetFrameMs: Double = 16.7 // aim for 60fps budget

    // Auto particle budget (0.3 ... 1.0)
    var particleBudgetScale: CGFloat = 1.0
    let maxParticles: Int = 800
    
    // MARK: - Lifecycle
    func reset(in size: CGSize) {
        worldCenter = CGPoint(x: size.width/2, y: size.height/2)
        
        player = Player(angle: .pi/2, radius: maxOrbit)
        targetAngle = player.angle
        targetRadius = player.radius
        
        angularVel = 0
        radialVel  = 0
        
        bullets.removeAll()
        fireAccumulator = 0
        
        asteroids.removeAll()
        particles.removeAll()
        powerups.removeAll()
        shockwaves.removeAll()
        
        shieldCharges = 0
        invulnerability = 0
        score = 0
        
        powerupTimer = 0
        scoreAccumulator = 0
        scoreMultiplier = 1.0
        lastUpdate = 0
        
        elapsed = 0
        spawnAcc = 0
        
        phase = .playing
    }
    
    // MARK: - Main loop
    func update(now: TimeInterval, size: CGSize) {
        guard phase == .playing else {
            lastUpdate = now
            return
        }

        if lastUpdate == 0 {
            lastUpdate = now
        }
        let rawDt = now - lastUpdate        // un-clamped
        lastUpdate = now

        // Clamp for simulation stability (as before)
        var dt = rawDt
        dt = min(max(dt, 0), 1.0/30.0)

        elapsed += dt

        // Current spawn rate (spawns/sec), smoothly ramps up
        let ramp = min(1.0, elapsed / rampDuration)
        let spawnRate = baseSpawnRate + ramp * rampSpawnBonus
        let spawnInterval = 1.0 / spawnRate

        spawnAcc += dt

        // Cap enemies; slightly lower cap during grace period
        let cap = (elapsed < gracePeriod) ? max(3, maxEnemies(now: elapsed) - 2) : maxEnemies(now: elapsed)

        while spawnAcc >= spawnInterval {
            spawnAcc -= spawnInterval
            if asteroids.count(where: { $0.alive }) < cap {
                spawnAsteroid(size: size)
            }
        }
        
        // --- Perf: EMA frame time (ms) & budget ---
        let ms = rawDt * 1000.0
        emaFrameMs = emaFrameMs * (1.0 - emaAlpha) + ms * emaAlpha

        // Budget scale rises toward 1 when under budget, dips when over
        let target = targetFrameMs
        let scale = max(0.3, min(1.0, target / max(1.0, emaFrameMs)))
        // Ease changes a bit to avoid pops
        particleBudgetScale = particleBudgetScale * 0.85 + CGFloat(scale) * 0.15
        
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
        
        // === Momentum-based ANGLE ===
        // Input: +1 = CCW, -1 = CW
        let turnInput: CGFloat = (holdRotateCCW ? 1 : 0) - (holdRotateCW ? 1 : 0)
        let turnTargetSpeed = turnInput * angularMaxSpeed

        if turnInput != 0 {
            // Thrust toward target speed
            let delta = turnTargetSpeed - angularVel
            let maxDelta = angularAccel * CGFloat(dt)
            angularVel += max(-maxDelta, min(maxDelta, delta))
        } else {
            // No input: brake toward 0
            let sign = angularVel >= 0 ? 1 : -1
            let mag = abs(angularVel)
            let newMag = max(0, mag - angularDecel * CGFloat(dt))
            angularVel = CGFloat(sign) * newMag
        }

        // Continuous tiny drag (prevents endless micro-oscillation)
        angularVel *= pow(angularFriction, CGFloat(dt))

        // Integrate
        player.angle += angularVel * CGFloat(dt)


        // === Radius spring toward sticky target ===
        let desiredRadius = targetRadius

        // Critically damped spring
        let k: CGFloat = 22.0
        let c: CGFloat = 2 * sqrt(k)
        let x = player.radius
        let v = radialVel
        let a = -k * (x - desiredRadius) - c * v

        radialVel += a * CGFloat(dt)
        player.radius += radialVel * CGFloat(dt)

        // Clamp + bump haptic (unchanged)
        player.radius = min(max(player.radius, minOrbit), maxOrbit)
        let bumpedMin = player.radius <= minOrbit + 0.001
        let bumpedMax = player.radius >= maxOrbit - 0.001
        if (bumpedMin || bumpedMax), now - lastOrbitBumpTime > orbitBumpCooldown {
            orbitBumpHaptic()
            lastOrbitBumpTime = now
        }
        
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
                            // 1) Score first (based on *current* multiplier)
                            let base = asteroids[ai].type.scoreValue
                            let gained = Int(Double(base) * scoreMultiplier)
                            score += gained

                            // 2) Then bump multiplier based on enemy difficulty
                            let boost = multiplierBoost(for: asteroids[ai].type)
                            scoreMultiplier = min(maxMultiplier, scoreMultiplier + boost)
                            
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
        shake = max(0, shake - CGFloat(dt*16))
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
        // Scale count by current budget (ceil so at least 1 when asked)
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

        // Soft cap to avoid runaway
        if particles.count > maxParticles {
            let overflow = particles.count - maxParticles
            particles.removeFirst(overflow)
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
    
    /// Max concurrent enemies as a function of time
    func maxEnemies(now t: TimeInterval) -> Int {
        // e.g. start 5 → 10 over 60s
        let start = 5
        let end = 10
        let k = min(1.0, t / 60.0)
        return Int(round(Double(start) + (Double(end - start) * k)))
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
    
    private func orbitBumpHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        gen.impactOccurred(intensity: 0.6)
    }
    
    func setInnerPress(_ pressing: Bool) {
        holdInnerRadius = pressing
        targetRadius = pressing ? minOrbit : player.radius   // release: lock to current
    }

    func setOuterPress(_ pressing: Bool) {
        holdOuterRadius = pressing
        targetRadius = pressing ? maxOrbit : player.radius   // release: lock to current
    }
    
    private func multiplierBoost(for type: EnemyType) -> Double {
        switch type {
        case .small:  return 0.12   // easiest → smallest boost
        case .evader: return 0.18   // medium
        case .big:    return 0.25   // hardest → biggest boost
        }
    }
}
